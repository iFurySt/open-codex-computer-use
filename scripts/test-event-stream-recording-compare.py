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


def make_recording(
    root,
    name,
    events,
    metadata_overrides=None,
    remove_metadata_keys=None,
    mcp_transcript=None,
    suppressed_events=None,
):
    recording = root / name
    recording.mkdir()
    events_path = recording / "events.jsonl"
    metadata_path = recording / "metadata.json"
    suppressed_path = recording / "suppressed.jsonl"
    write_jsonl(events_path, events)
    suppressed_events = suppressed_events or []
    write_jsonl(suppressed_path, suppressed_events)
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
    if metadata_overrides:
        metadata.update(metadata_overrides)
    for key in remove_metadata_keys or []:
        metadata.pop(key, None)
    write_json(metadata_path, metadata)
    write_json(recording / "session.json", metadata)
    if mcp_transcript is not None:
        write_json(recording / "mcp-transcript.json", mcp_transcript)
    return recording


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        baseline_events = [
            {"type": "session.started", "sessionId": "baseline"},
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "baseline",
                "accessibilityInspectorPayload": {
                    "kind": "full",
                    "diffFromPrevious": False,
                    "fullTree": [
                        "0 window Demo",
                        "1 search text field Alpha",
                    ],
                    "treeLines": [
                        "0 window Demo",
                        "1 search text field Alpha",
                    ],
                },
            },
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "baseline",
                "accessibilityInspectorPayload": {
                    "kind": "diff",
                    "diffFromPrevious": True,
                    "treeLines": [
                        "~ 1 search text field Alpha -> 1 search text field Beta",
                        "+ 2 button Done",
                    ],
                    "cumulativeDiffFromInitial": True,
                    "cumulativeTreeLines": [
                        "+ 2 button Done",
                    ],
                },
            },
            {
                "type": "mouse.click",
                "sessionId": "baseline",
                "location": {"x": 10, "y": 20},
                "targetAccessibilityElement": {
                    "role": "AXButton",
                    "title": "Save",
                    "actions": ["AXPress"],
                },
            },
            {"type": "session.ended", "sessionId": "baseline", "endReason": "recording_controls_stopped"},
        ]
        baseline_suppressed_events = [
            {
                "type": "AX.snapshot.suppressed",
                "reason": "snapshotTooLarge",
                "subsystem": "accessibility",
                "lineCount": 250,
            }
        ]
        mcp_transcript = {
            "startResponseShape": {"result": {"content": [{"type": "text", "textJSON": {"state": "recording"}}]}},
            "repeatStartResponseShape": {
                "result": {"content": [{"type": "text", "textJSON": {"state": "recording"}}]}
            },
            "statusResponseShape": {"result": {"content": [{"type": "text", "textJSON": {"state": "recording"}}]}},
            "stopResponseShape": {"result": {"content": [{"type": "text", "textJSON": {"state": "stopped"}}]}},
            "repeatStopResponseShape": {"result": {"content": [{"type": "text", "textJSON": {"state": "stopped"}}]}},
            "finalStatusResponseShape": {"result": {"content": [{"type": "text", "textJSON": {"state": "stopped"}}]}},
        }
        baseline = make_recording(
            root,
            "baseline",
            baseline_events,
            mcp_transcript=mcp_transcript,
            suppressed_events=baseline_suppressed_events,
        )
        matching = make_recording(
            root,
            "matching",
            baseline_events,
            mcp_transcript=mcp_transcript,
            suppressed_events=baseline_suppressed_events,
        )
        missing_mcp_shape = make_recording(
            root,
            "missing-mcp-shape",
            baseline_events,
            mcp_transcript={
                key: value
                for key, value in mcp_transcript.items()
                if key != "repeatStartResponseShape"
            },
            suppressed_events=baseline_suppressed_events,
        )
        timeout_mcp_shape = make_recording(
            root,
            "timeout-mcp-shape",
            baseline_events,
            mcp_transcript={
                **mcp_transcript,
                "repeatStartResponseShape": {"timeout": 5.0},
            },
            suppressed_events=baseline_suppressed_events,
        )
        schema_mcp_shape = make_recording(
            root,
            "schema-mcp-shape",
            baseline_events,
            mcp_transcript={
                **mcp_transcript,
                "repeatStartResponseShape": {"result": {"content": [{"type": "text"}]}},
            },
            suppressed_events=baseline_suppressed_events,
        )
        metadata_drift = make_recording(
            root,
            "metadata-drift",
            baseline_events,
            remove_metadata_keys=["suppressedEventCount"],
            suppressed_events=baseline_suppressed_events,
        )
        metadata_value_drift = make_recording(
            root,
            "metadata-value-drift",
            baseline_events,
            metadata_overrides={"endReason": "recording_controls_cancelled"},
            suppressed_events=baseline_suppressed_events,
        )
        missing_target = make_recording(root, "missing-target", [
            baseline_events[0],
            baseline_events[1],
            baseline_events[2],
            {
                "type": "mouse.click",
                "sessionId": "candidate",
                "location": {"x": 10, "y": 20},
            },
            baseline_events[4],
        ], suppressed_events=baseline_suppressed_events)
        reordered = make_recording(root, "reordered", [
            baseline_events[0],
            baseline_events[1],
            baseline_events[3],
            baseline_events[2],
        ], suppressed_events=baseline_suppressed_events)
        start_not_first = make_recording(root, "start-not-first", [
            baseline_events[1],
            baseline_events[0],
            baseline_events[2],
            baseline_events[3],
        ], suppressed_events=baseline_suppressed_events)
        missing_ax_diff = make_recording(root, "missing-ax-diff", [
            baseline_events[0],
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "candidate",
                "accessibilityInspectorPayload": {
                    "kind": "full",
                    "diffFromPrevious": False,
                    "treeLines": [
                        "0 standard window Example",
                        "1 search text field Beta",
                    ],
                },
            },
            baseline_events[3],
            baseline_events[4],
        ], suppressed_events=baseline_suppressed_events)
        marker_mismatch = make_recording(root, "marker-mismatch", [
            baseline_events[0],
            baseline_events[1],
            {
                "type": "AX.focusedWindowChanged",
                "sessionId": "candidate",
                "accessibilityInspectorPayload": {
                    "kind": "diff",
                    "diffFromPrevious": True,
                    "treeLines": [
                        "+ 2 button Done",
                    ],
                    "cumulativeDiffFromInitial": True,
                    "cumulativeTreeLines": [
                        "+ 2 button Done",
                    ],
                },
            },
            baseline_events[3],
            baseline_events[4],
        ], suppressed_events=baseline_suppressed_events)
        missing_suppressed = make_recording(root, "missing-suppressed", baseline_events)
        suppressed_schema_drift = make_recording(
            root,
            "suppressed-schema-drift",
            baseline_events,
            suppressed_events=[
                {
                    "type": "AX.snapshot.suppressed",
                    "reason": "snapshotTooLarge",
                }
            ],
        )

        pass_result = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(matching),
                "--require-same-event-sequence",
                "--require-same-schema",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        pass_json = json.loads(pass_result.stdout)
        assert pass_json["ok"] is True
        assert pass_json["eventSequenceEqual"] is True
        assert pass_json["schemaEqual"] is True
        assert pass_json["metadataKeysEqual"] is True
        assert pass_json["metadataKeyDiff"] == {"extraKeys": [], "missingKeys": []}
        assert pass_json["metadataStableValuesEqual"] is True
        assert pass_json["metadataValueDiff"]["changedValues"] == []
        assert pass_json["metadataValueDiff"]["missingKeys"] == []
        assert pass_json["handoffPathEvidence"]["baseline"]["metadataPath"]["exists"] is True
        assert pass_json["handoffPathEvidence"]["baseline"]["sessionPath"]["exists"] is True
        assert pass_json["handoffPathEvidence"]["baseline"]["eventsPath"]["exists"] is True
        assert pass_json["handoffPathEvidence"]["baseline"]["suppressedEventsPath"]["exists"] is True
        assert pass_json["suppressedEventSequenceEqual"] is True
        assert pass_json["suppressedSchemaEqual"] is True
        assert pass_json["baseline"]["suppressedEventCount"] == 1
        assert pass_json["finalSessionEvidence"]["baseline"]["sessionStartedCount"] == 1
        assert pass_json["finalSessionEvidence"]["baseline"]["hasInitialSessionStarted"] is True
        assert pass_json["finalSessionEvidence"]["baseline"]["sessionEndedCount"] == 1
        assert pass_json["finalSessionEvidence"]["baseline"]["hasFinalSessionEnded"] is True
        assert pass_json["finalSessionEvidence"]["baseline"]["endReasons"] == ["recording_controls_stopped"]
        assert pass_json["mcpResponseShapeEvidence"]["baseline"]["repeatStartResponseShape"]["hasResult"] is True
        assert pass_json["mcpResponseShapeEvidence"]["candidate"]["repeatStartResponseShape"]["hasResult"] is True
        assert pass_json["axDiffEvidence"]["baseline"]["diffMarkers"] == ["+", "~"]
        assert pass_json["axDiffEvidence"]["baseline"]["hasFullTree"] is True
        assert pass_json["axDiffEvidence"]["baseline"]["cumulativeDiffMarkers"] == ["+"]
        assert "targetAccessibilityElement.role" in pass_json["semanticFieldEvidence"]["baseline"]["mouse.click"]["presentPaths"]
        assert "accessibilityInspectorPayload.fullTree[]" in pass_json["semanticFieldEvidence"]["baseline"]["AX.focusedWindowChanged"]["presentPaths"]
        assert "accessibilityInspectorPayload.treeLines[]" in pass_json["semanticFieldEvidence"]["baseline"]["AX.focusedWindowChanged"]["presentPaths"]

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
        official_ax_baseline = make_recording(root, "official-ax-baseline", official_ax_events)
        official_ax_candidate = make_recording(root, "official-ax-candidate", official_ax_events)
        official_ax_result = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(official_ax_baseline),
                str(official_ax_candidate),
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        official_ax_json = json.loads(official_ax_result.stdout)
        assert official_ax_json["axDiffEvidence"]["baseline"]["payloadCount"] == 2
        assert official_ax_json["axDiffEvidence"]["baseline"]["hasFullPayload"] is True
        assert official_ax_json["axDiffEvidence"]["baseline"]["hasFullTree"] is True

        suppressed_sequence_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(missing_suppressed),
                "--require-same-suppressed-event-sequence",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert suppressed_sequence_failure.returncode == 1
        suppressed_sequence_report = json.loads(suppressed_sequence_failure.stderr)
        assert "suppressed event type sequence differs" in suppressed_sequence_report["errors"]
        assert suppressed_sequence_report["firstSuppressedEventSequenceDifference"] == {
            "index": 0,
            "baseline": "AX.snapshot.suppressed",
            "candidate": None,
        }

        suppressed_schema_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(suppressed_schema_drift),
                "--require-same-suppressed-schema",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert suppressed_schema_failure.returncode == 1
        suppressed_schema_report = json.loads(suppressed_schema_failure.stderr)
        assert "suppressed event schema differs" in suppressed_schema_report["errors"]
        assert "AX.snapshot.suppressed" in suppressed_schema_report["suppressedSchemaDiff"]
        assert "subsystem" in suppressed_schema_report["suppressedSchemaDiff"]["AX.snapshot.suppressed"]["missingPaths"]

        handoff_path_pass = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(matching),
                "--require-handoff-paths",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert json.loads(handoff_path_pass.stdout)["ok"] is True

        missing_handoff_path = make_recording(
            root,
            "missing-handoff-path",
            baseline_events,
            remove_metadata_keys=["sessionPath"],
            suppressed_events=baseline_suppressed_events,
        )
        missing_handoff_path_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(missing_handoff_path),
                "--require-handoff-paths",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_handoff_path_failure.returncode == 1
        missing_handoff_path_report = json.loads(missing_handoff_path_failure.stderr)
        assert "candidate missing declared handoff path: sessionPath" in missing_handoff_path_report["errors"]
        assert missing_handoff_path_report["handoffPathEvidence"]["candidate"]["sessionPath"]["exists"] is None

        bad_handoff_path = make_recording(
            root,
            "bad-handoff-path",
            baseline_events,
            metadata_overrides={"suppressedEventsPath": "missing-suppressed.jsonl"},
            suppressed_events=baseline_suppressed_events,
        )
        bad_handoff_path_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(bad_handoff_path),
                "--require-handoff-paths",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert bad_handoff_path_failure.returncode == 1
        bad_handoff_path_report = json.loads(bad_handoff_path_failure.stderr)
        assert "candidate declared handoff path does not exist: suppressedEventsPath" in bad_handoff_path_report["errors"]
        assert bad_handoff_path_report["handoffPathEvidence"]["candidate"]["suppressedEventsPath"]["exists"] is False

        mcp_shape_pass = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(matching),
                "--require-mcp-response-shapes",
                "--require-same-mcp-response-schema",
            ],
            cwd=repo,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert json.loads(mcp_shape_pass.stdout)["ok"] is True

        missing_mcp_shape_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(missing_mcp_shape),
                "--require-mcp-response-shapes",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert missing_mcp_shape_failure.returncode == 1
        missing_mcp_shape_report = json.loads(missing_mcp_shape_failure.stderr)
        assert "candidate missing MCP response shape: repeatStartResponseShape" in missing_mcp_shape_report["errors"]

        timeout_mcp_shape_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(timeout_mcp_shape),
                "--require-mcp-response-shapes",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert timeout_mcp_shape_failure.returncode == 1
        timeout_mcp_shape_report = json.loads(timeout_mcp_shape_failure.stderr)
        assert any(
            error.startswith("candidate MCP response shape repeatStartResponseShape hasResult differs")
            for error in timeout_mcp_shape_report["errors"]
        )
        assert any(
            error.startswith("candidate MCP response shape repeatStartResponseShape timedOut differs")
            for error in timeout_mcp_shape_report["errors"]
        )

        schema_mcp_shape_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(schema_mcp_shape),
                "--require-mcp-response-shapes",
                "--require-same-mcp-response-schema",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert schema_mcp_shape_failure.returncode == 1
        schema_mcp_shape_report = json.loads(schema_mcp_shape_failure.stderr)
        assert any(
            error.startswith("candidate MCP response shape repeatStartResponseShape missing schema paths:")
            for error in schema_mcp_shape_report["errors"]
        )

        schema_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(missing_target),
                "--require-same-schema",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert schema_failure.returncode == 1
        schema_report = json.loads(schema_failure.stderr)
        assert schema_report["ok"] is False
        assert "event schema differs" in schema_report["errors"]
        missing_paths = schema_report["schemaDiff"]["mouse.click"]["missingPaths"]
        assert "targetAccessibilityElement" in missing_paths

        metadata_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(metadata_drift),
                "--require-same-metadata-keys",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert metadata_failure.returncode == 1
        metadata_report = json.loads(metadata_failure.stderr)
        assert metadata_report["ok"] is False
        assert "metadata keys differ" in metadata_report["errors"]
        assert metadata_report["metadataKeyDiff"]["missingKeys"] == ["suppressedEventCount"]
        assert metadata_report["metadataKeyDiff"]["extraKeys"] == []

        metadata_value_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(metadata_value_drift),
                "--require-same-metadata-values",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert metadata_value_failure.returncode == 1
        metadata_value_report = json.loads(metadata_value_failure.stderr)
        assert metadata_value_report["ok"] is False
        assert "stable metadata values differ" in metadata_value_report["errors"]
        assert metadata_value_report["metadataValueDiff"]["changedValues"] == [
            {
                "key": "endReason",
                "baseline": "recording_controls_stopped",
                "candidate": "recording_controls_cancelled",
            }
        ]
        assert metadata_value_report["metadataValueDiff"]["missingKeys"] == []

        semantic_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(missing_target),
                "--require-semantic-fields",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert semantic_failure.returncode == 1
        semantic_report = json.loads(semantic_failure.stderr)
        assert semantic_report["ok"] is False
        assert any(
            error.startswith("candidate missing semantic fields for mouse.click:")
            for error in semantic_report["errors"]
        )
        assert "targetAccessibilityElement.role" in semantic_report["errors"][0]

        sequence_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(reordered),
                "--require-same-event-sequence",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert sequence_failure.returncode == 1
        sequence_report = json.loads(sequence_failure.stderr)
        assert sequence_report["ok"] is False
        assert "event type sequence differs" in sequence_report["errors"]
        assert sequence_report["firstEventSequenceDifference"]["index"] == 2

        final_session_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(reordered),
                "--require-final-session-evidence",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert final_session_failure.returncode == 1
        final_session_report = json.loads(final_session_failure.stderr)
        assert final_session_report["ok"] is False
        assert "candidate final event is not session.ended" in final_session_report["errors"]
        assert final_session_report["finalSessionEvidence"]["candidate"]["hasFinalSessionEnded"] is False
        assert final_session_report["finalSessionEvidence"]["candidate"]["lastEventType"] == "AX.focusedWindowChanged"

        start_session_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(start_not_first),
                "--require-final-session-evidence",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert start_session_failure.returncode == 1
        start_session_report = json.loads(start_session_failure.stderr)
        assert start_session_report["ok"] is False
        assert "candidate first event is not session.started" in start_session_report["errors"]
        assert start_session_report["finalSessionEvidence"]["candidate"]["hasInitialSessionStarted"] is False
        assert start_session_report["finalSessionEvidence"]["candidate"]["firstEventType"] == "AX.focusedWindowChanged"

        ax_missing_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(missing_ax_diff),
                "--require-ax-diff-evidence",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert ax_missing_failure.returncode == 1
        ax_missing_report = json.loads(ax_missing_failure.stderr)
        assert "candidate missing AX diff payload" in ax_missing_report["errors"]
        assert "candidate missing cumulative AX diff payload" in ax_missing_report["errors"]

        marker_failure = subprocess.run(
            [
                sys.executable,
                str(repo / "scripts/compare-event-stream-recordings.py"),
                str(baseline),
                str(marker_mismatch),
                "--require-ax-diff-evidence",
                "--require-same-ax-diff-markers",
            ],
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert marker_failure.returncode == 1
        marker_report = json.loads(marker_failure.stderr)
        assert "candidate missing AX diff markers: ~" in marker_report["errors"]

    print(json.dumps({"ok": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
