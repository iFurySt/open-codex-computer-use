#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys
import tempfile

from record_and_replay_scenarios import DEFAULT_REQUIRED_SCENARIOS, scenario_recipe


def run(command, cwd):
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    script = repo / "scripts/prepare-record-and-replay-official-golden-capture.py"
    default_required_scenario = DEFAULT_REQUIRED_SCENARIOS[0]
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = pathlib.Path(tmp)
        fixture_root = tmp_path / "fixtures"
        plugin_root = tmp_path / "record-and-replay"
        skill_dir = plugin_root / "1.0.857/skills/record-and-replay"
        skill_dir.mkdir(parents=True)
        (skill_dir / "SKILL.md").write_text("---\nname: record-and-replay\n---\n")

        missing = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--name",
                "official-simple-action-stop-1.0.857",
            ],
            repo,
        )
        assert missing.returncode == 0, missing.stderr
        missing_json = json.loads(missing.stdout)
        assert missing_json["ok"] is True
        assert missing_json["stage"] == "preflight"
        assert missing_json["officialPlugin"]["available"] is True
        assert missing_json["officialPlugin"]["versions"][0]["version"] == "1.0.857"
        assert missing_json["scenarioStatus"] == {
            "available": False,
            "missing": True,
            "notReady": False,
            "ready": False,
            "scenario": default_required_scenario,
        }
        assert missing_json["coverage"]["missingOfficialScenarios"] == [default_required_scenario]
        assert missing_json["scenarioRecipe"]["priority"] == "required"
        assert missing_json["scenarioRecipe"]["expectedActionEvents"] == ["mouse.click"]
        assert missing_json["scenarioRecipe"]["expectedEndReason"] == "recording_controls_stopped"
        assert missing_json["scenarioRecipe"]["ocuCandidateSourceKind"] == "run-action-smoke"
        assert "commands.inspectOnly" in " ".join(missing_json["nextActions"])
        inspect_cmd = missing_json["commands"]["inspectOnly"]
        assert "--inspect-only" in inspect_cmd
        assert "--mcp-transcript" in inspect_cmd
        assert missing_json["commands"]["strictOfficialGoldenGate"] == [
            "make",
            "record-and-replay-official-golden-gate-audit",
        ]
        assert (
            missing_json["commands"]["strictOfficialGoldenGateShell"]
            == "make record-and-replay-official-golden-gate-audit"
        )
        assert missing_json["commands"]["strictOfficialGoldenExpectedFailureAudit"] == [
            "python3",
            "scripts/check-record-and-replay-baseline-summary.py",
            "dist/record-and-replay-official-golden-gate-summary.json",
            "--allow-strict-official-golden-missing",
        ]
        assert "--allow-strict-official-golden-missing" in (
            missing_json["commands"]["strictOfficialGoldenExpectedFailureAuditShell"]
        )
        assert missing_json["commands"]["inspectOnlyShell"].startswith("python3 ")
        assert missing_json["commands"]["ocuCandidate"][1] == "scripts/ingest-ocu-record-and-replay-candidate.py"
        assert "--run-action-smoke" in missing_json["commands"]["ocuCandidate"]
        assert "--output-dir" in missing_json["commands"]["ocuCandidate"]
        assert str(fixture_root / "ocu-candidates") in missing_json["commands"]["ocuCandidate"]
        assert "--official-root" in missing_json["commands"]["ocuCandidate"]
        assert str(fixture_root) in missing_json["commands"]["ocuCandidate"]

        packet_dir = tmp_path / "capture-packet"
        capture_packet = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--name",
                "official-simple-action-stop-1.0.857",
                "--capture-packet-dir",
                str(packet_dir),
            ],
            repo,
        )
        assert capture_packet.returncode == 0, capture_packet.stderr
        capture_packet_json = json.loads(capture_packet.stdout)
        assert pathlib.Path(capture_packet_json["capturePacket"]["path"]).resolve() == packet_dir.resolve()
        assert capture_packet_json["capturePacket"]["includeTranscript"] is True
        assert capture_packet_json["capturePacket"]["requiresMcpTranscriptInput"] is True
        assert capture_packet_json["capturePacket"]["statusResponseInputPath"].endswith(
            "inputs/event_stream_stop-response.json"
        )
        assert capture_packet_json["capturePacket"]["mcpTranscriptInputPath"].endswith(
            "inputs/mcp-transcript.json"
        )
        assert any(
            "Replace capture packet input placeholders" in action
            for action in capture_packet_json["nextActions"]
        )
        assert any(
            "capturePacket.verifyInputsShell" in action
            for action in capture_packet_json["nextActions"]
        )
        assert "verifyInputsShell" in capture_packet_json["capturePacket"]
        assert capture_packet_json["capturePacket"]["verifyWorkflowShell"].endswith(
            "verify-workflow.sh"
        )
        assert capture_packet_json["capturePacket"]["checkFixtureSetShell"].endswith(
            "check-fixture-set.sh"
        )
        assert capture_packet_json["capturePacket"]["strictGoldenGateShell"].endswith(
            "strict-golden-gate.sh"
        )
        assert capture_packet_json["capturePacket"][
            "strictExpectedFailureAuditShell"
        ].endswith("strict-expected-failure-audit.sh")
        assert capture_packet_json["capturePacket"]["ingestOcuCandidateShell"].endswith(
            "ingest-ocu-candidate.sh"
        )
        assert "--output-dir" in capture_packet_json["commands"]["ocuCandidate"]
        assert str(fixture_root / "ocu-candidates") in capture_packet_json["commands"]["ocuCandidate"]
        assert (packet_dir / "README.md").exists()
        assert (packet_dir / "preflight.json").exists()
        assert (packet_dir / "capture-contract.json").exists()
        assert (packet_dir / "scenario-recipe.json").exists()
        assert (packet_dir / "inputs/event_stream_stop-response.json").exists()
        assert (packet_dir / "inputs/mcp-transcript.json").exists()
        assert (packet_dir / "verify-inputs.sh").exists()
        assert (packet_dir / "verify-workflow.sh").exists()
        assert (packet_dir / "inspect-only.sh").exists()
        assert (packet_dir / "import-fixture.sh").exists()
        assert (packet_dir / "check-coverage.sh").exists()
        assert (packet_dir / "check-fixture-set.sh").exists()
        assert (packet_dir / "strict-golden-gate.sh").exists()
        assert (packet_dir / "strict-expected-failure-audit.sh").exists()
        assert (packet_dir / "ingest-ocu-candidate.sh").exists()
        assert (packet_dir / "verify-inputs.sh").stat().st_mode & 0o111
        assert (packet_dir / "verify-workflow.sh").stat().st_mode & 0o111
        assert (packet_dir / "inspect-only.sh").stat().st_mode & 0o111
        packet_readme = (packet_dir / "README.md").read_text()
        assert "Record & Replay Official Capture Packet" in packet_readme
        assert "MCP transcript input required: `yes`" in packet_readme
        assert "`capture-contract.json` records the expected scenario" in packet_readme
        assert "`postCaptureWorkflow`" in packet_readme
        assert "`inputs/mcp-transcript.json`: required same-session MCP transcript evidence." in (
            packet_readme
        )
        assert "Do not commit raw official recording JSON" in packet_readme
        assert "./verify-inputs.sh" in packet_readme
        assert "./verify-workflow.sh" in packet_readme
        assert "finalize-record-and-replay-official-capture-packet.py" in packet_readme
        assert "--final-status-json" in packet_readme
        assert "`verify-workflow.sh` checks" in packet_readme
        assert "./check-fixture-set.sh" in packet_readme
        assert "./strict-golden-gate.sh" in packet_readme
        assert "./strict-expected-failure-audit.sh" in packet_readme
        assert "./ingest-ocu-candidate.sh" in packet_readme
        assert "Equivalent fixture-set gate" in packet_readme
        assert "Equivalent strict golden gate audit" in packet_readme
        assert "Equivalent strict expected-failure audit" in packet_readme
        assert "make record-and-replay-official-golden-gate-audit" in packet_readme
        assert "--allow-strict-official-golden-missing" in packet_readme
        assert "embed the repository path captured when this packet was created" in packet_readme
        assert "REPO_ROOT=/path/to/repo" in packet_readme
        assert "git rev-parse" not in packet_readme
        packet_recipe = json.loads((packet_dir / "scenario-recipe.json").read_text())
        assert packet_recipe == scenario_recipe(default_required_scenario)
        packet_contract = json.loads((packet_dir / "capture-contract.json").read_text())
        assert packet_contract["formatVersion"] == 1
        assert packet_contract["scenario"] == default_required_scenario
        assert packet_contract["expectedActionEvents"] == ["mouse.click"]
        assert packet_contract["expectedEndReason"] == "recording_controls_stopped"
        assert packet_contract["requiresMcpTranscriptInput"] is True
        assert packet_contract["requiredStatusHandoffPathKeys"] == ["eventsPath"]
        assert packet_contract["requiredStatusHandoffAnyOf"] == [
            ["metadataPath", "sessionPath"]
        ]
        assert "suppressedEventsPath" in packet_contract["optionalStatusHandoffPathKeys"]
        assert "startResponseShape" in packet_contract["requiredTranscriptEvidenceKeys"]
        assert "statusResponseShape" in packet_contract["requiredTranscriptEvidenceKeys"]
        assert "stopResponseShape" in packet_contract["requiredTranscriptEvidenceKeys"]
        assert "finalStatusResponseShape" in packet_contract["requiredTranscriptEvidenceKeys"]
        assert "repeatStartResponseShape" not in packet_contract["requiredTranscriptEvidenceKeys"]
        workflow_ids = [step["id"] for step in packet_contract["postCaptureWorkflow"]]
        assert workflow_ids == [
            "replace-status-json",
            "replace-mcp-transcript",
            "verify-inputs",
            "inspect-only",
            "import-fixture",
            "check-coverage",
            "check-fixture-set",
            "ingest-ocu-candidate",
            "strict-golden-gate",
            "strict-expected-failure-audit",
        ]
        assert capture_packet_json["capturePacket"]["postCaptureWorkflow"] == (
            packet_contract["postCaptureWorkflow"]
        )
        assert capture_packet_json["capturePacket"]["captureContractPath"].endswith(
            "capture-contract.json"
        )
        packet_placeholder = json.loads(
            (packet_dir / "inputs/event_stream_stop-response.json").read_text()
        )
        assert packet_placeholder["_placeholder"] is True
        verify_script = (packet_dir / "verify-inputs.sh").read_text()
        assert "Invalid packet JSON" in verify_script
        assert "Packet input still contains placeholder" in verify_script
        workflow_verify = run([str(packet_dir / "verify-workflow.sh")], repo)
        assert workflow_verify.returncode == 0, workflow_verify.stderr
        workflow_verify_json = json.loads(workflow_verify.stdout)
        assert workflow_verify_json["ok"] is True
        assert workflow_verify_json["checkedWorkflow"] is True
        assert workflow_verify_json["checkedWorkflowCommands"] is True
        assert workflow_verify_json["checkedWorkflowInputs"] is True
        mutated_contract = json.loads((packet_dir / "capture-contract.json").read_text())
        for step in mutated_contract["postCaptureWorkflow"]:
            if step["id"] == "inspect-only":
                step["command"] = "./missing-inspect-only.sh"
        (packet_dir / "capture-contract.json").write_text(
            json.dumps(mutated_contract, indent=2, sort_keys=True) + "\n"
        )
        workflow_drift = run([str(packet_dir / "verify-workflow.sh")], repo)
        assert workflow_drift.returncode == 2
        assert "Workflow command" in workflow_drift.stderr
        assert "missing" in workflow_drift.stderr
        (packet_dir / "capture-contract.json").write_text(
            json.dumps(packet_contract, indent=2, sort_keys=True) + "\n"
        )
        inspect_script = (packet_dir / "inspect-only.sh").read_text()
        assert 'default_repo_root=' in inspect_script
        assert '"${packet_dir}/inputs/event_stream_stop-response.json"' in inspect_script
        assert '"${packet_dir}/inputs/mcp-transcript.json"' in inspect_script
        assert "check_replaced_input" in inspect_script
        import_script = (packet_dir / "import-fixture.sh").read_text()
        assert "check_replaced_input" in import_script
        strict_gate_script = (packet_dir / "strict-golden-gate.sh").read_text()
        assert "record-and-replay-official-golden-gate-audit" in strict_gate_script
        assert "record-and-replay-official-golden-gate\n" not in strict_gate_script
        strict_expected_failure_script = (
            packet_dir / "strict-expected-failure-audit.sh"
        ).read_text()
        assert "check-record-and-replay-baseline-summary.py" in strict_expected_failure_script
        assert "--allow-strict-official-golden-missing" in strict_expected_failure_script
        placeholder_verify = run([str(packet_dir / "verify-inputs.sh")], repo)
        assert placeholder_verify.returncode == 2
        assert "Packet input still contains placeholder: event_stream_stop response" in (
            placeholder_verify.stderr
        )
        placeholder_inspect = run([str(packet_dir / "inspect-only.sh")], repo)
        assert placeholder_inspect.returncode == 2
        assert "Packet input still contains placeholder: event_stream_stop response" in (
            placeholder_inspect.stderr
        )
        assert "event_stream_stop-response.json" in placeholder_inspect.stderr
        placeholder_import = run([str(packet_dir / "import-fixture.sh")], repo)
        assert placeholder_import.returncode == 2
        assert "Packet input still contains placeholder: event_stream_stop response" in (
            placeholder_import.stderr
        )
        assert "event_stream_stop-response.json" in placeholder_import.stderr
        (packet_dir / "inputs/event_stream_stop-response.json").write_text("{}\n")
        placeholder_transcript_verify = run([str(packet_dir / "verify-inputs.sh")], repo)
        assert placeholder_transcript_verify.returncode == 2
        assert "Packet input still contains placeholder: MCP transcript" in (
            placeholder_transcript_verify.stderr
        )
        placeholder_transcript_inspect = run([str(packet_dir / "inspect-only.sh")], repo)
        assert placeholder_transcript_inspect.returncode == 2
        assert "Packet input still contains placeholder: MCP transcript" in (
            placeholder_transcript_inspect.stderr
        )
        assert "mcp-transcript.json" in placeholder_transcript_inspect.stderr
        placeholder_transcript_import = run([str(packet_dir / "import-fixture.sh")], repo)
        assert placeholder_transcript_import.returncode == 2
        assert "Packet input still contains placeholder: MCP transcript" in (
            placeholder_transcript_import.stderr
        )
        assert "mcp-transcript.json" in placeholder_transcript_import.stderr
        (packet_dir / "inputs/mcp-transcript.json").write_text("{}\n")
        semantic_status_verify = run([str(packet_dir / "verify-inputs.sh")], repo)
        assert semantic_status_verify.returncode == 2
        assert "Packet status JSON does not contain Record & Replay handoff path evidence" in (
            semantic_status_verify.stderr
        )
        (packet_dir / "inputs/event_stream_stop-response.json").write_text(
            json.dumps(
                {
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(
                                    {
                                        "metadataPath": "/tmp/official-session/metadata.json",
                                        "sessionPath": "/tmp/official-session/session.json",
                                        "eventsPath": "/tmp/official-session/events.jsonl",
                                    }
                                ),
                            }
                        ]
                    }
                }
            )
            + "\n"
        )
        semantic_transcript_verify = run([str(packet_dir / "verify-inputs.sh")], repo)
        assert semantic_transcript_verify.returncode == 2
        assert "Packet MCP transcript does not contain MCP transcript evidence" in (
            semantic_transcript_verify.stderr
        )
        (packet_dir / "inputs/mcp-transcript.json").write_text(
            json.dumps({"stopResponseShape": {"result": {"content": []}}}) + "\n"
        )
        replaced_inputs_verify = run([str(packet_dir / "verify-inputs.sh")], repo)
        assert replaced_inputs_verify.returncode == 0, replaced_inputs_verify.stderr
        replaced_inputs_verify_json = json.loads(replaced_inputs_verify.stdout)
        assert replaced_inputs_verify_json["ok"] is True
        assert replaced_inputs_verify_json["stage"] == "verify-inputs"
        assert replaced_inputs_verify_json["foundHandoffPathKeys"] == [
            "eventsPath",
            "metadataPath",
            "sessionPath",
        ]
        assert replaced_inputs_verify_json["requiredStatusHandoffPathKeys"] == ["eventsPath"]
        assert replaced_inputs_verify_json["requiredStatusHandoffAnyOf"] == [
            ["metadataPath", "sessionPath"]
        ]
        assert replaced_inputs_verify_json["foundTranscriptEvidenceKeys"] == [
            "stopResponseShape"
        ]
        coverage_script = (packet_dir / "check-coverage.sh").read_text()
        assert "check_replaced_input" not in coverage_script

        no_transcript_packet_dir = tmp_path / "capture-packet-no-transcript"
        no_transcript_packet = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--name",
                "official-simple-action-stop-1.0.857",
                "--capture-packet-dir",
                str(no_transcript_packet_dir),
                "--no-include-transcript",
            ],
            repo,
        )
        assert no_transcript_packet.returncode == 0, no_transcript_packet.stderr
        no_transcript_packet_json = json.loads(no_transcript_packet.stdout)
        assert no_transcript_packet_json["capturePacket"]["includeTranscript"] is False
        assert no_transcript_packet_json["capturePacket"]["requiresMcpTranscriptInput"] is False
        no_transcript_workflow_ids = [
            step["id"] for step in no_transcript_packet_json["capturePacket"]["postCaptureWorkflow"]
        ]
        assert "replace-mcp-transcript" not in no_transcript_workflow_ids
        assert no_transcript_workflow_ids[0] == "replace-status-json"
        assert no_transcript_workflow_ids[-1] == "strict-expected-failure-audit"
        assert (
            no_transcript_packet_json["capturePacket"]["statusResponseInputPath"].endswith(
                "inputs/event_stream_stop-response.json"
            )
        )
        assert no_transcript_packet_json["capturePacket"]["mcpTranscriptInputPath"] is None
        assert no_transcript_packet_json["capturePacket"]["checkFixtureSetShell"].endswith(
            "check-fixture-set.sh"
        )
        assert no_transcript_packet_json["capturePacket"]["strictGoldenGateShell"].endswith(
            "strict-golden-gate.sh"
        )
        assert no_transcript_packet_json["capturePacket"][
            "strictExpectedFailureAuditShell"
        ].endswith("strict-expected-failure-audit.sh")
        assert (no_transcript_packet_dir / "inputs/event_stream_stop-response.json").exists()
        assert not (no_transcript_packet_dir / "inputs/mcp-transcript.json").exists()
        assert (no_transcript_packet_dir / "capture-contract.json").exists()
        assert (no_transcript_packet_dir / "verify-workflow.sh").exists()
        no_transcript_workflow_verify = run(
            [str(no_transcript_packet_dir / "verify-workflow.sh")],
            repo,
        )
        assert no_transcript_workflow_verify.returncode == 0, (
            no_transcript_workflow_verify.stderr
        )
        no_transcript_packet_readme = (no_transcript_packet_dir / "README.md").read_text()
        assert "MCP transcript input required: `no`" in no_transcript_packet_readme
        assert "does not create `inputs/mcp-transcript.json`" in no_transcript_packet_readme
        assert "--mcp-transcript" not in (no_transcript_packet_dir / "inspect-only.sh").read_text()
        assert "--mcp-transcript" not in (no_transcript_packet_dir / "import-fixture.sh").read_text()
        no_transcript_placeholder_verify = run(
            [str(no_transcript_packet_dir / "verify-inputs.sh")],
            repo,
        )
        assert no_transcript_placeholder_verify.returncode == 2
        assert "event_stream_stop response" in no_transcript_placeholder_verify.stderr
        assert "MCP transcript" not in no_transcript_placeholder_verify.stderr
        (no_transcript_packet_dir / "inputs/event_stream_stop-response.json").write_text(
            json.dumps(
                {
                    "metadataPath": "/tmp/official-session/metadata.json",
                    "eventsPath": "/tmp/official-session/events.jsonl",
                }
            )
            + "\n"
        )
        no_transcript_replaced_verify = run(
            [str(no_transcript_packet_dir / "verify-inputs.sh")],
            repo,
        )
        assert no_transcript_replaced_verify.returncode == 0, (
            no_transcript_replaced_verify.stderr
        )

        packet_set_dir = tmp_path / "capture-packet-set"
        capture_packet_set = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--capture-packet-dir",
                str(packet_set_dir),
                "--capture-packet-recommended-scenarios",
            ],
            repo,
        )
        assert capture_packet_set.returncode == 0, capture_packet_set.stderr
        capture_packet_set_json = json.loads(capture_packet_set.stdout)
        assert capture_packet_set_json["stage"] == "capture-packet-set"
        assert capture_packet_set_json["scenarios"] == [
            "simple-action-stop",
            "keyboard-input-stop",
            "drag-stop",
            "cancel",
            "timeout",
        ]
        assert (packet_set_dir / "README.md").exists()
        assert (packet_set_dir / "capture-packets.json").exists()
        assert (packet_set_dir / "verify-all.sh").exists()
        assert (packet_set_dir / "verify-workflow.sh").exists()
        assert (packet_set_dir / "inspect-all.sh").exists()
        assert (packet_set_dir / "import-all.sh").exists()
        assert (packet_set_dir / "check-all.sh").exists()
        assert (packet_set_dir / "ingest-ocu-candidates.sh").exists()
        assert (packet_set_dir / "strict-expected-failure-audit.sh").exists()
        assert (packet_set_dir / "verify-all.sh").stat().st_mode & 0o111
        assert (packet_set_dir / "verify-workflow.sh").stat().st_mode & 0o111
        assert (packet_set_dir / "inspect-all.sh").stat().st_mode & 0o111
        assert (packet_set_dir / "import-all.sh").stat().st_mode & 0o111
        assert (packet_set_dir / "check-all.sh").stat().st_mode & 0o111
        assert (packet_set_dir / "ingest-ocu-candidates.sh").stat().st_mode & 0o111
        assert (packet_set_dir / "strict-expected-failure-audit.sh").stat().st_mode & 0o111
        for scenario in capture_packet_set_json["scenarios"]:
            scenario_dir = packet_set_dir / scenario
            assert (scenario_dir / "README.md").exists()
            assert (scenario_dir / "preflight.json").exists()
            assert (scenario_dir / "capture-contract.json").exists()
            assert (scenario_dir / "scenario-recipe.json").exists()
            assert (scenario_dir / "inputs/event_stream_stop-response.json").exists()
            assert (scenario_dir / "verify-inputs.sh").exists()
            assert (scenario_dir / "inspect-only.sh").exists()
            assert (scenario_dir / "import-fixture.sh").exists()
        assert (packet_set_dir / "simple-action-stop/ingest-ocu-candidate.sh").exists()
        assert (packet_set_dir / "drag-stop/ingest-ocu-candidate.sh").exists()
        assert not (packet_set_dir / "keyboard-input-stop/ingest-ocu-candidate.sh").exists()
        assert not (packet_set_dir / "cancel/ingest-ocu-candidate.sh").exists()
        simple_preflight = json.loads((packet_set_dir / "simple-action-stop/preflight.json").read_text())
        assert "--output-dir" in simple_preflight["commands"]["ocuCandidate"]
        assert str(fixture_root / "ocu-candidates") in simple_preflight["commands"]["ocuCandidate"]
        drag_preflight = json.loads((packet_set_dir / "drag-stop/preflight.json").read_text())
        assert "--output-dir" in drag_preflight["commands"]["ocuCandidate"]
        assert str(fixture_root / "ocu-candidates") in drag_preflight["commands"]["ocuCandidate"]
        set_manifest = json.loads((packet_set_dir / "capture-packets.json").read_text())
        assert set_manifest["stage"] == "capture-packet-set"
        assert set_manifest["includeTranscript"] is True
        assert set_manifest["requiresMcpTranscriptInput"] is True
        assert set_manifest["capturePackets"]["simple-action-stop"]["path"]
        assert set_manifest["capturePackets"]["simple-action-stop"]["includeTranscript"] is True
        assert set_manifest["captureContractPaths"]["simple-action-stop"].endswith(
            "simple-action-stop/capture-contract.json"
        )
        assert set_manifest["captureContracts"]["simple-action-stop"]["scenario"] == (
            "simple-action-stop"
        )
        assert set_manifest["postCaptureWorkflow"]["simple-action-stop"] == (
            set_manifest["captureContracts"]["simple-action-stop"]["postCaptureWorkflow"]
        )
        assert set_manifest["postCaptureWorkflow"]["keyboard-input-stop"] == (
            set_manifest["captureContracts"]["keyboard-input-stop"]["postCaptureWorkflow"]
        )
        assert any(
            step["id"] == "ingest-ocu-candidate"
            for step in set_manifest["postCaptureWorkflow"]["simple-action-stop"]
        )
        assert not any(
            step["id"] == "ingest-ocu-candidate"
            for step in set_manifest["postCaptureWorkflow"]["keyboard-input-stop"]
        )
        assert set_manifest["captureContracts"]["simple-action-stop"][
            "expectedActionEvents"
        ] == ["mouse.click"]
        assert (
            set_manifest["captureContracts"]["simple-action-stop"]["expectedEndReason"]
            == "recording_controls_stopped"
        )
        assert (
            set_manifest["captureContracts"]["simple-action-stop"][
                "requiresMcpTranscriptInput"
            ]
            is True
        )
        assert set_manifest["captureContracts"]["drag-stop"]["expectedActionEvents"] == [
            "mouse.drag"
        ]
        assert (
            set_manifest["capturePackets"]["simple-action-stop"]["requiresMcpTranscriptInput"]
            is True
        )
        assert set_manifest["scripts"]["verifyAll"].endswith("verify-all.sh")
        assert set_manifest["scripts"]["verifyWorkflow"].endswith("verify-workflow.sh")
        assert set_manifest["scripts"]["inspectAll"].endswith("inspect-all.sh")
        assert set_manifest["scripts"]["importAll"].endswith("import-all.sh")
        assert set_manifest["scripts"]["checkAll"].endswith("check-all.sh")
        assert set_manifest["scripts"]["ingestOcuCandidates"].endswith(
            "ingest-ocu-candidates.sh"
        )
        assert set_manifest["scripts"]["strictExpectedFailureAudit"].endswith(
            "strict-expected-failure-audit.sh"
        )
        assert capture_packet_set_json["capturePacketSet"][
            "verifyWorkflowShell"
        ].endswith("verify-workflow.sh")
        assert capture_packet_set_json["capturePacketSet"][
            "ingestOcuCandidatesShell"
        ].endswith("ingest-ocu-candidates.sh")
        assert capture_packet_set_json["capturePacketSet"][
            "strictExpectedFailureAuditShell"
        ].endswith("strict-expected-failure-audit.sh")
        set_readme = (packet_set_dir / "README.md").read_text()
        assert "MCP transcript input required: `yes`" in set_readme
        assert "`capture-packets.json` includes `captureContracts`" in set_readme
        assert "`postCaptureWorkflow`" in set_readme
        assert "./verify-workflow.sh" in set_readme
        assert "`verify-workflow.sh` checks" in set_readme
        assert (
            "Replace `inputs/mcp-transcript.json` with same-session transcript evidence."
            in set_readme
        )
        assert "./ingest-ocu-candidates.sh" in set_readme
        assert "./strict-expected-failure-audit.sh" in set_readme
        assert "skips scenarios without a generated per-scenario OCU candidate wrapper" in (
            set_readme
        )
        verify_all_script = (packet_set_dir / "verify-all.sh").read_text()
        assert "simple-action-stop" in verify_all_script
        assert "verify-inputs.sh" in verify_all_script
        set_workflow_verify = run([str(packet_set_dir / "verify-workflow.sh")], repo)
        assert set_workflow_verify.returncode == 0, set_workflow_verify.stderr
        set_workflow_verify_json = json.loads(set_workflow_verify.stdout)
        assert set_workflow_verify_json["ok"] is True
        assert set_workflow_verify_json["checkedPacketSetWorkflow"] is True
        mutated_manifest = json.loads((packet_set_dir / "capture-packets.json").read_text())
        mutated_manifest["scripts"]["verifyAll"] = "drifted.sh"
        (packet_set_dir / "capture-packets.json").write_text(
            json.dumps(mutated_manifest, indent=2, sort_keys=True) + "\n"
        )
        set_workflow_drift = run([str(packet_set_dir / "verify-workflow.sh")], repo)
        assert set_workflow_drift.returncode == 2
        assert "Packet set scripts manifest drift for verifyAll" in (
            set_workflow_drift.stderr
        )
        (packet_set_dir / "capture-packets.json").write_text(
            json.dumps(set_manifest, indent=2, sort_keys=True) + "\n"
        )
        inspect_all_script = (packet_set_dir / "inspect-all.sh").read_text()
        assert "simple-action-stop" in inspect_all_script
        assert "inspect-only.sh" in inspect_all_script
        assert "check_replaced_input" in inspect_all_script
        import_all_script = (packet_set_dir / "import-all.sh").read_text()
        assert "check_replaced_input" in import_all_script
        check_all_script = (packet_set_dir / "check-all.sh").read_text()
        assert "check_replaced_input" not in check_all_script
        ingest_ocus_script = (packet_set_dir / "ingest-ocu-candidates.sh").read_text()
        assert "ingest-ocu-candidate.sh" in ingest_ocus_script
        assert "skipping; no generated ingest-ocu-candidate.sh" in ingest_ocus_script
        strict_expected_failure_all = (
            packet_set_dir / "strict-expected-failure-audit.sh"
        ).read_text()
        assert "--allow-strict-official-golden-missing" in strict_expected_failure_all
        placeholder_set_verify = run([str(packet_set_dir / "verify-all.sh")], repo)
        assert placeholder_set_verify.returncode == 2
        assert "Packet input still contains placeholder: event_stream_stop response" in (
            placeholder_set_verify.stderr
        )
        placeholder_set_inspect = run([str(packet_set_dir / "inspect-all.sh")], repo)
        assert placeholder_set_inspect.returncode == 2
        assert "Packet input still contains placeholder: event_stream_stop response" in (
            placeholder_set_inspect.stderr
        )
        placeholder_set_import = run([str(packet_set_dir / "import-all.sh")], repo)
        assert placeholder_set_import.returncode == 2
        assert "Packet input still contains placeholder: event_stream_stop response" in (
            placeholder_set_import.stderr
        )
        assert "==> simple-action-stop" not in placeholder_set_import.stdout
        (packet_set_dir / "simple-action-stop/inputs/event_stream_stop-response.json").write_text(
            json.dumps(
                {
                    "metadataPath": "/tmp/official-session/metadata.json",
                    "eventsPath": "/tmp/official-session/events.jsonl",
                }
            )
            + "\n"
        )
        (packet_set_dir / "simple-action-stop/inputs/mcp-transcript.json").write_text(
            json.dumps({"stopResponseShape": {"result": {"content": []}}}) + "\n"
        )
        partial_placeholder_verify = run([str(packet_set_dir / "verify-all.sh")], repo)
        assert partial_placeholder_verify.returncode == 2
        assert "keyboard-input-stop/inputs/event_stream_stop-response.json" in (
            partial_placeholder_verify.stderr
        )
        partial_placeholder_import = run([str(packet_set_dir / "import-all.sh")], repo)
        assert partial_placeholder_import.returncode == 2
        assert "keyboard-input-stop/inputs/event_stream_stop-response.json" in (
            partial_placeholder_import.stderr
        )
        assert "==> simple-action-stop" not in partial_placeholder_import.stdout

        make_packet_dir = tmp_path / "make-capture-packet"
        make_packet = run(
            [
                "make",
                "record-and-replay-official-golden-capture-packet",
                f"RNR_PACKET_DIR={make_packet_dir}",
                "RNR_SCENARIO=drag-stop",
                f"RNR_FIXTURE_ROOT={fixture_root}",
                f"RNR_OFFICIAL_PLUGIN_ROOT={tmp_path / 'missing-plugin-for-make'}",
                "RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1",
            ],
            repo,
        )
        assert make_packet.returncode == 0, make_packet.stderr
        make_packet_json = json.loads(make_packet.stdout)
        assert make_packet_json["scenario"] == "drag-stop"
        assert make_packet_json["officialPlugin"]["allowedMissing"] is True
        assert (make_packet_dir / "README.md").exists()
        assert (make_packet_dir / "scenario-recipe.json").exists()
        assert (make_packet_dir / "capture-contract.json").exists()
        assert (make_packet_dir / "inputs/event_stream_stop-response.json").exists()
        assert (make_packet_dir / "verify-inputs.sh").exists()
        assert (make_packet_dir / "verify-workflow.sh").exists()
        assert (make_packet_dir / "inspect-only.sh").exists()
        assert (make_packet_dir / "ingest-ocu-candidate.sh").exists()
        assert json.loads((make_packet_dir / "scenario-recipe.json").read_text()) == scenario_recipe(
            "drag-stop"
        )

        make_packet_set_dir = tmp_path / "make-capture-packet-set"
        make_packet_set = run(
            [
                "make",
                "record-and-replay-official-golden-capture-packet-set",
                f"RNR_PACKET_DIR={make_packet_set_dir}",
                f"RNR_FIXTURE_ROOT={fixture_root}",
                f"RNR_OFFICIAL_PLUGIN_ROOT={tmp_path / 'missing-plugin-for-make'}",
                "RNR_ALLOW_MISSING_OFFICIAL_PLUGIN=1",
            ],
            repo,
        )
        assert make_packet_set.returncode == 0, make_packet_set.stderr
        make_packet_set_json = json.loads(make_packet_set.stdout)
        assert make_packet_set_json["stage"] == "capture-packet-set"
        assert make_packet_set_json["scenarios"] == capture_packet_set_json["scenarios"]
        assert (make_packet_set_dir / "capture-packets.json").exists()
        assert (make_packet_set_dir / "verify-all.sh").exists()
        assert (make_packet_set_dir / "verify-workflow.sh").exists()
        assert (make_packet_set_dir / "inspect-all.sh").exists()
        assert (make_packet_set_dir / "strict-expected-failure-audit.sh").exists()
        assert (make_packet_set_dir / "drag-stop/ingest-ocu-candidate.sh").exists()
        assert not (make_packet_set_dir / "keyboard-input-stop/ingest-ocu-candidate.sh").exists()

        no_transcript_packet_set_dir = tmp_path / "capture-packet-set-no-transcript"
        no_transcript_packet_set = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--capture-packet-dir",
                str(no_transcript_packet_set_dir),
                "--capture-packet-recommended-scenarios",
                "--no-include-transcript",
            ],
            repo,
        )
        assert no_transcript_packet_set.returncode == 0, no_transcript_packet_set.stderr
        no_transcript_json = json.loads(no_transcript_packet_set.stdout)
        assert no_transcript_json["stage"] == "capture-packet-set"
        assert no_transcript_json["capturePacketSet"]["includeTranscript"] is False
        assert no_transcript_json["capturePacketSet"]["requiresMcpTranscriptInput"] is False
        assert (
            no_transcript_json["capturePacketSet"]["ingestOcuCandidatesShell"].endswith(
                "ingest-ocu-candidates.sh"
            )
        )
        assert no_transcript_json["capturePacketSet"][
            "strictExpectedFailureAuditShell"
        ].endswith("strict-expected-failure-audit.sh")
        no_transcript_manifest = json.loads(
            (no_transcript_packet_set_dir / "capture-packets.json").read_text()
        )
        assert no_transcript_manifest["includeTranscript"] is False
        assert no_transcript_manifest["requiresMcpTranscriptInput"] is False
        assert (
            no_transcript_manifest["captureContracts"]["simple-action-stop"][
                "requiresMcpTranscriptInput"
            ]
            is False
        )
        assert (
            no_transcript_manifest["captureContracts"]["drag-stop"]["expectedActionEvents"]
            == ["mouse.drag"]
        )
        assert no_transcript_manifest["scripts"]["ingestOcuCandidates"].endswith(
            "ingest-ocu-candidates.sh"
        )
        assert no_transcript_manifest["scripts"]["verifyWorkflow"].endswith(
            "verify-workflow.sh"
        )
        assert no_transcript_manifest["scripts"]["strictExpectedFailureAudit"].endswith(
            "strict-expected-failure-audit.sh"
        )
        assert (no_transcript_packet_set_dir / "ingest-ocu-candidates.sh").exists()
        assert (no_transcript_packet_set_dir / "verify-workflow.sh").exists()
        assert (
            no_transcript_packet_set_dir / "strict-expected-failure-audit.sh"
        ).exists()
        no_transcript_set_workflow_verify = run(
            [str(no_transcript_packet_set_dir / "verify-workflow.sh")],
            repo,
        )
        assert no_transcript_set_workflow_verify.returncode == 0, (
            no_transcript_set_workflow_verify.stderr
        )
        for scenario in no_transcript_json["scenarios"]:
            scenario_dir = no_transcript_packet_set_dir / scenario
            assert (scenario_dir / "inputs/event_stream_stop-response.json").exists()
            assert not (scenario_dir / "inputs/mcp-transcript.json").exists()
            assert (scenario_dir / "capture-contract.json").exists()
            assert "--mcp-transcript" not in (scenario_dir / "inspect-only.sh").read_text()
            assert "--mcp-transcript" not in (scenario_dir / "import-fixture.sh").read_text()
            assert (
                no_transcript_manifest["capturePackets"][scenario]["includeTranscript"] is False
            )
            assert (
                no_transcript_manifest["capturePackets"][scenario][
                    "requiresMcpTranscriptInput"
                ]
                is False
            )
            assert no_transcript_manifest["capturePackets"][scenario]["mcpTranscriptInputPath"] is None
            no_transcript_readme = (scenario_dir / "README.md").read_text()
            assert "MCP transcript input required: `no`" in no_transcript_readme
            assert "does not create `inputs/mcp-transcript.json`" in no_transcript_readme
        no_transcript_inspect_all = (no_transcript_packet_set_dir / "inspect-all.sh").read_text()
        no_transcript_import_all = (no_transcript_packet_set_dir / "import-all.sh").read_text()
        assert "mcp-transcript.json" not in no_transcript_inspect_all
        assert "mcp-transcript.json" not in no_transcript_import_all
        no_transcript_set_readme = (no_transcript_packet_set_dir / "README.md").read_text()
        assert "MCP transcript input required: `no`" in no_transcript_set_readme
        assert "does not create or require `inputs/mcp-transcript.json`" in no_transcript_set_readme
        assert "./ingest-ocu-candidates.sh" in no_transcript_set_readme
        for scenario in no_transcript_json["scenarios"]:
            (
                no_transcript_packet_set_dir
                / scenario
                / "inputs/event_stream_stop-response.json"
            ).write_text(
                json.dumps(
                    {
                        "metadataPath": "/tmp/official-session/metadata.json",
                        "eventsPath": "/tmp/official-session/events.jsonl",
                    }
                )
                + "\n"
            )
        no_transcript_verify_all = run(
            [str(no_transcript_packet_set_dir / "verify-all.sh")],
            repo,
        )
        assert no_transcript_verify_all.returncode == 0, no_transcript_verify_all.stderr

        require_ready = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(plugin_root),
                "--require-ready",
            ],
            repo,
        )
        assert require_ready.returncode == 1
        require_ready_json = json.loads(require_ready.stderr)
        assert require_ready_json["requireReady"] is True
        assert require_ready_json["scenarioStatus"]["ready"] is False

        missing_plugin = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(tmp_path / "missing-plugin"),
            ],
            repo,
        )
        assert missing_plugin.returncode == 1
        missing_plugin_json = json.loads(missing_plugin.stderr)
        assert missing_plugin_json["officialPlugin"]["available"] is False

        allowed_missing_plugin = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(fixture_root),
                "--official-plugin-root",
                str(tmp_path / "missing-plugin"),
                "--allow-missing-official-plugin",
                "--scenario",
                "keyboard-input-stop",
                "--no-include-transcript",
            ],
            repo,
        )
        assert allowed_missing_plugin.returncode == 0, allowed_missing_plugin.stderr
        allowed_json = json.loads(allowed_missing_plugin.stdout)
        assert allowed_json["officialPlugin"]["allowedMissing"] is True
        assert allowed_json["scenarioRecipe"]["scenario"] == "keyboard-input-stop"
        assert allowed_json["scenarioRecipe"]["expectedActionEvents"] == ["keyboard.text_input"]
        assert allowed_json["scenarioRecipe"]["ocuCandidateSourceKind"] == "recording-required"
        assert allowed_json["commands"]["ocuCandidate"] is None
        assert "synthetic --run-action-smoke" in allowed_json["commands"]["ocuCandidateNote"]
        assert "--mcp-transcript" not in allowed_json["commands"]["inspectOnly"]

        recipe_drift_root = tmp_path / "recipe-drift-fixtures"
        recipe_drift_fixture = recipe_drift_root / "official-action"
        recipe_drift_fixture.mkdir(parents=True)
        recipe = scenario_recipe("simple-action-stop")
        recipe["expectedActionEvents"] = ["keyboard.text_input"]
        (recipe_drift_fixture / "fixture-manifest.json").write_text(
            json.dumps(
                {
                    "fixtureFormatVersion": 1,
                    "name": "official-action",
                    "source": "official",
                    "scenario": "simple-action-stop",
                    "scenarioRecipe": recipe,
                    "officialPluginVersion": "record-and-replay 1.0.857",
                    "eventCount": 4,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )
        coverage_error = run(
            [
                sys.executable,
                str(script),
                "--fixture-root",
                str(recipe_drift_root),
                "--official-plugin-root",
                str(plugin_root),
            ],
            repo,
        )
        assert coverage_error.returncode == 1
        coverage_error_json = json.loads(coverage_error.stderr)
        assert coverage_error_json["coverageErrors"]
        assert any(
            "scenarioRecipe does not match scenario" in error
            for error in coverage_error_json["coverageErrors"]
        )
        assert any("Fix official fixture coverage errors" in action for action in coverage_error_json["nextActions"])

    print(
        json.dumps(
            {
                "ok": True,
                "checkedMissingScenarioPreflight": True,
                "checkedCapturePacket": True,
                "checkedCapturePacketPostCaptureWorkflow": True,
                "checkedCapturePacketWorkflowVerifier": True,
                "checkedCapturePacketHandoffScripts": True,
                "checkedCapturePacketStrictAuditHandoff": True,
                "checkedCapturePacketStrictExpectedFailureAuditHandoff": True,
                "checkedCapturePacketOcuCandidateOutputDir": True,
                "checkedCapturePacketNoTranscript": True,
                "checkedCapturePacketSet": True,
                "checkedCapturePacketSetPostCaptureWorkflow": True,
                "checkedCapturePacketSetWorkflowVerifier": True,
                "checkedCapturePacketSetNoTranscript": True,
                "checkedCapturePacketSetOcuCandidateHandoff": True,
                "checkedCapturePacketSetContractManifest": True,
                "checkedCapturePacketTranscriptManifest": True,
                "checkedCapturePacketInputSemanticGuard": True,
                "checkedCapturePacketVerifyInputs": True,
                "checkedCapturePacketSetVerifyAll": True,
                "checkedCapturePacketPlaceholderGuard": True,
                "checkedCapturePacketImportPlaceholderGuard": True,
                "checkedCapturePacketTranscriptPlaceholderGuard": True,
                "checkedCapturePacketSetRootPlaceholderGuard": True,
                "checkedCapturePacketSetRootPreflightPlaceholderGuard": True,
                "checkedMakeCapturePacketTargets": True,
                "checkedRequireReadyFailure": True,
                "checkedMissingPluginFailure": True,
                "checkedAllowedMissingPluginKeyboardScenario": True,
                "checkedCoverageErrorFailure": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
