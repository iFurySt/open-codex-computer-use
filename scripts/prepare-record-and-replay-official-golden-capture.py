#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import textwrap
from typing import Any

from record_and_replay_scenarios import (
    DEFAULT_RECOMMENDED_SCENARIOS,
    DEFAULT_REQUIRED_SCENARIOS,
    scenario_recipe,
)


DEFAULT_FIXTURE_ROOT = pathlib.Path(
    "docs/references/codex-computer-use-reverse-engineering/fixtures/recordings"
)
DEFAULT_OFFICIAL_PLUGIN_ROOT = pathlib.Path(
    "~/.codex/plugins/cache/openai-bundled/record-and-replay"
).expanduser()
DEFAULT_OFFICIAL_PLUGIN_VERSION = "record-and-replay 1.0.857"
DEFAULT_SCENARIO = DEFAULT_REQUIRED_SCENARIOS[0]
DEFAULT_REQUIRED_SCENARIO_HELP = ", ".join(DEFAULT_REQUIRED_SCENARIOS)


def display_path(path: pathlib.Path, repo: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(repo.resolve()))
    except (FileNotFoundError, ValueError):
        try:
            return "~/" + str(path.expanduser().resolve().relative_to(pathlib.Path.home()))
        except (FileNotFoundError, ValueError):
            return str(path)


def run_json(command: list[str], cwd: pathlib.Path) -> tuple[bool, dict[str, Any]]:
    completed = subprocess.run(
        command,
        cwd=cwd,
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
            "errors": [
                f"command exited {completed.returncode} and did not emit JSON",
                completed.stderr.strip() or completed.stdout.strip(),
            ],
        }
    return completed.returncode == 0, parsed


def shell_join(argv: list[str]) -> str:
    import shlex

    return " ".join(shlex.quote(part) for part in argv)


def discover_official_plugin_versions(plugin_root: pathlib.Path, repo: pathlib.Path) -> list[dict[str, Any]]:
    if not plugin_root.exists():
        return []
    versions: list[dict[str, Any]] = []
    for path in sorted(plugin_root.iterdir()):
        if not path.is_dir():
            continue
        skill_path = path / "skills/record-and-replay/SKILL.md"
        versions.append(
            {
                "version": path.name,
                "path": display_path(path, repo),
                "hasSkill": skill_path.exists(),
            }
        )
    return versions


def default_fixture_name(scenario: str, official_plugin_version: str) -> str:
    version = official_plugin_version.replace("record-and-replay", "").strip() or "unknown"
    safe_version = version.replace(" ", "-")
    return f"official-{scenario}-{safe_version}"


def scenario_candidate_command(
    repo: pathlib.Path,
    scenario: str,
    name: str,
    fixture_root: pathlib.Path,
) -> list[str] | None:
    if scenario not in {"simple-action-stop", "drag-stop"}:
        return None
    candidate_root = fixture_root / "ocu-candidates"
    return [
        "python3",
        "scripts/ingest-ocu-record-and-replay-candidate.py",
        "--run-action-smoke",
        "--scenario",
        scenario,
        "--name",
        f"ocu-{scenario}",
        "--output-dir",
        display_path(candidate_root, repo),
        "--official-root",
        display_path(fixture_root, repo),
        "--require-mcp-transcript-evidence",
    ]


def build_commands(
    repo: pathlib.Path,
    args: argparse.Namespace,
    fixture_name: str,
) -> dict[str, Any]:
    fixture_root = args.fixture_root
    status_json = args.status_json_placeholder
    transcript = args.mcp_transcript_placeholder
    base = [
        "python3",
        "scripts/ingest-official-record-and-replay-fixture.py",
        "--status-json",
        status_json,
        "--name",
        fixture_name,
        "--scenario",
        args.scenario,
        "--output-dir",
        display_path(fixture_root, repo),
        "--official-plugin-version",
        args.official_plugin_version,
    ]
    if args.status_json_base_dir_placeholder:
        base.extend(["--status-json-base-dir", args.status_json_base_dir_placeholder])

    inspect = [*base, "--inspect-only"]
    if args.include_transcript:
        inspect.extend(["--mcp-transcript", transcript, "--require-mcp-transcript-evidence"])

    import_cmd = [
        *base,
        "--check-fixture-set",
        "--check-coverage",
    ]
    if args.include_transcript:
        import_cmd.extend(["--mcp-transcript", transcript, "--require-mcp-transcript-evidence"])
    if args.require_coverage_on_import:
        import_cmd.append("--require-coverage")

    candidate = scenario_candidate_command(repo, args.scenario, fixture_name, fixture_root)
    commands: dict[str, Any] = {
        "inspectOnly": inspect,
        "inspectOnlyShell": shell_join(inspect),
        "importFixture": import_cmd,
        "importFixtureShell": shell_join(import_cmd),
        "coverageReadiness": [
            "python3",
            "scripts/check-event-stream-official-fixture-coverage.py",
            "--fixture-root",
            display_path(fixture_root, repo),
            "--require-readiness",
        ],
        "fixtureSet": [
            "python3",
            "scripts/check-event-stream-official-fixture-set.py",
            "--official-root",
            display_path(fixture_root, repo),
            "--require-scenario",
            args.scenario,
        ],
        "strictOfficialGoldenGate": ["make", "record-and-replay-official-golden-gate-audit"],
        "strictOfficialGoldenExpectedFailureAudit": [
            "python3",
            "scripts/check-record-and-replay-baseline-summary.py",
            "dist/record-and-replay-official-golden-gate-summary.json",
            "--allow-strict-official-golden-missing",
        ],
    }
    commands["coverageReadinessShell"] = shell_join(commands["coverageReadiness"])
    commands["fixtureSetShell"] = shell_join(commands["fixtureSet"])
    commands["strictOfficialGoldenGateShell"] = shell_join(commands["strictOfficialGoldenGate"])
    commands["strictOfficialGoldenExpectedFailureAuditShell"] = shell_join(
        commands["strictOfficialGoldenExpectedFailureAudit"]
    )
    if candidate is not None:
        commands["ocuCandidate"] = candidate
        commands["ocuCandidateShell"] = shell_join(candidate)
    else:
        commands["ocuCandidate"] = None
        commands["ocuCandidateNote"] = (
            "Import this scenario from an existing OCU recording or preserved smoke JSON; "
            "synthetic --run-action-smoke is only supported for simple-action-stop and drag-stop."
        )
    return commands


