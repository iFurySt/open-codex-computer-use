#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path, records):
    path.write_text(
        "\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n"
    )


def make_recording(root, name, events, manifest=None, mcp_transcript=None, suppressed_events=None):
    recording = root / name
    recording.mkdir()
    write_jsonl(recording / "events.jsonl", events)
    suppressed_events = suppressed_events or []
    write_jsonl(recording / "suppressed.jsonl", suppressed_events)
    metadata = {
        "sessionId": name,
        "state": "stopped",
        "active": False,
        "endReason": "recording_controls_stopped",
        "eventCount": len(events),
        "suppressedEventCount": len(suppressed_events),
        "eventsPath": "events.jsonl",
        "metadataPath": "metadata.json",
        "sessionPath": "session.json",
        "suppressedEventsPath": "suppressed.jsonl",
    }
    write_json(recording / "metadata.json", metadata)
    write_json(recording / "session.json", metadata)
    if mcp_transcript is not None:
        write_json(recording / "mcp-transcript.json", mcp_transcript)
    if manifest is not None:
        write_json(recording / "fixture-manifest.json", manifest)
    return recording


def fixture_manifest(name, event_count, mcp_transcript=False, suppressed_event_count=0):
    return {
        "fixtureFormatVersion": 1,
        "name": name,
        "source": "official",
        "officialPluginVersion": "record-and-replay 1.0.857",
        "capturedAt": "2026-06-26",
        "importedAt": "2026-06-26",
        "eventCount": event_count,
        "suppressedEventCount": suppressed_event_count,
        "eventTypes": {},
        "files": {
            "metadata": "metadata.json",
            "session": "session.json",
            "events": "events.jsonl",
            "suppressed": "suppressed.jsonl",
            "mcpTranscript": "mcp-transcript.json" if mcp_transcript else None,
        },
        "redaction": {
            "screenshotsCopied": False,
            "mcpTranscriptSanitized": mcp_transcript,
            "preserveAppAttribution": False,
            "textKeys": ["title", "value"],
            "timestampKeys": ["timestamp"],
            "sessionIdKeys": ["sessionId"],
            "pathKeysRewrittenRelative": ["eventsPath"],
        },
    }


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    script = repo / "scripts/check-event-stream-golden-readiness.py"
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        ready_events = [
            {"type": "session.started", "sessionId": "ready"},
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "ready",
                "accessibilityInspectorPayload": {
                    "kind": "full",
                    "diffFromPrevious": False,
                    "renderedText": "<redacted-renderedText:length=10>",
                    "fullTree": ["<redacted-fullTree:length=10>"],
                    "treeLines": ["<redacted-treeLines:length=10>"],
                    "screenshotNeededForContext": False,
                    "screenshotAvailable": False,
                },
            },
            {
                "type": "mouse.click",
                "sessionId": "ready",
                "targetAccessibilityElement": {"role": "AXButton", "title": "<redacted-title:length=4>"},
            },
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "ready",
                "accessibilityInspectorPayload": {
                    "kind": "diff",
                    "diffFromPrevious": True,
                    "renderedText": "<redacted-renderedText:length=10>",
                    "treeLines": ["~ <redacted-treeLines:length=10>"],
                    "cumulativeDiffFromInitial": True,
                    "cumulativeRenderedText": "<redacted-cumulativeRenderedText:length=10>",
                    "cumulativeTreeLines": ["+ <redacted-cumulativeTreeLines:length=10>"],
                    "screenshotNeededForContext": False,
                    "screenshotAvailable": False,
                },
            },
            {"type": "session.ended", "sessionId": "ready", "endReason": "recording_controls_stopped"},
        ]
        ready_suppressed_events = [
            {
                "type": "AX.snapshot.suppressed",
                "reason": "snapshotTooLarge",
                "subsystem": "accessibility",
            }
        ]
        mcp_transcript = {
            "startResponseShape": {"result": {"content": []}},
            "repeatStartResponseShape": {"result": {"content": []}},
            "statusResponseShape": {"result": {"content": []}},
            "stopResponseShape": {"result": {"content": []}},
            "repeatStopResponseShape": {"result": {"content": []}},
            "finalStatusResponseShape": {"result": {"content": []}},
            "transcript": [
                {
                    "direction": "send",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "tools/call",
                        "params": {"name": "event_stream_start", "arguments": {}},
                    },
                },
                {"direction": "receive", "message": {"jsonrpc": "2.0", "id": 1, "result": {"content": []}}},
                {
                    "direction": "send",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 2,
                        "method": "tools/call",
                        "params": {"name": "event_stream_status", "arguments": {}},
                    },
                },
                {"direction": "receive", "message": {"jsonrpc": "2.0", "id": 2, "result": {"content": []}}},
                {
                    "direction": "send",
                    "message": {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "tools/call",
                        "params": {"name": "event_stream_stop", "arguments": {}},
                    },
                },
                {"direction": "receive", "message": {"jsonrpc": "2.0", "id": 3, "result": {"content": []}}},
            ]
        }
        ready = make_recording(
            root,
            "ready",
            ready_events,
            fixture_manifest(
                "ready",
                len(ready_events),
                mcp_transcript=True,
                suppressed_event_count=len(ready_suppressed_events),
            ),
            mcp_transcript=mcp_transcript,
            suppressed_events=ready_suppressed_events,
        )

        ready_result = subprocess.run(
            [
                sys.executable,
                str(script),
                str(ready),
                "--require-fixture-manifest",
                "--require-source",
                "official",
                "--require-official-plugin-version",
                "record-and-replay 1.0.857",
                "--require-session-alias",
                "--require-metadata-counts",
                "--require-handoff-paths",
                "--require-full-ax-payload",
                "--require-diff-payload",
                "--require-cumulative-diff",
                "--require-event-type",
                "mouse.click",
                "--require-end-reason",
                "recording_controls_stopped",
                "--require-suppressed-events",
                "--require-suppressed-event-type",
                "AX.snapshot.suppressed",
                "--require-mcp-transcript",
                "--require-mcp-tool-response",
                "event_stream_start",
                "--require-mcp-tool-response",
                "event_stream_status",
                "--require-mcp-tool-response",
                "event_stream_stop",
                "--require-mcp-response-shape",
                "startResponseShape",
                "--require-mcp-response-shape",
                "statusResponseShape",
                "--require-mcp-response-shape",
                "stopResponseShape",
                "--require-mcp-response-shape",
                "finalStatusResponseShape",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        ready_json = json.loads(ready_result.stdout)
        assert ready_json["ok"] is True
        assert ready_json["recordings"][0]["metadataSessionAliasComplete"] is True
        assert ready_json["recordings"][0]["metadataSessionAliasMatches"] is True
        assert ready_json["recordings"][0]["metadataEventCount"] == len(ready_events)
        assert ready_json["recordings"][0]["metadataEventCountMatches"] is True
        assert ready_json["recordings"][0]["metadataSuppressedEventCount"] == 1
        assert ready_json["recordings"][0]["metadataSuppressedEventCountMatches"] is True
        assert ready_json["recordings"][0]["declaredPaths"]["metadataPath"]["exists"] is True
        assert ready_json["recordings"][0]["declaredPaths"]["eventsPath"]["exists"] is True
        assert ready_json["recordings"][0]["declaredPaths"]["sessionPath"]["exists"] is True
        assert ready_json["recordings"][0]["declaredPaths"]["suppressedEventsPath"]["exists"] is True
        assert ready_json["recordings"][0]["sessionStartedCount"] == 1
        assert ready_json["recordings"][0]["sessionStartedIsFirst"] is True
        assert ready_json["recordings"][0]["endReasons"]["recording_controls_stopped"] >= 1
        assert ready_json["recordings"][0]["hasDiffAXPayload"] is True
        assert ready_json["recordings"][0]["hasFullTreePayload"] is True
        assert ready_json["recordings"][0]["hasCumulativeAXDiff"] is True
        assert ready_json["recordings"][0]["mcpToolResponses"]["event_stream_start"]["hasResult"] is True
        assert ready_json["recordings"][0]["mcpToolResponses"]["event_stream_status"]["hasResult"] is True
        assert ready_json["recordings"][0]["mcpToolResponses"]["event_stream_stop"]["hasResult"] is True
        assert ready_json["recordings"][0]["mcpResponseShapes"]["startResponseShape"]["hasResult"] is True
        assert ready_json["recordings"][0]["mcpResponseShapes"]["statusResponseShape"]["hasResult"] is True
        assert ready_json["recordings"][0]["mcpResponseShapes"]["stopResponseShape"]["hasResult"] is True
        assert ready_json["recordings"][0]["mcpResponseShapes"]["finalStatusResponseShape"]["hasResult"] is True
        assert ready_json["recordings"][0]["suppressedEventCount"] == 1
        assert ready_json["recordings"][0]["suppressedEventTypes"]["AX.snapshot.suppressed"] == 1

        official_ax_events = [
            {"kind": "session.started", "sessionId": "official-ax"},
            {
                "kind": "window.changed",
                "sessionId": "official-ax",
                "ax": {
                    "mode": "fullTree",
                    "textRedacted": True,
                    "textLength": 42,
                },
            },
            {
                "kind": "mouse.click",
                "sessionId": "official-ax",
                "ax": {
                    "mode": "fullTree",
                    "textRedacted": True,
                    "textLength": 42,
                },
            },
            {
                "kind": "session.ended",
                "sessionId": "official-ax",
                "endReason": "recording_controls_stopped",
            },
        ]
        official_ax = make_recording(
            root,
            "official-ax",
            official_ax_events,
            fixture_manifest("official-ax", len(official_ax_events)),
        )
        official_ax_result = subprocess.run(
            [
                sys.executable,
                str(script),
                str(official_ax),
                "--require-full-ax-payload",
                "--require-event-type",
                "mouse.click",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        official_ax_json = json.loads(official_ax_result.stdout)
        assert official_ax_json["recordings"][0]["hasAccessibilityPayload"] is True
        assert official_ax_json["recordings"][0]["hasFullAXPayload"] is True
        assert official_ax_json["recordings"][0]["hasFullTreePayload"] is True

        official_session_alias = make_recording(
            root,
            "official-session-alias",
            ready_events,
            fixture_manifest("official-session-alias", len(ready_events)),
        )
        official_metadata = json.loads((official_session_alias / "metadata.json").read_text())
        official_metadata["startedAt"] = "2026-06-26T00:00:00.000Z"
        official_metadata["endedAt"] = "2026-06-26T00:00:05.000Z"
        write_json(official_session_alias / "metadata.json", official_metadata)
        write_json(
            official_session_alias / "session.json",
            {
                "id": "official-session-alias",
                "startedAt": "2026-06-26T00:00:00.000Z",
                "endedAt": "2026-06-26T00:00:05.000Z",
                "endReason": "recording_controls_stopped",
                "eventsPath": "events.jsonl",
            },
        )
        official_session_alias_result = subprocess.run(
            [
                sys.executable,
                str(script),
                str(official_session_alias),
                "--require-fixture-manifest",
                "--require-session-alias",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        official_session_alias_json = json.loads(official_session_alias_result.stdout)
        assert official_session_alias_json["ok"] is True
        assert official_session_alias_json["recordings"][0]["metadataSessionAliasComplete"] is True
        assert official_session_alias_json["recordings"][0]["metadataSessionAliasMatches"] is True

        def top_level_kind_only(event):
            result = dict(event)
            if "type" in result:
                result["kind"] = result.pop("type")
            return result

        kind_only_events = [top_level_kind_only(event) for event in ready_events]
        kind_only_suppressed = [top_level_kind_only(event) for event in ready_suppressed_events]
        kind_only = make_recording(
            root,
            "kind-only",
            kind_only_events,
            fixture_manifest(
                "kind-only",
                len(kind_only_events),
                suppressed_event_count=len(kind_only_suppressed),
            ),
            suppressed_events=kind_only_suppressed,
        )
        kind_only_result = subprocess.run(
            [
                sys.executable,
                str(script),
                str(kind_only),
                "--require-fixture-manifest",
                "--require-session-alias",
                "--require-metadata-counts",
                "--require-handoff-paths",
                "--require-full-ax-payload",
                "--require-diff-payload",
                "--require-cumulative-diff",
                "--require-event-type",
                "mouse.click",
                "--require-end-reason",
                "recording_controls_stopped",
                "--require-suppressed-events",
                "--require-suppressed-event-type",
                "AX.snapshot.suppressed",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        kind_only_json = json.loads(kind_only_result.stdout)
        assert kind_only_json["ok"] is True
        assert kind_only_json["recordings"][0]["eventTypes"]["mouse.click"] == 1
        assert kind_only_json["recordings"][0]["sessionStartedIsFirst"] is True
        assert kind_only_json["recordings"][0]["sessionEndedIsFinal"] is True
        assert kind_only_json["recordings"][0]["suppressedEventTypes"]["AX.snapshot.suppressed"] == 1

        lifecycle_events = [
            {"type": "session.started", "sessionId": "lifecycle"},
            {"type": "session.ended", "sessionId": "lifecycle", "endReason": "recording_controls_stopped"},
        ]
        lifecycle = make_recording(root, "lifecycle", lifecycle_events, fixture_manifest("lifecycle", len(lifecycle_events)))
        missing_session_alias = make_recording(
            root,
            "missing-session-alias",
            lifecycle_events,
            fixture_manifest("missing-session-alias", len(lifecycle_events)),
        )
        (missing_session_alias / "session.json").unlink()
        missing_session_alias_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(missing_session_alias),
                "--require-fixture-manifest",
                "--require-session-alias",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_session_alias_failure.returncode == 1
        missing_session_alias_json = json.loads(missing_session_alias_failure.stderr)
        assert "missing session.json alias" in missing_session_alias_json["recordings"][0]["errors"]
        assert missing_session_alias_json["recordings"][0]["metadataSessionAliasComplete"] is False
        assert missing_session_alias_json["recordings"][0]["metadataSessionAliasMatches"] is None

        mismatched_session_alias = make_recording(
            root,
            "mismatched-session-alias",
            lifecycle_events,
            fixture_manifest("mismatched-session-alias", len(lifecycle_events)),
        )
        mismatched_session_json = json.loads((mismatched_session_alias / "session.json").read_text())
        mismatched_session_json["endReason"] = "recording_controls_cancelled"
        write_json(mismatched_session_alias / "session.json", mismatched_session_json)
        mismatched_session_alias_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(mismatched_session_alias),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert mismatched_session_alias_failure.returncode == 1
        mismatched_session_alias_json = json.loads(mismatched_session_alias_failure.stderr)
        assert "metadata.json and session.json differ" in mismatched_session_alias_json["recordings"][0]["errors"]
        assert mismatched_session_alias_json["recordings"][0]["metadataSessionAliasComplete"] is True
        assert mismatched_session_alias_json["recordings"][0]["metadataSessionAliasMatches"] is False

        bad_metadata_count = make_recording(
            root,
            "bad-metadata-count",
            lifecycle_events,
            fixture_manifest("bad-metadata-count", len(lifecycle_events)),
        )
        bad_metadata = json.loads((bad_metadata_count / "metadata.json").read_text())
        bad_metadata["eventCount"] = 99
        write_json(bad_metadata_count / "metadata.json", bad_metadata)
        write_json(bad_metadata_count / "session.json", bad_metadata)
        bad_metadata_count_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(bad_metadata_count),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert bad_metadata_count_failure.returncode == 1
        bad_metadata_count_json = json.loads(bad_metadata_count_failure.stderr)
        assert (
            "eventCount=99 does not match events.jsonl lines=2"
            in bad_metadata_count_json["recordings"][0]["errors"]
        )
        assert bad_metadata_count_json["recordings"][0]["metadataEventCountMatches"] is False

        missing_metadata_counts = make_recording(
            root,
            "missing-metadata-counts",
            lifecycle_events,
            fixture_manifest("missing-metadata-counts", len(lifecycle_events)),
        )
        missing_counts_metadata = json.loads((missing_metadata_counts / "metadata.json").read_text())
        del missing_counts_metadata["eventCount"]
        del missing_counts_metadata["suppressedEventCount"]
        write_json(missing_metadata_counts / "metadata.json", missing_counts_metadata)
        write_json(missing_metadata_counts / "session.json", missing_counts_metadata)
        missing_metadata_counts_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(missing_metadata_counts),
                "--require-fixture-manifest",
                "--require-metadata-counts",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_metadata_counts_failure.returncode == 1
        missing_metadata_counts_json = json.loads(missing_metadata_counts_failure.stderr)
        missing_metadata_count_errors = missing_metadata_counts_json["recordings"][0]["errors"]
        assert "missing metadata eventCount" in missing_metadata_count_errors
        assert "missing metadata suppressedEventCount" in missing_metadata_count_errors
        assert missing_metadata_counts_json["recordings"][0]["metadataEventCountMatches"] is None

        missing_handoff_paths = make_recording(
            root,
            "missing-handoff-paths",
            lifecycle_events,
            fixture_manifest("missing-handoff-paths", len(lifecycle_events)),
        )
        missing_handoff_metadata = json.loads((missing_handoff_paths / "metadata.json").read_text())
        del missing_handoff_metadata["metadataPath"]
        del missing_handoff_metadata["sessionPath"]
        del missing_handoff_metadata["eventsPath"]
        del missing_handoff_metadata["suppressedEventsPath"]
        write_json(missing_handoff_paths / "metadata.json", missing_handoff_metadata)
        write_json(missing_handoff_paths / "session.json", missing_handoff_metadata)
        missing_handoff_paths_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(missing_handoff_paths),
                "--require-fixture-manifest",
                "--require-handoff-paths",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_handoff_paths_failure.returncode == 1
        missing_handoff_paths_json = json.loads(missing_handoff_paths_failure.stderr)
        missing_handoff_path_errors = missing_handoff_paths_json["recordings"][0]["errors"]
        assert "missing metadataPath" in missing_handoff_path_errors
        assert "missing eventsPath" in missing_handoff_path_errors
        assert "missing sessionPath" in missing_handoff_path_errors
        assert "missing suppressedEventsPath" in missing_handoff_path_errors

        bad_session_path = make_recording(
            root,
            "bad-session-path",
            lifecycle_events,
            fixture_manifest("bad-session-path", len(lifecycle_events)),
        )
        bad_session_path_metadata = json.loads((bad_session_path / "metadata.json").read_text())
        bad_session_path_metadata["sessionPath"] = "missing-session.json"
        write_json(bad_session_path / "metadata.json", bad_session_path_metadata)
        write_json(bad_session_path / "session.json", bad_session_path_metadata)
        bad_session_path_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(bad_session_path),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert bad_session_path_failure.returncode == 1
        bad_session_path_json = json.loads(bad_session_path_failure.stderr)
        assert "sessionPath does not exist: missing-session.json" in bad_session_path_json["recordings"][0]["errors"]
        assert bad_session_path_json["recordings"][0]["declaredPaths"]["sessionPath"]["exists"] is False

        bad_events_path = make_recording(
            root,
            "bad-events-path",
            lifecycle_events,
            fixture_manifest("bad-events-path", len(lifecycle_events)),
        )
        bad_events_path_metadata = json.loads((bad_events_path / "metadata.json").read_text())
        bad_events_path_metadata["eventsPath"] = "missing-events.jsonl"
        write_json(bad_events_path / "metadata.json", bad_events_path_metadata)
        write_json(bad_events_path / "session.json", bad_events_path_metadata)
        bad_events_path_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(bad_events_path),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert bad_events_path_failure.returncode == 1
        bad_events_path_json = json.loads(bad_events_path_failure.stderr)
        bad_events_path_errors = bad_events_path_json["recordings"][0]["errors"]
        assert "eventsPath does not exist: missing-events.jsonl" in bad_events_path_errors
        assert any(error.startswith("missing JSONL file: ") for error in bad_events_path_errors)
        assert bad_events_path_json["recordings"][0]["declaredPaths"]["eventsPath"]["exists"] is False

        bad_manifest_suppressed_count = make_recording(
            root,
            "bad-manifest-suppressed-count",
            lifecycle_events,
            fixture_manifest("bad-manifest-suppressed-count", len(lifecycle_events), suppressed_event_count=7),
        )
        bad_manifest_suppressed_count_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(bad_manifest_suppressed_count),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert bad_manifest_suppressed_count_failure.returncode == 1
        bad_manifest_suppressed_count_json = json.loads(bad_manifest_suppressed_count_failure.stderr)
        assert (
            "fixture manifest suppressedEventCount=7 does not match suppressed.jsonl lines=0"
            in bad_manifest_suppressed_count_json["recordings"][0]["errors"]
        )

        missing_suppressed_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(lifecycle),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
                "--require-suppressed-events",
                "--require-suppressed-event-type",
                "AX.snapshot.suppressed",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_suppressed_failure.returncode == 1
        missing_suppressed_json = json.loads(missing_suppressed_failure.stderr)
        missing_suppressed_errors = missing_suppressed_json["recordings"][0]["errors"]
        assert "missing suppressed events" in missing_suppressed_errors
        assert "missing required suppressed event type: AX.snapshot.suppressed" in missing_suppressed_errors

        missing_end_reason_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(lifecycle),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
                "--require-end-reason",
                "recording_controls_cancelled",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_end_reason_failure.returncode == 1
        missing_end_reason_json = json.loads(missing_end_reason_failure.stderr)
        assert (
            "missing required endReason: recording_controls_cancelled"
            in missing_end_reason_json["recordings"][0]["errors"]
        )

        lifecycle_failure = subprocess.run(
            [sys.executable, str(script), str(lifecycle), "--require-fixture-manifest"],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert lifecycle_failure.returncode == 1
        failure_json = json.loads(lifecycle_failure.stderr)
        errors = failure_json["recordings"][0]["errors"]
        assert any("missing action event" in error for error in errors)
        assert any("missing accessibilityInspectorPayload" in error for error in errors)

        missing_start_events = [
            {"type": "mouse.click", "sessionId": "missing-start"},
            {
                "type": "session.ended",
                "sessionId": "missing-start",
                "endReason": "recording_controls_stopped",
            },
        ]
        missing_start = make_recording(
            root,
            "missing-start",
            missing_start_events,
            fixture_manifest("missing-start", len(missing_start_events)),
        )
        missing_start_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(missing_start),
                "--require-fixture-manifest",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_start_failure.returncode == 1
        missing_start_json = json.loads(missing_start_failure.stderr)
        assert "missing session.started event" in missing_start_json["recordings"][0]["errors"]
        assert missing_start_json["recordings"][0]["sessionStartedCount"] == 0

        lifecycle_pass = subprocess.run(
            [
                sys.executable,
                str(script),
                str(lifecycle),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert json.loads(lifecycle_pass.stdout)["ok"] is True

        duplicate_end_events = [
            {"type": "session.started", "sessionId": "duplicate-end"},
            {
                "type": "session.ended",
                "sessionId": "duplicate-end",
                "endReason": "recording_controls_stopped",
            },
            {
                "type": "session.ended",
                "sessionId": "duplicate-end",
                "endReason": "recording_controls_stopped",
            },
        ]
        duplicate_end = make_recording(
            root,
            "duplicate-end",
            duplicate_end_events,
            fixture_manifest("duplicate-end", len(duplicate_end_events)),
        )
        duplicate_end_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(duplicate_end),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert duplicate_end_failure.returncode == 1
        duplicate_end_json = json.loads(duplicate_end_failure.stderr)
        assert "multiple session.ended events" in duplicate_end_json["recordings"][0]["errors"]
        assert duplicate_end_json["recordings"][0]["sessionEndedCount"] == 2
        assert duplicate_end_json["recordings"][0]["sessionEndedIsFinal"] is True

        end_not_final_events = [
            {"type": "session.started", "sessionId": "end-not-final"},
            {
                "type": "session.ended",
                "sessionId": "end-not-final",
                "endReason": "recording_controls_stopped",
            },
            {"type": "debug.error", "sessionId": "end-not-final", "reason": "lateEvent"},
        ]
        end_not_final = make_recording(
            root,
            "end-not-final",
            end_not_final_events,
            fixture_manifest("end-not-final", len(end_not_final_events)),
        )
        end_not_final_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(end_not_final),
                "--require-fixture-manifest",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert end_not_final_failure.returncode == 1
        end_not_final_json = json.loads(end_not_final_failure.stderr)
        assert "session.ended is not the final event" in end_not_final_json["recordings"][0]["errors"]
        assert end_not_final_json["recordings"][0]["sessionEndedCount"] == 1
        assert end_not_final_json["recordings"][0]["sessionEndedIsFinal"] is False

        timeout_transcript = {
            "startResponseShape": {"timeout": 5.0},
            "repeatStartResponseShape": {"timeout": 5.0},
            "transcriptShape": [
                {
                    "direction": "send",
                    "id": 3,
                    "method": "tools/call",
                    "timeout": None,
                },
                {
                    "direction": "receive",
                    "id": None,
                    "method": None,
                    "timeout": 5.0,
                },
            ],
        }
        timeout_fixture = make_recording(
            root,
            "timeout",
            lifecycle_events,
            fixture_manifest("timeout", len(lifecycle_events), mcp_transcript=True),
            mcp_transcript=timeout_transcript,
        )
        timeout_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(timeout_fixture),
                "--require-fixture-manifest",
                "--require-mcp-transcript",
                "--require-mcp-tool-response",
                "event_stream_start",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert timeout_failure.returncode == 1
        timeout_json = json.loads(timeout_failure.stderr)
        timeout_errors = timeout_json["recordings"][0]["errors"]
        assert "MCP tool timed out: event_stream_start" in timeout_errors
        assert timeout_json["recordings"][0]["mcpResponseShapes"]["startResponseShape"]["timedOut"] is True
        assert timeout_json["recordings"][0]["mcpToolResponses"]["event_stream_start"]["timedOut"] is True

        repeat_timeout_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(timeout_fixture),
                "--require-fixture-manifest",
                "--require-mcp-transcript",
                "--require-mcp-response-shape",
                "repeatStartResponseShape",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert repeat_timeout_failure.returncode == 1
        repeat_timeout_json = json.loads(repeat_timeout_failure.stderr)
        repeat_timeout_errors = repeat_timeout_json["recordings"][0]["errors"]
        assert "MCP response shape timed out: repeatStartResponseShape" in repeat_timeout_errors
        assert (
            repeat_timeout_json["recordings"][0]["mcpResponseShapes"]["repeatStartResponseShape"]["timedOut"]
            is True
        )

        mixed_transcript = {
            "startResponseShape": {"result": {"content": []}},
            "repeatStartResponseShape": {"timeout": 5.0},
        }
        mixed_fixture = make_recording(
            root,
            "mixed",
            lifecycle_events,
            fixture_manifest("mixed", len(lifecycle_events), mcp_transcript=True),
            mcp_transcript=mixed_transcript,
        )
        mixed_tool_pass = subprocess.run(
            [
                sys.executable,
                str(script),
                str(mixed_fixture),
                "--require-fixture-manifest",
                "--require-mcp-transcript",
                "--require-mcp-tool-response",
                "event_stream_start",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        mixed_tool_json = json.loads(mixed_tool_pass.stdout)
        assert mixed_tool_json["recordings"][0]["mcpToolResponses"]["event_stream_start"]["hasResult"] is True
        assert mixed_tool_json["recordings"][0]["mcpToolResponses"]["event_stream_start"]["timedOut"] is False
        mixed_shape_failure = subprocess.run(
            [
                sys.executable,
                str(script),
                str(mixed_fixture),
                "--require-fixture-manifest",
                "--require-mcp-transcript",
                "--require-mcp-response-shape",
                "repeatStartResponseShape",
                "--allow-no-action",
                "--allow-no-ax-payload",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert mixed_shape_failure.returncode == 1
        mixed_shape_json = json.loads(mixed_shape_failure.stderr)
        assert (
            "MCP response shape timed out: repeatStartResponseShape"
            in mixed_shape_json["recordings"][0]["errors"]
        )

    print(json.dumps({"ok": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
