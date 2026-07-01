#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from typing import Any


RESPONSE_SHAPE_KEYS = {
    "startResponseShape": ("start", "startResponse", "startResponseShape"),
    "statusResponseShape": ("status", "statusResponse", "statusResponseShape"),
    "stopResponseShape": ("stop", "stopResponse", "stopResponseShape"),
    "finalStatusResponseShape": (
        "finalStatus",
        "finalStatusResponse",
        "finalStatusResponseShape",
    ),
    "repeatStartResponseShape": (
        "repeatStart",
        "repeatStartResponse",
        "repeatStartResponseShape",
    ),
    "repeatStopResponseShape": (
        "repeatStop",
        "repeatStopResponse",
        "repeatStopResponseShape",
    ),
}

REQUIRED_HOSTED_SHAPES = (
    "startResponseShape",
    "statusResponseShape",
    "stopResponseShape",
    "finalStatusResponseShape",
)

HANDOFF_PATH_KEYS = (
    "metadataPath",
    "sessionPath",
    "eventsPath",
    "suppressedEventsPath",
    "sessionDirectoryPath",
)


def load_json(path: pathlib.Path, label: str) -> Any:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"missing {label} JSON file: {path}")
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid {label} JSON in {path}:{error.lineno}:{error.colno}: {error.msg}")


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def decode_json_string(value: str) -> Any | None:
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def iter_json_objects(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            if isinstance(child, str):
                decoded = decode_json_string(child)
                if decoded is not None:
                    yield from iter_json_objects(decoded)
                    continue
            yield from iter_json_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_json_objects(child)


def handoff_path_keys(value: Any) -> list[str]:
    return sorted(
        {
            key
            for obj in iter_json_objects(value)
            for key in HANDOFF_PATH_KEYS
            if isinstance(obj.get(key), str) and obj.get(key)
        }
    )


def unwrap_shape(value: Any) -> Any:
    if isinstance(value, dict):
        for key in ("startResponseShape", "statusResponseShape", "stopResponseShape", "finalStatusResponseShape"):
            nested = value.get(key)
            if isinstance(nested, dict):
                return nested
    return value


def as_tool_response_shape(value: Any) -> dict[str, Any]:
    value = unwrap_shape(value)
    if isinstance(value, dict) and any(key in value for key in ("result", "error", "timeout", "eof")):
        return value
    return {
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(value, sort_keys=True, ensure_ascii=False),
                }
            ]
        }
    }


def shape_is_usable(shape: Any) -> bool:
    return isinstance(shape, dict) and ("result" in shape or "error" in shape) and "timeout" not in shape


def extract_capture_value(capture: Any, keys: tuple[str, ...]) -> Any | None:
    if not isinstance(capture, dict):
        return None
    for key in keys:
        if key in capture:
            return capture[key]
    return None


def load_inputs(args: argparse.Namespace) -> dict[str, Any]:
    capture = load_json(args.capture_json, "capture") if args.capture_json else {}
    values: dict[str, Any] = {}
    individual_paths = {
        "startResponseShape": args.start_json,
        "statusResponseShape": args.status_json,
        "stopResponseShape": args.stop_json,
        "finalStatusResponseShape": args.final_status_json,
        "repeatStartResponseShape": args.repeat_start_json,
        "repeatStopResponseShape": args.repeat_stop_json,
    }
    for shape_key, aliases in RESPONSE_SHAPE_KEYS.items():
        if individual_paths[shape_key] is not None:
            values[shape_key] = load_json(individual_paths[shape_key], shape_key)
            continue
        capture_value = extract_capture_value(capture, aliases)
        if capture_value is not None:
            values[shape_key] = capture_value
    if "finalStatusResponseShape" not in values and args.use_stop_as_final_status:
        if "stopResponseShape" in values:
            values["finalStatusResponseShape"] = values["stopResponseShape"]
    return values


def synthetic_transcript(shapes: dict[str, Any]) -> list[dict[str, Any]]:
    calls = [
        ("event_stream_start", "startResponseShape"),
        ("event_stream_status", "statusResponseShape"),
        ("event_stream_stop", "stopResponseShape"),
        ("event_stream_status", "finalStatusResponseShape"),
    ]
    if "repeatStartResponseShape" in shapes:
        calls.insert(1, ("event_stream_start", "repeatStartResponseShape"))
    if "repeatStopResponseShape" in shapes:
        calls.insert(-1, ("event_stream_stop", "repeatStopResponseShape"))
    transcript: list[dict[str, Any]] = []
    for index, (tool_name, shape_key) in enumerate(calls, start=1):
        transcript.append(
            {
                "direction": "send",
                "message": {
                    "jsonrpc": "2.0",
                    "id": index,
                    "method": "tools/call",
                    "params": {"name": tool_name, "arguments": {}},
                },
            }
        )
        transcript.append(
            {
                "direction": "receive",
                "message": {
                    **shapes[shape_key],
                    "id": index,
                    "jsonrpc": "2.0",
                },
            }
        )
    return transcript