def write_text(path: pathlib.Path, text: str, *, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    if executable:
        path.chmod(0o755)


def bash_array(
    command: list[str] | None,
    args: argparse.Namespace,
    *,
    status_json_path: str = '"${packet_dir}/inputs/event_stream_stop-response.json"',
    transcript_path: str = '"${packet_dir}/inputs/mcp-transcript.json"',
) -> str:
    if command is None:
        return ""

    import shlex

    parts: list[str] = []
    for item in command:
        if item == args.status_json_placeholder:
            parts.append(status_json_path)
        elif item == args.mcp_transcript_placeholder:
            parts.append(transcript_path)
        else:
            parts.append(shlex.quote(item))
    return "\n  ".join(parts)


def render_packet_script(command: list[str] | None, args: argparse.Namespace, repo: pathlib.Path) -> str:
    if command is None:
        return "#!/usr/bin/env bash\nset -euo pipefail\necho 'No command is available for this scenario.' >&2\nexit 1\n"
    import shlex

    repo_root = shlex.quote(str(repo))
    needs_status_json = args.status_json_placeholder in command
    needs_transcript = args.mcp_transcript_placeholder in command
    guard_lines: list[str] = []
    if needs_status_json or needs_transcript:
        guard_lines.append(
            textwrap.dedent(
                """\
                check_replaced_input() {
                  local path="$1"
                  local label="$2"
                  if [[ ! -f "${path}" ]]; then
                    echo "Missing packet input: ${label} (${path})" >&2
                    exit 2
                  fi
                  if python3 - "${path}" <<'PY'
                import json
                import sys

                try:
                    with open(sys.argv[1], "r", encoding="utf-8") as handle:
                        value = json.load(handle)
                except Exception:
                    sys.exit(1)
                sys.exit(0 if isinstance(value, dict) and value.get("_placeholder") is True else 1)
                PY
                  then
                    echo "Packet input still contains placeholder: ${label} (${path}). Replace it with hosted official JSON before running ${BASH_SOURCE[0]##*/}." >&2
                    exit 2
                  fi
                }
                """
            )
        )
    if needs_status_json:
        guard_lines.append(
            'check_replaced_input "${packet_dir}/inputs/event_stream_stop-response.json" "event_stream_stop response"\n'
        )
    if needs_transcript:
        guard_lines.append(
            'check_replaced_input "${packet_dir}/inputs/mcp-transcript.json" "MCP transcript"\n'
        )
    guard = "\n".join(guard_lines)
    if guard:
        guard += "\n"
    semantic_verify = ""
    if needs_status_json:
        semantic_verify = '"${packet_dir}/verify-inputs.sh" >/dev/null\n\n'
    return (
        "#!/usr/bin/env bash\n\n"
        "set -euo pipefail\n\n"
        'packet_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        f"default_repo_root={repo_root}\n"
        'repo_root="${REPO_ROOT:-${default_repo_root}}"\n\n'
        f"{guard}"
        f"{semantic_verify}"
        "cd \"${repo_root}\"\n"
        "cmd=(\n"
        f"  {bash_array(command, args)}\n"
        ")\n"
        '"${cmd[@]}"\n'
    )


def render_repo_script(command: list[str], repo: pathlib.Path) -> str:
    import shlex

    repo_root = shlex.quote(str(repo))
    return (
        "#!/usr/bin/env bash\n\n"
        "set -euo pipefail\n\n"
        f"default_repo_root={repo_root}\n"
        'repo_root="${REPO_ROOT:-${default_repo_root}}"\n\n'
        "cd \"${repo_root}\"\n"
        "cmd=(\n"
        f"  {shell_join(command)}\n"
        ")\n"
        '"${cmd[@]}"\n'
    )


def render_packet_inputs_script(args: argparse.Namespace) -> str:
    transcript_check = ""
    if args.include_transcript:
        transcript_check = (
            'check_json_input "${packet_dir}/inputs/mcp-transcript.json" "MCP transcript"\n'
        )
    return (
        "#!/usr/bin/env bash\n\n"
        "set -euo pipefail\n\n"
        'packet_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n\n'
        "check_json_input() {\n"
        '  local path="$1"\n'
        '  local label="$2"\n'
        '  if [[ ! -f "${path}" ]]; then\n'
        '    echo "Missing packet input: ${label} (${path})" >&2\n'
        "    exit 2\n"
        "  fi\n"
        '  python3 - "${path}" "${label}" <<\'PY\'\n'
        "import json\n"
        "import sys\n\n"
        "path, label = sys.argv[1:3]\n"
        "try:\n"
        "    with open(path, \"r\", encoding=\"utf-8\") as handle:\n"
        "        value = json.load(handle)\n"
        "except Exception as error:\n"
        "    print(f\"Invalid packet JSON: {label} ({path}): {error}\", file=sys.stderr)\n"
        "    sys.exit(2)\n"
        "if isinstance(value, dict) and value.get(\"_placeholder\") is True:\n"
        "    print(\n"
        "        f\"Packet input still contains placeholder: {label} ({path}). \"\n"
        "        \"Replace it with hosted official JSON before running packet import.\",\n"
        "        file=sys.stderr,\n"
        "    )\n"
        "    sys.exit(2)\n"
        "PY\n"
        "}\n\n"
        'check_json_input "${packet_dir}/inputs/event_stream_stop-response.json" "event_stream_stop response"\n'
        f"{transcript_check}"
        'python3 - "${packet_dir}" <<\'PY\'\n'
        "import json\n"
        "import sys\n\n"
        "from pathlib import Path\n\n"
        "packet_dir = Path(sys.argv[1])\n"
        "path_keys = (\"metadataPath\", \"sessionPath\", \"eventsPath\", \"suppressedEventsPath\", \"sessionDirectoryPath\")\n"
        "transcript_keys = {\n"
        "    \"startResponseShape\",\n"
        "    \"repeatStartResponseShape\",\n"
        "    \"statusResponseShape\",\n"
        "    \"stopResponseShape\",\n"
        "    \"repeatStopResponseShape\",\n"
        "    \"finalStatusResponseShape\",\n"
        "    \"transcript\",\n"
        "}\n\n"
        "def load_packet_json(relative_path):\n"
        "    path = packet_dir / relative_path\n"
        "    try:\n"
        "        with path.open(\"r\", encoding=\"utf-8\") as handle:\n"
        "            return json.load(handle)\n"
        "    except Exception as error:\n"
        "        print(f\"Invalid packet JSON: {relative_path}: {error}\", file=sys.stderr)\n"
        "        sys.exit(2)\n\n"
        "def decode_json_string(value):\n"
        "    if not isinstance(value, str):\n"
        "        return None\n"
        "    try:\n"
        "        return json.loads(value)\n"
        "    except json.JSONDecodeError:\n"
        "        return None\n\n"
        "def iter_objects(value):\n"
        "    if isinstance(value, dict):\n"
        "        yield value\n"
        "        for child in value.values():\n"
        "            decoded = decode_json_string(child)\n"
        "            if decoded is not None:\n"
        "                yield from iter_objects(decoded)\n"
        "            else:\n"
        "                yield from iter_objects(child)\n"
        "    elif isinstance(value, list):\n"
        "        for child in value:\n"
        "            yield from iter_objects(child)\n\n"
        "contract = load_packet_json(\"capture-contract.json\")\n"
        "recipe = load_packet_json(\"scenario-recipe.json\")\n"
        "if contract.get(\"scenario\") != recipe.get(\"scenario\"):\n"
        "    print(\"Packet contract scenario does not match scenario recipe\", file=sys.stderr)\n"
        "    sys.exit(2)\n"
        "status_json = load_packet_json(\"inputs/event_stream_stop-response.json\")\n"
        "found_handoff_keys = sorted({\n"
        "    key\n"
        "    for obj in iter_objects(status_json)\n"
        "    for key in path_keys\n"
        "    if isinstance(obj.get(key), str) and obj.get(key)\n"
        "})\n"
        "if not found_handoff_keys:\n"
        "    print(\n"
        "        \"Packet status JSON does not contain Record & Replay handoff path evidence: \"\n"
        "        + \", \".join(path_keys),\n"
        "        file=sys.stderr,\n"
        "    )\n"
        "    sys.exit(2)\n"
        "required_handoff_keys = tuple(contract.get(\"requiredStatusHandoffPathKeys\") or ())\n"
        "missing_required_handoff_keys = [\n"
        "    key for key in required_handoff_keys if key not in found_handoff_keys\n"
        "]\n"
        "required_any_of_groups = contract.get(\"requiredStatusHandoffAnyOf\") or []\n"
        "missing_any_of_groups = [\n"
        "    group\n"
        "    for group in required_any_of_groups\n"
        "    if isinstance(group, list) and not any(key in found_handoff_keys for key in group)\n"
        "]\n"
        "if missing_required_handoff_keys or missing_any_of_groups:\n"
        "    print(\n"
        "        \"Packet status JSON is missing required Record & Replay handoff evidence: \"\n"
        "        + json.dumps({\n"
        "            \"missingRequiredStatusHandoffPathKeys\": missing_required_handoff_keys,\n"
        "            \"missingRequiredStatusHandoffAnyOf\": missing_any_of_groups,\n"
        "            \"foundHandoffPathKeys\": found_handoff_keys,\n"
        "        }, sort_keys=True),\n"
        "        file=sys.stderr,\n"
        "    )\n"
        "    sys.exit(2)\n"
        "found_transcript_keys = []\n"
        "requires_transcript = bool(contract.get(\"requiresMcpTranscriptInput\"))\n"
        "if requires_transcript:\n"
        "    transcript_json = load_packet_json(\"inputs/mcp-transcript.json\")\n"
        "    found_transcript_keys = sorted({\n"
        "        key\n"
        "        for obj in iter_objects(transcript_json)\n"
        "        for key in transcript_keys\n"
        "        if key in obj\n"
        "    })\n"
        "    if not found_transcript_keys:\n"
        "        print(\n"
        "            \"Packet MCP transcript does not contain MCP transcript evidence: \"\n"
        "            + \", \".join(sorted(transcript_keys)),\n"
        "            file=sys.stderr,\n"
        "        )\n"
        "        sys.exit(2)\n"
        "print(json.dumps({\n"
        "    \"ok\": True,\n"
        "    \"stage\": \"verify-inputs\",\n"
        "    \"packetDir\": str(packet_dir),\n"
        "    \"scenario\": contract.get(\"scenario\"),\n"
        "    \"foundHandoffPathKeys\": found_handoff_keys,\n"
        "    \"requiredStatusHandoffPathKeys\": list(required_handoff_keys),\n"
        "    \"requiredStatusHandoffAnyOf\": required_any_of_groups,\n"
        "    \"requiresMcpTranscriptInput\": requires_transcript,\n"
        "    \"foundTranscriptEvidenceKeys\": found_transcript_keys,\n"
        "}, sort_keys=True))\n"
        "PY\n"
    )


def render_packet_set_script(scenarios: list[str], child_script: str, *, include_transcript: bool) -> str:
    import shlex

    scenario_lines = "\n".join(f"  {shlex.quote(scenario)}" for scenario in scenarios)
    preflight = ""
    if child_script in {"inspect-only.sh", "import-fixture.sh"}:
        preflight = textwrap.dedent(
            """\
            check_replaced_input() {
              local path="$1"
              local label="$2"
              if [[ ! -f "${path}" ]]; then
                echo "Missing packet input: ${label} (${path})" >&2
                exit 2
              fi
              if python3 - "${path}" <<'PY'
            import json
            import sys

            try:
                with open(sys.argv[1], "r", encoding="utf-8") as handle:
                    value = json.load(handle)
            except Exception:
                sys.exit(1)
            sys.exit(0 if isinstance(value, dict) and value.get("_placeholder") is True else 1)
            PY
              then
                echo "Packet input still contains placeholder: ${label} (${path}). Replace it with hosted official JSON before running ${BASH_SOURCE[0]##*/}." >&2
                exit 2
              fi
            }

            for scenario in "${scenarios[@]}"; do
              check_replaced_input "${packet_set_dir}/${scenario}/inputs/event_stream_stop-response.json" "event_stream_stop response"
            """
        )
        if include_transcript:
            preflight += textwrap.dedent(
                """\
              check_replaced_input "${packet_set_dir}/${scenario}/inputs/mcp-transcript.json" "MCP transcript"
                """
            )
        preflight += textwrap.dedent(
            """\
            done

            """
        )
    return (
        "#!/usr/bin/env bash\n\n"
        "set -euo pipefail\n\n"
        'packet_set_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        "scenarios=(\n"
        f"{scenario_lines}\n"
        ")\n\n"
        f"{preflight}"
        'for scenario in "${scenarios[@]}"; do\n'
        f'  script="${{packet_set_dir}}/${{scenario}}/{child_script}"\n'
        '  if [[ ! -x "${script}" ]]; then\n'
        f'    echo "Missing executable packet script: ${{scenario}}/{child_script}" >&2\n'
        "    exit 1\n"
        "  fi\n"
        '  echo "==> ${scenario}"\n'
        '  "${script}"\n'
        "done\n"
    )


def render_packet_set_optional_script(scenarios: list[str], child_script: str) -> str:
    import shlex

    scenario_lines = "\n".join(f"  {shlex.quote(scenario)}" for scenario in scenarios)
    return (
        "#!/usr/bin/env bash\n\n"
        "set -euo pipefail\n\n"
        'packet_set_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        "scenarios=(\n"
        f"{scenario_lines}\n"
        ")\n\n"
        'ran=0\n'
        'for scenario in "${scenarios[@]}"; do\n'
        f'  script="${{packet_set_dir}}/${{scenario}}/{child_script}"\n'
        '  if [[ ! -x "${script}" ]]; then\n'
        f'    echo "==> ${{scenario}}: skipping; no generated {child_script}"\n'
        "    continue\n"
        "  fi\n"
        '  echo "==> ${scenario}"\n'
        '  "${script}"\n'
        "  ran=$((ran + 1))\n"
        "done\n\n"
        'if [[ "${ran}" -eq 0 ]]; then\n'
        f'  echo "No generated {child_script} scripts were available." >&2\n'
        "fi\n"
    )


def render_workflow_verifier_script(*, packet_set: bool) -> str:
    mode = "packet-set" if packet_set else "packet"
    return textwrap.dedent(
        f"""\
        #!/usr/bin/env bash

        set -euo pipefail

        packet_dir="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"

        python3 - "${{packet_dir}}" "{mode}" <<'PY'
        import json
        import pathlib
        import sys

        packet_dir = pathlib.Path(sys.argv[1])
        mode = sys.argv[2]

        def fail(message):
            print(message, file=sys.stderr)
            sys.exit(2)

        def load_json(path):
            try:
                return json.loads(path.read_text())
            except Exception as exc:
                fail(f"Invalid workflow JSON {{path}}: {{exc}}")

        def require_file(path, label):
            if not path.is_file():
                fail(f"Workflow {{label}} is missing: {{path}}")

        def require_executable(path, label):
            require_file(path, label)
            if not path.stat().st_mode & 0o111:
                fail(f"Workflow command is not executable: {{path}}")

        def verify_workflow(root, contract, *, scenario):
            workflow = contract.get("postCaptureWorkflow")
            if not isinstance(workflow, list) or not workflow:
                fail(f"Workflow missing for {{scenario}}")
            requires_transcript = bool(contract.get("requiresMcpTranscriptInput"))
            ids = [step.get("id") for step in workflow if isinstance(step, dict)]
            if "replace-status-json" not in ids:
                fail(f"Workflow missing replace-status-json for {{scenario}}")
            if requires_transcript and "replace-mcp-transcript" not in ids:
                fail(f"Workflow missing replace-mcp-transcript for {{scenario}}")
            if not requires_transcript and "replace-mcp-transcript" in ids:
                fail(f"Workflow unexpectedly requires MCP transcript for {{scenario}}")
            required_commands = {{
                "verify-inputs": "verify-inputs.sh",
                "inspect-only": "inspect-only.sh",
                "import-fixture": "import-fixture.sh",
                "check-coverage": "check-coverage.sh",
                "check-fixture-set": "check-fixture-set.sh",
                "strict-golden-gate": "strict-golden-gate.sh",
                "strict-expected-failure-audit": "strict-expected-failure-audit.sh",
            }}
            optional_commands = {{"ingest-ocu-candidate": "ingest-ocu-candidate.sh"}}
            for step in workflow:
                if not isinstance(step, dict):
                    fail(f"Workflow step is not an object for {{scenario}}")
                step_id = step.get("id")
                input_path = step.get("input")
                command = step.get("command")
                if input_path is not None:
                    require_file(root / input_path, f"input {{step_id}}")
                if command is not None:
                    if not isinstance(command, str) or not command.startswith("./"):
                        fail(f"Workflow command must be a local ./ script for {{scenario}}: {{command!r}}")
                    require_executable(root / command[2:], f"command {{step_id}}")
                expected = required_commands.get(step_id)
                if expected is not None and command != f"./{{expected}}":
                    fail(f"Workflow command drift for {{scenario}} {{step_id}}: {{command!r}}")
                optional = optional_commands.get(step_id)
                if optional is not None and command != f"./{{optional}}":
                    fail(f"Workflow optional command drift for {{scenario}} {{step_id}}: {{command!r}}")
            for step_id, script_name in required_commands.items():
                if step_id not in ids:
                    fail(f"Workflow missing required step {{step_id}} for {{scenario}}")
                require_executable(root / script_name, f"script {{step_id}}")
            if "ingest-ocu-candidate" in ids:
                require_executable(root / "ingest-ocu-candidate.sh", f"script ingest-ocu-candidate for {{scenario}}")
            else:
                if (root / "ingest-ocu-candidate.sh").exists():
                    fail(f"Workflow omits ingest-ocu-candidate but script exists for {{scenario}}")
            require_file(root / "inputs/event_stream_stop-response.json", f"status input for {{scenario}}")
            if requires_transcript:
                require_file(root / "inputs/mcp-transcript.json", f"MCP transcript input for {{scenario}}")
            elif (root / "inputs/mcp-transcript.json").exists():
                fail(f"Workflow says MCP transcript is disabled but input exists for {{scenario}}")

        if mode == "packet":
            contract = load_json(packet_dir / "capture-contract.json")
            verify_workflow(packet_dir, contract, scenario=contract.get("scenario", "<unknown>"))
            print(json.dumps({{
                "ok": True,
                "stage": "verify-workflow",
                "checkedWorkflow": True,
                "checkedWorkflowCommands": True,
                "checkedWorkflowInputs": True,
                "scenario": contract.get("scenario"),
            }}, sort_keys=True))
        elif mode == "packet-set":
            manifest = load_json(packet_dir / "capture-packets.json")
            contracts = manifest.get("captureContracts")
            workflows = manifest.get("postCaptureWorkflow")
            if not isinstance(contracts, dict) or not contracts:
                fail("Packet set workflow manifest is missing captureContracts")
            if not isinstance(workflows, dict) or not workflows:
                fail("Packet set workflow manifest is missing postCaptureWorkflow")
            scenarios = manifest.get("scenarios")
            if not isinstance(scenarios, list) or not scenarios:
                fail("Packet set workflow manifest is missing scenarios")
            for scenario in scenarios:
                contract = contracts.get(scenario)
                if not isinstance(contract, dict):
                    fail(f"Packet set missing capture contract for {{scenario}}")
                if workflows.get(scenario) != contract.get("postCaptureWorkflow"):
                    fail(f"Packet set workflow does not match capture contract for {{scenario}}")
                verify_workflow(packet_dir / scenario, contract, scenario=scenario)
            scripts = manifest.get("scripts")
            required_root_scripts = {{
                "verifyAll": "verify-all.sh",
                "inspectAll": "inspect-all.sh",
                "importAll": "import-all.sh",
                "checkAll": "check-all.sh",
                "ingestOcuCandidates": "ingest-ocu-candidates.sh",
                "strictExpectedFailureAudit": "strict-expected-failure-audit.sh",
                "verifyWorkflow": "verify-workflow.sh",
            }}
            if not isinstance(scripts, dict):
                fail("Packet set workflow manifest is missing scripts")
            for key, script_name in required_root_scripts.items():
                if not str(scripts.get(key, "")).endswith(script_name):
                    fail(f"Packet set scripts manifest drift for {{key}}")
                require_executable(packet_dir / script_name, f"root script {{key}}")
            print(json.dumps({{
                "ok": True,
                "stage": "verify-workflow",
                "checkedWorkflow": True,
                "checkedWorkflowCommands": True,
                "checkedWorkflowInputs": True,
                "checkedPacketSetWorkflow": True,
                "scenarios": scenarios,
            }}, sort_keys=True))
        else:
            fail(f"unknown workflow verifier mode: {{mode}}")
        PY
        """
    )


def placeholder_json(label: str) -> str:
    return json.dumps(
        {
            "_placeholder": True,
            "replaceWith": label,
            "note": "Replace this file with the JSON captured from the official Codex Record & Replay workflow before running the packet scripts.",
        },
        indent=2,
        sort_keys=True,
    ) + "\n"


def capture_contract(result: dict[str, Any], *, include_transcript: bool) -> dict[str, Any]:
    recipe = result["scenarioRecipe"]
    workflow = post_capture_workflow(result, include_transcript=include_transcript)
    return {
        "formatVersion": 1,
        "scenario": result["scenario"],
        "fixtureName": result["fixtureName"],
        "captureGoal": recipe["captureGoal"],
        "userAction": recipe["userAction"],
        "expectedActionEvents": recipe.get("expectedActionEvents", []),
        "expectedEndReason": recipe.get("expectedEndReason"),
        "requiresMcpTranscriptInput": include_transcript,
        "statusHandoffPathKeys": [
            "metadataPath",
            "sessionPath",
            "eventsPath",
            "suppressedEventsPath",
            "sessionDirectoryPath",
        ],
        "requiredStatusHandoffPathKeys": [
            "eventsPath",
        ],
        "requiredStatusHandoffAnyOf": [
            [
                "metadataPath",
                "sessionPath",
            ],
        ],
        "optionalStatusHandoffPathKeys": [
            "suppressedEventsPath",
            "sessionDirectoryPath",
        ],
        "requiredTranscriptEvidenceKeys": [
            "startResponseShape",
            "statusResponseShape",
            "stopResponseShape",
            "finalStatusResponseShape",
            "transcript",
        ]
        if include_transcript
        else [],
        "postCaptureWorkflow": workflow,
        "postCaptureChecks": [
            "./verify-inputs.sh",
            "./verify-workflow.sh",
            "./inspect-only.sh",
            "./import-fixture.sh",
            "./check-fixture-set.sh",
            "./strict-golden-gate.sh",
            "./strict-expected-failure-audit.sh",
        ],
    }


def post_capture_workflow(
    result: dict[str, Any],
    *,
    include_transcript: bool,
) -> list[dict[str, Any]]:
    workflow: list[dict[str, Any]] = [
        {
            "id": "replace-status-json",
            "description": "Replace hosted status/stop JSON placeholder with official Record & Replay handoff JSON.",
            "input": "inputs/event_stream_stop-response.json",
            "required": True,
        }
    ]
    if include_transcript:
        workflow.append(
            {
                "id": "replace-mcp-transcript",
                "description": "Replace MCP transcript placeholder with same-session official transcript evidence.",
                "input": "inputs/mcp-transcript.json",
                "required": True,
            }
        )
    workflow.extend(
        [
            {
                "id": "verify-inputs",
                "command": "./verify-inputs.sh",
                "required": True,
            },
            {
                "id": "inspect-only",
                "command": "./inspect-only.sh",
                "required": True,
            },
            {
                "id": "import-fixture",
                "command": "./import-fixture.sh",
                "required": True,
            },
            {
                "id": "check-coverage",
                "command": "./check-coverage.sh",
                "required": True,
            },
            {
                "id": "check-fixture-set",
                "command": "./check-fixture-set.sh",
                "required": True,
            },
        ]
    )
    if (result.get("commands") or {}).get("ocuCandidate") is not None:
        workflow.append(
            {
                "id": "ingest-ocu-candidate",
                "command": "./ingest-ocu-candidate.sh",
                "required": False,
                "condition": "same-scenario OCU candidate wrapper is generated for this scenario",
            }
        )
    workflow.extend(
        [
            {
                "id": "strict-golden-gate",
                "command": "./strict-golden-gate.sh",
                "required": True,
                "condition": "after required official successful recording fixtures are imported",
            },
            {
                "id": "strict-expected-failure-audit",
                "command": "./strict-expected-failure-audit.sh",
                "required": True,
                "condition": "while required official successful recording fixtures are still missing",
            },
        ]
    )
    return workflow


def render_capture_readme(result: dict[str, Any], *, include_transcript: bool) -> str:
    recipe = result["scenarioRecipe"]
    commands = result["commands"]
    expected_events = ", ".join(recipe.get("expectedActionEvents") or ["<none>"])
    expected_end_reason = recipe.get("expectedEndReason")
    if expected_end_reason is None:
        expected_end_reason = "<observe official value>"
    notes = "\n".join(f"- {note}" for note in recipe.get("notes", []))
    transcript_requirement = "yes" if include_transcript else "no"
    if include_transcript:
        transcript_input = (
            "- `inputs/mcp-transcript.json`: required same-session MCP transcript evidence."
        )
    else:
        transcript_input = (
            "This packet was generated with `--no-include-transcript`; it does not create "
            "`inputs/mcp-transcript.json`, and generated inspect/import commands do not "
            "require MCP transcript evidence."
        )
    if commands.get("ocuCandidateShell"):
        ocu_candidate_step = (
            "\n        After the official fixture imports cleanly, run:\n\n"
            "        ```sh\n"
            "        ./ingest-ocu-candidate.sh\n"
            "        ```\n"
        )
    else:
        ocu_candidate_step = (
            "\n        This scenario does not have a generated OCU candidate ingest wrapper; "
            "use the `commands.ocuCandidateNote` guidance in `preflight.json`.\n"
        )
    return textwrap.dedent(
        f"""\
        # Record & Replay Official Capture Packet

        Scenario: `{result["scenario"]}`
        Fixture name: `{result["fixtureName"]}`
        MCP transcript input required: `{transcript_requirement}`

        ## Capture Goal

        {recipe["captureGoal"]}

        User action:

        {recipe["userAction"]}

        Expected action events: `{expected_events}`
        Expected end reason: `{expected_end_reason}`

        Notes:

        {notes}

        ## Inputs

        Replace these placeholder files after the official hosted recording finishes:

        - `inputs/event_stream_stop-response.json`: final `event_stream_stop` or completed `event_stream_status` JSON from the official Codex Record & Replay tool.
        {transcript_input}

        `capture-contract.json` records the expected scenario, handoff path evidence, transcript evidence requirement, action events, and end reason for this packet. `verify-inputs.sh` checks that the status JSON contains Record & Replay handoff path evidence and, when transcript input is enabled, that `inputs/mcp-transcript.json` looks like an MCP transcript.

        `capture-contract.json` also includes `postCaptureWorkflow`, the machine-readable command order to run after hosted official recording completes.

        `verify-workflow.sh` checks that this packet's machine-readable workflow still matches the generated inputs and wrapper scripts. It does not inspect hosted JSON and can run before recording.

        Do not commit raw official recording JSON, screenshots, secrets, private text, or machine-local paths. Run inspect-only first, then let the import script create a sanitized fixture.

        ## Commands

        If you captured hosted Codex tool responses as separate JSON files, first finalize packet inputs from the repository root:

        ```sh
        python3 scripts/finalize-record-and-replay-official-capture-packet.py \\
          --packet-dir <this-packet-dir> \\
          --start-json <event_stream_start-response.json> \\
          --status-json <event_stream_status-active-response.json> \\
          --stop-json <event_stream_stop-response.json> \\
          --final-status-json <event_stream_status-final-response.json>
        ```

        From this packet directory, run:

        ```sh
        ./verify-inputs.sh
        ./verify-workflow.sh
        ./inspect-only.sh
        ./import-fixture.sh
        ./check-coverage.sh
        ./check-fixture-set.sh
        ./strict-golden-gate.sh
        ./strict-expected-failure-audit.sh
        ```
        {ocu_candidate_step}

        The generated shell wrappers embed the repository path captured when this packet was created. Set `REPO_ROOT=/path/to/repo` if you move the packet or run it against another checkout.

        Equivalent inspect-only command:

        ```sh
        {commands["inspectOnlyShell"]}
        ```

        Equivalent import command:

        ```sh
        {commands["importFixtureShell"]}
        ```

        Equivalent fixture-set gate:

        ```sh
        {commands["fixtureSetShell"]}
        ```

        Equivalent strict golden gate audit:

        ```sh
        {commands["strictOfficialGoldenGateShell"]}
        ```

        Equivalent strict expected-failure audit while required official golden is still missing:

        ```sh
        {commands["strictOfficialGoldenExpectedFailureAuditShell"]}
        ```
        """
    )


def write_capture_packet(
    packet_dir: pathlib.Path,
    result: dict[str, Any],
    args: argparse.Namespace,
    repo: pathlib.Path,
) -> dict[str, Any]:
    packet_dir.mkdir(parents=True, exist_ok=True)
    inputs_dir = packet_dir / "inputs"
    inputs_dir.mkdir(parents=True, exist_ok=True)

    commands = result["commands"]
    files: list[str] = []

    def record(path: pathlib.Path) -> None:
        files.append(display_path(path, repo))

    readme = packet_dir / "README.md"
    write_text(readme, render_capture_readme(result, include_transcript=args.include_transcript))
    record(readme)

    recipe_path = packet_dir / "scenario-recipe.json"
    write_text(recipe_path, json.dumps(result["scenarioRecipe"], indent=2, sort_keys=True) + "\n")
    record(recipe_path)

    contract = capture_contract(result, include_transcript=args.include_transcript)
    contract_path = packet_dir / "capture-contract.json"
    write_text(contract_path, json.dumps(contract, indent=2, sort_keys=True) + "\n")
    record(contract_path)

    preflight_path = packet_dir / "preflight.json"
    write_text(preflight_path, json.dumps(result, indent=2, sort_keys=True) + "\n")
    record(preflight_path)

    status_path = inputs_dir / "event_stream_stop-response.json"
    write_text(status_path, placeholder_json("official event_stream_stop or completed event_stream_status response JSON"))
    record(status_path)

    transcript_path = inputs_dir / "mcp-transcript.json"
    if args.include_transcript:
        write_text(transcript_path, placeholder_json("same-session official MCP transcript JSON"))
        record(transcript_path)

    scripts = {
        "verify-inputs.sh": None,
        "verify-workflow.sh": None,
        "inspect-only.sh": commands.get("inspectOnly"),
        "import-fixture.sh": commands.get("importFixture"),
        "check-coverage.sh": commands.get("coverageReadiness"),
        "check-fixture-set.sh": commands.get("fixtureSet"),
        "strict-golden-gate.sh": commands.get("strictOfficialGoldenGate"),
        "strict-expected-failure-audit.sh": commands.get(
            "strictOfficialGoldenExpectedFailureAudit"
        ),
    }
    if commands.get("ocuCandidate") is not None:
        scripts["ingest-ocu-candidate.sh"] = commands.get("ocuCandidate")
    for name, command in scripts.items():
        path = packet_dir / name
        if name == "verify-inputs.sh":
            write_text(path, render_packet_inputs_script(args), executable=True)
        elif name == "verify-workflow.sh":
            write_text(path, render_workflow_verifier_script(packet_set=False), executable=True)
        else:
            write_text(path, render_packet_script(command, args, repo), executable=True)
        record(path)

    return {
        "path": display_path(packet_dir, repo),
        "files": files,
        "includeTranscript": bool(args.include_transcript),
        "requiresMcpTranscriptInput": bool(args.include_transcript),
        "postCaptureWorkflow": contract["postCaptureWorkflow"],
        "captureContractPath": display_path(contract_path, repo),
        "statusResponseInputPath": display_path(status_path, repo),
        "mcpTranscriptInputPath": display_path(transcript_path, repo)
        if args.include_transcript
        else None,
        "verifyInputsShell": f"bash {display_path(packet_dir / 'verify-inputs.sh', repo)}",
        "verifyWorkflowShell": f"bash {display_path(packet_dir / 'verify-workflow.sh', repo)}",
        "inspectOnlyShell": f"bash {display_path(packet_dir / 'inspect-only.sh', repo)}",
        "importFixtureShell": f"bash {display_path(packet_dir / 'import-fixture.sh', repo)}",
        "checkCoverageShell": f"bash {display_path(packet_dir / 'check-coverage.sh', repo)}",
        "checkFixtureSetShell": f"bash {display_path(packet_dir / 'check-fixture-set.sh', repo)}",
        "strictGoldenGateShell": f"bash {display_path(packet_dir / 'strict-golden-gate.sh', repo)}",
        "strictExpectedFailureAuditShell": (
            f"bash {display_path(packet_dir / 'strict-expected-failure-audit.sh', repo)}"
        ),
        "ingestOcuCandidateShell": (
            f"bash {display_path(packet_dir / 'ingest-ocu-candidate.sh', repo)}"
            if commands.get("ocuCandidate") is not None
            else None
        ),
    }


def write_capture_packet_set(
    root: pathlib.Path,
    scenarios: list[str],
    results: list[dict[str, Any]],
    repo: pathlib.Path,
    *,
    include_transcript: bool,
) -> dict[str, Any]:
    root.mkdir(parents=True, exist_ok=True)
    packets = {
        result["scenario"]: result.get("capturePacket")
        for result in results
        if isinstance(result.get("capturePacket"), dict)
    }
    contracts = {
        result["scenario"]: capture_contract(result, include_transcript=include_transcript)
        for result in results
        if isinstance(result.get("capturePacket"), dict)
    }
    workflows = {
        scenario: contract.get("postCaptureWorkflow", [])
        for scenario, contract in contracts.items()
    }
    contract_paths = {
        scenario: packet.get("captureContractPath")
        for scenario, packet in packets.items()
        if isinstance(packet.get("captureContractPath"), str)
    }
    scripts = {
        "verifyAll": root / "verify-all.sh",
        "verifyWorkflow": root / "verify-workflow.sh",
        "inspectAll": root / "inspect-all.sh",
        "importAll": root / "import-all.sh",
        "checkAll": root / "check-all.sh",
        "ingestOcuCandidates": root / "ingest-ocu-candidates.sh",
        "strictExpectedFailureAudit": root / "strict-expected-failure-audit.sh",
    }
    write_text(
        scripts["verifyAll"],
        render_packet_set_script(scenarios, "verify-inputs.sh", include_transcript=include_transcript),
        executable=True,
    )
    write_text(
        scripts["verifyWorkflow"],
        render_workflow_verifier_script(packet_set=True),
        executable=True,
    )
    write_text(
        scripts["inspectAll"],
        render_packet_set_script(scenarios, "inspect-only.sh", include_transcript=include_transcript),
        executable=True,
    )
    write_text(
        scripts["importAll"],
        render_packet_set_script(scenarios, "import-fixture.sh", include_transcript=include_transcript),
        executable=True,
    )
    write_text(
        scripts["checkAll"],
        render_packet_set_script(scenarios, "check-coverage.sh", include_transcript=include_transcript),
        executable=True,
    )
    write_text(
        scripts["ingestOcuCandidates"],
        render_packet_set_optional_script(scenarios, "ingest-ocu-candidate.sh"),
        executable=True,
    )
    strict_expected_failure_command = [
        "python3",
        "scripts/check-record-and-replay-baseline-summary.py",
        "dist/record-and-replay-official-golden-gate-summary.json",
        "--allow-strict-official-golden-missing",
    ]
    write_text(
        scripts["strictExpectedFailureAudit"],
        render_repo_script(strict_expected_failure_command, repo),
        executable=True,
    )

    manifest = {
        "stage": "capture-packet-set",
        "scenarios": scenarios,
        "includeTranscript": include_transcript,
        "requiresMcpTranscriptInput": include_transcript,
        "capturePackets": packets,
        "captureContracts": contracts,
        "captureContractPaths": contract_paths,
        "postCaptureWorkflow": workflows,
        "scripts": {name: display_path(path, repo) for name, path in scripts.items()},
        "results": results,
    }
    write_text(root / "capture-packets.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    scenario_lines = "\n".join(f"- `{scenario}`: `{scenario}/README.md`" for scenario in scenarios)
    transcript_requirement = "yes" if include_transcript else "no"
    if include_transcript:
        transcript_step = (
            "2. Replace `inputs/mcp-transcript.json` with same-session transcript evidence."
        )
    else:
        transcript_step = (
            "2. This packet set was generated with `--no-include-transcript`; it does not "
            "create or require `inputs/mcp-transcript.json`."
        )
    write_text(
        root / "README.md",
        textwrap.dedent(
            f"""\
            # Record & Replay Official Capture Packet Set

            This directory contains one official capture packet per scenario. These packets do not start official recording and do not write fixtures. Use them after each Codex-hosted official Record & Replay recording completes.

            MCP transcript input required: `{transcript_requirement}`

            `capture-packets.json` includes `captureContracts`, a machine-readable per-scenario copy of each packet's `capture-contract.json`.

            It also includes `postCaptureWorkflow`, the ordered per-scenario command plan to run after hosted official recording completes.

            `verify-workflow.sh` checks that `capture-packets.json`, each child `capture-contract.json`, and the generated wrapper scripts still agree. It does not inspect hosted JSON and can run before recording.

            ## Scenarios

            {scenario_lines}

            ## Workflow

            For each scenario directory:

            1. Replace `inputs/event_stream_stop-response.json` with the hosted official `event_stream_stop` or completed `event_stream_status` JSON.
            {transcript_step}
            3. Run `./inspect-only.sh`.
            4. If inspect-only succeeds, run `./import-fixture.sh`.
            5. Run `./check-coverage.sh` after importing required samples.

            Do not commit raw hosted JSON, screenshots, secrets, private text, or machine-local paths. Commit only sanitized fixtures produced by the import script.

            After replacing inputs, the root helpers can run every scenario in order:

            ```sh
            ./verify-all.sh
            ./verify-workflow.sh
            ./inspect-all.sh
            ./import-all.sh
            ./check-all.sh
            ./strict-expected-failure-audit.sh
            ```

            For scenarios that support synthetic OCU candidate sampling, run:

            ```sh
            ./ingest-ocu-candidates.sh
            ```

            The candidate helper imports same-scenario OCU candidate fixtures but does not make candidate comparison part of the required official golden gate. It skips scenarios without a generated per-scenario OCU candidate wrapper, such as recording-required keyboard, cancel, or timeout scenarios. To use candidates for calibration, run the `fixtureSetGateShell` or `pairingPreflightShell` printed by each candidate import.
            """
        ),
    )
    return {
        "path": display_path(root, repo),
        "manifestPath": display_path(root / "capture-packets.json", repo),
        "readmePath": display_path(root / "README.md", repo),
        "scenarios": scenarios,
        "includeTranscript": include_transcript,
        "requiresMcpTranscriptInput": include_transcript,
        "capturePackets": packets,
        "captureContracts": contracts,
        "captureContractPaths": contract_paths,
        "postCaptureWorkflow": workflows,
        "scripts": {name: display_path(path, repo) for name, path in scripts.items()},
        "verifyWorkflowShell": (
            f"bash {display_path(root / 'verify-workflow.sh', repo)}"
        ),
        "ingestOcuCandidatesShell": (
            f"bash {display_path(root / 'ingest-ocu-candidates.sh', repo)}"
        ),
        "strictExpectedFailureAuditShell": (
            f"bash {display_path(root / 'strict-expected-failure-audit.sh', repo)}"
        ),
    }


def preflight_packet_set(args: argparse.Namespace) -> tuple[int, dict[str, Any]]:
    repo = pathlib.Path(__file__).resolve().parents[1]
    if args.capture_packet_dir is None:
        return 1, {
            "ok": False,
            "stage": "capture-packet-set",
            "errors": ["--capture-packet-dir is required with --capture-packet-recommended-scenarios"],
        }
    if args.name:
        return 1, {
            "ok": False,
            "stage": "capture-packet-set",
            "errors": ["--name cannot be used with --capture-packet-recommended-scenarios"],
        }

    scenarios = list(dict.fromkeys(args.recommended_scenario))
    results: list[dict[str, Any]] = []
    ok = True
    for scenario in scenarios:
        scenario_args = argparse.Namespace(**vars(args))
        scenario_args.scenario = scenario
        scenario_args.name = None
        scenario_args.capture_packet_dir = args.capture_packet_dir / scenario
        exit_code, result = preflight(scenario_args)
        results.append(result)
        ok = ok and exit_code == 0

    capture_packet_set = write_capture_packet_set(
        args.capture_packet_dir,
        scenarios,
        results,
        repo,
        include_transcript=args.include_transcript,
    )
    result = {
        "ok": ok,
        "stage": "capture-packet-set",
        "capturePacketSet": capture_packet_set,
        "scenarios": scenarios,
        "results": results,
        "nextActions": [
            "Capture each hosted official Record & Replay scenario, replace the matching packet inputs, then run that packet's inspect-only.sh.",
            "Import required scenarios first; recommended scenarios calibrate keyboard, drag, cancel, and timeout behavior.",
        ],
    }
    return 0 if ok else 1, result


def readiness_status(coverage: dict[str, Any], scenario: str) -> dict[str, Any]:
    missing = coverage.get("missingOfficialScenarios")
    not_ready = coverage.get("notReadyOfficialScenarios")
    available = coverage.get("availableOfficialScenarios")
    if not isinstance(missing, list):
        missing = []
    if not isinstance(not_ready, list):
        not_ready = []
    if not isinstance(available, list):
        available = []
    scenario_available = scenario in available
    scenario_missing = scenario in missing or not scenario_available
    scenario_not_ready = scenario in not_ready
    ready = (
        scenario_available
        and not scenario_missing
        and not scenario_not_ready
        and coverage.get("coverageOk") is True
        and coverage.get("requiredOfficialReadinessOk") is True
    )
    return {
        "scenario": scenario,
        "available": scenario_available,
        "missing": scenario_missing,
        "notReady": scenario_not_ready,
        "ready": ready,
    }


def preflight(args: argparse.Namespace) -> tuple[int, dict[str, Any]]:
    repo = pathlib.Path(__file__).resolve().parents[1]
    fixture_root = args.fixture_root
    fixture_name = args.name or default_fixture_name(args.scenario, args.official_plugin_version)

    coverage_command = [
        sys.executable,
        str(repo / "scripts/check-event-stream-official-fixture-coverage.py"),
        "--fixture-root",
        str(fixture_root),
        "--allow-missing",
        "--check-readiness",
    ]
    for scenario in args.require_scenario:
        coverage_command.extend(["--require-scenario", scenario])
    for scenario in args.recommended_scenario:
        coverage_command.extend(["--recommended-scenario", scenario])
    coverage_ok, coverage = run_json(coverage_command, repo)

    plugin_versions = discover_official_plugin_versions(args.official_plugin_root, repo)
    plugin_available = any(version.get("hasSkill") for version in plugin_versions)
    scenario_status = readiness_status(coverage, args.scenario)
    commands = build_commands(repo, args, fixture_name)
    missing_required = coverage.get("missingOfficialScenarios")
    missing_recommended = coverage.get("missingRecommendedOfficialScenarios")
    not_ready = coverage.get("notReadyOfficialScenarios")
    coverage_errors = coverage.get("errors")
    if not isinstance(coverage_errors, list):
        coverage_errors = []

    result: dict[str, Any] = {
        "ok": coverage_ok and (plugin_available or args.allow_missing_official_plugin),
        "stage": "preflight",
        "scenario": args.scenario,
        "fixtureName": fixture_name,
        "fixtureRoot": display_path(fixture_root, repo),
        "officialPlugin": {
            "root": display_path(args.official_plugin_root, repo),
            "available": plugin_available,
            "versions": plugin_versions,
            "allowedMissing": args.allow_missing_official_plugin,
        },
        "scenarioRecipe": scenario_recipe(args.scenario),
        "coverage": coverage,
        "coverageErrors": coverage_errors,
        "scenarioStatus": scenario_status,
        "nextActions": [],
        "commands": commands,
    }

    if args.capture_packet_dir is not None:
        result["capturePacket"] = write_capture_packet(args.capture_packet_dir, result, args, repo)
        result["nextActions"].append(
            "Replace capture packet input placeholders with hosted official JSON, run capturePacket.verifyInputsShell, then run capturePacket.inspectOnlyShell."
        )

    if not plugin_available:
        result["nextActions"].append(
            "Install or restore the official bundled record-and-replay plugin cache, "
            "or pass --allow-missing-official-plugin when preparing commands only."
        )
    if coverage_errors:
        result["nextActions"].append(
            "Fix official fixture coverage errors before importing or pairing candidates: "
            + " | ".join(str(error) for error in coverage_errors)
        )
    if scenario_status["missing"]:
        result["nextActions"].append(
            f"Capture hosted official Record & Replay scenario {args.scenario!r}, then run commands.inspectOnly."
        )
    elif scenario_status["notReady"]:
        result["nextActions"].append(
            f"Re-import or repair official scenario {args.scenario!r}; existing fixture does not pass readiness."
        )
    else:
        result["nextActions"].append(
            f"Official scenario {args.scenario!r} is present; run commands.strictOfficialGoldenGate before release to refresh the strict summary artifact."
        )

    if missing_required:
        result["nextActions"].append(f"Missing required official scenarios: {', '.join(missing_required)}.")
    if not_ready:
        result["nextActions"].append(f"Not-ready official scenarios: {', '.join(not_ready)}.")
    if missing_recommended:
        result["nextActions"].append(
            f"Recommended follow-up official scenarios still missing: {', '.join(missing_recommended)}."
        )

    if args.require_ready and not scenario_status["ready"]:
        result["ok"] = False
        result["requireReady"] = True
    else:
        result["requireReady"] = False

    return 0 if result["ok"] else 1, result


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare the next official Record & Replay successful recording golden capture. "
            "This command is read-only: it reports current coverage and prints inspect/import commands."
        )
    )
    parser.add_argument(
        "--scenario",
        default=DEFAULT_SCENARIO,
        help=(
            f"Official scenario to prepare. Defaults to {DEFAULT_SCENARIO}. "
            f"Required scenarios: {DEFAULT_REQUIRED_SCENARIO_HELP}."
        ),
    )
    parser.add_argument("--name", help="Fixture name to use in generated ingest commands.")
    parser.add_argument(
        "--fixture-root",
        type=pathlib.Path,
        default=DEFAULT_FIXTURE_ROOT,
        help=f"Official recording fixture root. Defaults to {DEFAULT_FIXTURE_ROOT}.",
    )
    parser.add_argument(
        "--official-plugin-root",
        type=pathlib.Path,
        default=DEFAULT_OFFICIAL_PLUGIN_ROOT,
        help=f"Bundled official record-and-replay plugin cache root. Defaults to {DEFAULT_OFFICIAL_PLUGIN_ROOT}.",
    )
    parser.add_argument(
        "--official-plugin-version",
        default=DEFAULT_OFFICIAL_PLUGIN_VERSION,
        help=f"Version string to write during import. Defaults to {DEFAULT_OFFICIAL_PLUGIN_VERSION!r}.",
    )
    parser.add_argument(
        "--status-json-placeholder",
        default="<event_stream_stop-response.json>",
        help="Placeholder path used in generated inspect/import commands.",
    )
    parser.add_argument(
        "--status-json-base-dir-placeholder",
        default=None,
        help="Optional placeholder for --status-json-base-dir in generated commands.",
    )
    parser.add_argument(
        "--mcp-transcript-placeholder",
        default="<mcp-transcript.json>",
        help="Placeholder path used when --include-transcript is enabled.",
    )
    parser.add_argument(
        "--include-transcript",
        action="store_true",
        default=True,
        help="Include --mcp-transcript and --require-mcp-transcript-evidence in generated commands.",
    )
    parser.add_argument(
        "--no-include-transcript",
        action="store_false",
        dest="include_transcript",
        help="Do not include transcript flags in generated inspect/import commands.",
    )
    parser.add_argument(
        "--require-coverage-on-import",
        action="store_true",
        help="Add --require-coverage to the generated import command.",
    )
    parser.add_argument(
        "--require-scenario",
        action="append",
        default=[],
        help=(
            "Required scenario to pass to coverage report. Defaults to "
            f"{DEFAULT_REQUIRED_SCENARIO_HELP}."
        ),
    )
    parser.add_argument(
        "--recommended-scenario",
        action="append",
        default=[],
        help="Recommended scenario to pass to coverage report. Defaults to the coverage script defaults.",
    )
    parser.add_argument(
        "--allow-missing-official-plugin",
        action="store_true",
        help="Do not fail when the local official bundled plugin cache is absent.",
    )
    parser.add_argument(
        "--require-ready",
        action="store_true",
        help="Fail unless the selected scenario is already present and passes required readiness.",
    )
    parser.add_argument(
        "--capture-packet-dir",
        type=pathlib.Path,
        default=None,
        help=(
            "Write a local capture packet with scenario recipe, placeholder inputs, and inspect/import wrappers. "
            "No official recording is started."
        ),
    )
    parser.add_argument(
        "--capture-packet-recommended-scenarios",
        action="store_true",
        help=(
            "With --capture-packet-dir, write one capture packet per recommended scenario. "
            "No official recording is started."
        ),
    )
    args = parser.parse_args()
    if not args.require_scenario:
        args.require_scenario = list(DEFAULT_REQUIRED_SCENARIOS)
    if not args.recommended_scenario:
        args.recommended_scenario = list(DEFAULT_RECOMMENDED_SCENARIOS)
    if args.capture_packet_recommended_scenarios:
        exit_code, result = preflight_packet_set(args)
    else:
        exit_code, result = preflight(args)
    output = json.dumps(result, indent=2, sort_keys=True)
    if exit_code == 0:
        print(output)
    else:
        print(output, file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
