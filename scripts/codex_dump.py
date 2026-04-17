#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mitmproxy import ctx, http


DEFAULT_HOST_PATTERNS = (
    r"(^|\.)chatgpt\.com$",
    r"(^|\.)chat.openai\.com$",
    r"(^|\.)openai\.com$",
)
DEFAULT_PATH_PATTERNS = (
    r"^/backend-api/codex/",
    r"^/backend-api/wham/",
    r"^/backend-api/plugins/",
    r"^/backend-api//connectors/",
)
SENSITIVE_HEADERS = {
    "authorization",
    "cookie",
    "set-cookie",
    "proxy-authorization",
    "x-api-key",
}
SENSITIVE_JSON_KEYS = {
    "authorization",
    "access_token",
    "refresh_token",
    "api_key",
    "bearer_token",
    "cookie",
}
TRUNCATE_PREVIEW_BYTES = 240


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _safe_stem(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-") or "flow"


def _redact_header_value(name: str, value: str) -> str:
    if name.lower() in SENSITIVE_HEADERS:
        return "<redacted>"
    return value


def _redact_json(value: Any) -> Any:
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        for key, item in value.items():
            if key.lower() in SENSITIVE_JSON_KEYS:
                redacted[key] = "<redacted>"
            else:
                redacted[key] = _redact_json(item)
        return redacted
    if isinstance(value, list):
        return [_redact_json(item) for item in value]
    return value


def _json_preview(value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if len(text) <= TRUNCATE_PREVIEW_BYTES:
        return text
    return text[:TRUNCATE_PREVIEW_BYTES] + "...<truncated>"


class CodexDump:
    def __init__(self) -> None:
        self.output_dir: Path | None = None
        self.host_patterns: list[re.Pattern[str]] = []
        self.path_patterns: list[re.Pattern[str]] = []
        self.include_http = True
        self.include_ws = True
        self._http_counter = 0
        self._ws_counter = 0
        self._ws_files: dict[str, Path] = {}

    def load(self, loader) -> None:
        loader.add_option(
            name="codex_dump_dir",
            typespec=str,
            default="",
            help="Directory used to persist captured Codex HTTP and WebSocket traffic.",
        )
        loader.add_option(
            name="codex_dump_hosts",
            typespec=str,
            default=",".join(DEFAULT_HOST_PATTERNS),
            help="Comma-separated regex patterns for host allowlist.",
        )
        loader.add_option(
            name="codex_dump_paths",
            typespec=str,
            default=",".join(DEFAULT_PATH_PATTERNS),
            help="Comma-separated regex patterns for request path allowlist.",
        )
        loader.add_option(
            name="codex_dump_include_http",
            typespec=bool,
            default=True,
            help="Whether to persist matching HTTP request/response flows.",
        )
        loader.add_option(
            name="codex_dump_include_ws",
            typespec=bool,
            default=True,
            help="Whether to persist matching WebSocket messages.",
        )

    def configure(self, updated) -> None:
        hosts = [item.strip() for item in ctx.options.codex_dump_hosts.split(",") if item.strip()]
        paths = [item.strip() for item in ctx.options.codex_dump_paths.split(",") if item.strip()]
        self.host_patterns = [re.compile(pattern) for pattern in hosts]
        self.path_patterns = [re.compile(pattern) for pattern in paths]
        self.include_http = bool(ctx.options.codex_dump_include_http)
        self.include_ws = bool(ctx.options.codex_dump_include_ws)

        if ctx.options.codex_dump_dir:
            base_dir = Path(ctx.options.codex_dump_dir).expanduser()
        else:
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            base_dir = Path(tempfile.gettempdir()) / "codex-dumps" / timestamp

        self.output_dir = base_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        (self.output_dir / "http").mkdir(exist_ok=True)
        (self.output_dir / "websocket").mkdir(exist_ok=True)

    def request(self, flow: http.HTTPFlow) -> None:
        if self.include_http and self._matches(flow) and not self._is_ws_upgrade(flow):
            self._persist_http_flow(flow)

    def websocket_start(self, flow: http.HTTPFlow) -> None:
        if not self.include_ws or not self._matches(flow):
            return

        self._ws_counter += 1
        request = flow.request
        path_stem = _safe_stem(request.path.split("?", 1)[0].strip("/"))
        file_path = self.output_dir / "websocket" / f"{self._ws_counter:03d}-{path_stem}.jsonl"
        self._ws_files[flow.id] = file_path

        metadata = {
            "event": "websocket_start",
            "captured_at": _utc_now(),
            "id": flow.id,
            "request": self._serialize_request(request),
        }
        self._append_jsonl(file_path, metadata)
        ctx.log.info(f"codex_dump websocket -> {file_path}")

    def websocket_message(self, flow: http.HTTPFlow) -> None:
        if not self.include_ws or not self._matches(flow):
            return

        file_path = self._ws_files.get(flow.id)
        if file_path is None:
            self.websocket_start(flow)
            file_path = self._ws_files.get(flow.id)
            if file_path is None:
                return

        message = flow.websocket.messages[-1]
        decoded = self._decode_message(message.content)
        payload = {
            "event": "websocket_message",
            "captured_at": _utc_now(),
            "id": flow.id,
            "from_client": bool(message.from_client),
            "is_text": isinstance(decoded, str),
            "size_bytes": len(message.content),
        }

        if isinstance(decoded, str):
            parsed = self._try_parse_json(decoded)
            if parsed is not None:
                redacted = _redact_json(parsed)
                payload["json"] = redacted
                payload["preview"] = _json_preview(redacted)
            else:
                payload["text"] = decoded
                payload["preview"] = decoded[:TRUNCATE_PREVIEW_BYTES]
        else:
            payload["binary_preview_hex"] = decoded[:64].hex()

        self._append_jsonl(file_path, payload)

    def websocket_end(self, flow: http.HTTPFlow) -> None:
        file_path = self._ws_files.pop(flow.id, None)
        if file_path is None:
            return

        payload = {
            "event": "websocket_end",
            "captured_at": _utc_now(),
            "id": flow.id,
            "closed_by_client": getattr(flow.websocket, "closed_by_client", None),
            "close_code": getattr(flow.websocket, "close_code", None),
            "close_reason": getattr(flow.websocket, "close_reason", None),
        }
        self._append_jsonl(file_path, payload)

    def _matches(self, flow: http.HTTPFlow) -> bool:
        request = flow.request
        host = request.pretty_host or request.host or ""
        path = request.path or ""
        return (
            any(pattern.search(host) for pattern in self.host_patterns)
            and any(pattern.search(path) for pattern in self.path_patterns)
        )

    def _is_ws_upgrade(self, flow: http.HTTPFlow) -> bool:
        upgrade = flow.request.headers.get("upgrade", "")
        connection = flow.request.headers.get("connection", "")
        return "websocket" in upgrade.lower() or "upgrade" in connection.lower()

    def _persist_http_flow(self, flow: http.HTTPFlow) -> None:
        self._http_counter += 1
        request = flow.request
        path_stem = _safe_stem(request.path.split("?", 1)[0].strip("/"))
        file_path = self.output_dir / "http" / f"{self._http_counter:03d}-{request.method.lower()}-{path_stem}.json"

        payload = {
            "captured_at": _utc_now(),
            "id": flow.id,
            "request": self._serialize_request(request),
            "response": self._serialize_response(flow.response),
        }
        file_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        ctx.log.info(f"codex_dump http -> {file_path}")

    def _serialize_request(self, request: http.Request) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "method": request.method,
            "scheme": request.scheme,
            "host": request.pretty_host,
            "port": request.port,
            "path": request.path,
            "pretty_url": request.pretty_url,
            "headers": {
                name: _redact_header_value(name, value) for name, value in request.headers.items(multi=True)
            },
        }
        body = self._decode_message(request.raw_content or b"")
        if isinstance(body, str) and body:
            parsed = self._try_parse_json(body)
            payload["body"] = _redact_json(parsed) if parsed is not None else body
        elif isinstance(body, bytes) and body:
            payload["body_binary_preview_hex"] = body[:64].hex()
        return payload

    def _serialize_response(self, response: http.Response | None) -> dict[str, Any] | None:
        if response is None:
            return None

        payload: dict[str, Any] = {
            "status_code": response.status_code,
            "reason": response.reason,
            "headers": {
                name: _redact_header_value(name, value) for name, value in response.headers.items(multi=True)
            },
        }
        body = self._decode_message(response.raw_content or b"")
        if isinstance(body, str) and body:
            parsed = self._try_parse_json(body)
            payload["body"] = _redact_json(parsed) if parsed is not None else body
        elif isinstance(body, bytes) and body:
            payload["body_binary_preview_hex"] = body[:64].hex()
        return payload

    def _try_parse_json(self, value: str) -> Any | None:
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return None

    def _decode_message(self, content: bytes) -> str | bytes:
        if not content:
            return ""
        try:
            return content.decode("utf-8")
        except UnicodeDecodeError:
            return content

    def _append_jsonl(self, file_path: Path, payload: dict[str, Any]) -> None:
        with file_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")


addons = [CodexDump()]