def run_packet_check(packet_dir: pathlib.Path, script_name: str) -> dict[str, Any]:
    script = packet_dir / script_name
    completed = subprocess.run(
        [str(script)],
        cwd=str(packet_dir.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    raw = completed.stdout if completed.returncode == 0 else completed.stderr
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = {
            "ok": False,
            "raw": raw.strip(),
        }
    return {
        "ok": completed.returncode == 0,
        "returncode": completed.returncode,
        "result": parsed,
    }


def finalize(args: argparse.Namespace) -> tuple[int, dict[str, Any]]:
    packet_dir = args.packet_dir.resolve()
    contract = load_json(packet_dir / "capture-contract.json", "capture contract")
    inputs_dir = packet_dir / "inputs"
    values = load_inputs(args)
    missing_shapes = [key for key in REQUIRED_HOSTED_SHAPES if key not in values]
    if missing_shapes:
        raise ValueError(
            "missing hosted response JSON for required shapes: " + ", ".join(missing_shapes)
        )

    shapes = {key: as_tool_response_shape(value) for key, value in values.items()}
    unusable_shapes = [
        key
        for key in REQUIRED_HOSTED_SHAPES
        if not shape_is_usable(shapes.get(key))
    ]
    if unusable_shapes:
        raise ValueError(
            "required hosted response shape has no result/error or timed out: "
            + ", ".join(unusable_shapes)
        )

    status_source_key = "stopResponseShape" if args.status_input == "stop" else "finalStatusResponseShape"
    status_input = values[status_source_key]
    found_handoff_keys = handoff_path_keys(status_input)
    if not found_handoff_keys:
        raise ValueError(
            "selected status input does not contain Record & Replay handoff paths: "
            + ", ".join(HANDOFF_PATH_KEYS)
        )

    transcript_required = bool(contract.get("requiresMcpTranscriptInput"))
    transcript = {
        "fixtureFormatVersion": 1,
        "kind": "record-and-replay-hosted-capture-transcript",
        "source": "codex-hosted-record-and-replay",
        "scenario": contract.get("scenario"),
        "requiredHostedResponseShapes": list(REQUIRED_HOSTED_SHAPES),
        **shapes,
        "transcript": synthetic_transcript(shapes),
    }

    status_path = inputs_dir / "event_stream_stop-response.json"
    write_json(status_path, status_input)
    transcript_path = inputs_dir / "mcp-transcript.json"
    if transcript_required:
        write_json(transcript_path, transcript)

    verify_workflow = run_packet_check(packet_dir, "verify-workflow.sh")
    verify_inputs = run_packet_check(packet_dir, "verify-inputs.sh")
    ok = verify_workflow["ok"] and verify_inputs["ok"]
    return (
        0 if ok else 1,
        {
            "ok": ok,
            "stage": "finalize-hosted-capture-packet",
            "packetDir": str(packet_dir),
            "scenario": contract.get("scenario"),
            "statusInputPath": str(status_path),
            "mcpTranscriptInputPath": str(transcript_path) if transcript_required else None,
            "statusInputSource": status_source_key,
            "foundHandoffPathKeys": found_handoff_keys,
            "checkedHostedResponseShapes": list(REQUIRED_HOSTED_SHAPES),
            "verifyWorkflow": verify_workflow,
            "verifyInputs": verify_inputs,
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Finalize an official Record & Replay capture packet from Codex-hosted "
            "event_stream_start/status/stop/final-status JSON responses."
        )
    )
    parser.add_argument("--packet-dir", type=pathlib.Path, required=True)
    parser.add_argument("--capture-json", type=pathlib.Path)
    parser.add_argument("--start-json", type=pathlib.Path)
    parser.add_argument("--status-json", type=pathlib.Path)
    parser.add_argument("--stop-json", type=pathlib.Path)
    parser.add_argument("--final-status-json", type=pathlib.Path)
    parser.add_argument("--repeat-start-json", type=pathlib.Path)
    parser.add_argument("--repeat-stop-json", type=pathlib.Path)
    parser.add_argument(
        "--status-input",
        choices=["stop", "final-status"],
        default="stop",
        help="Which hosted response to write as inputs/event_stream_stop-response.json.",
    )
    parser.add_argument(
        "--use-stop-as-final-status",
        action="store_true",
        help="Use the stop response as finalStatusResponseShape when no final status JSON is available.",
    )
    args = parser.parse_args()
    try:
        exit_code, result = finalize(args)
    except ValueError as error:
        print(json.dumps({"ok": False, "errors": [str(error)]}, indent=2, sort_keys=True), file=sys.stderr)
        return 1
    output = json.dumps(result, indent=2, sort_keys=True)
    if exit_code == 0:
        print(output)
    else:
        print(output, file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
