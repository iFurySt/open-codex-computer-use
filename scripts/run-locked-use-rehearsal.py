#!/usr/bin/env python3
"""Interactive development test only. Never called from CI or normal OCU tools.

The controller retains a recovery path while the GUI test filters local input.
An emergency timeout tears down only this test's process group. That recovery
is not a production privacy guarantee and must not be reused as shield release.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm-lock-test", action="store_true", required=True,
                        help="confirm that the user is ready for shields and a screen lock")
    args = parser.parse_args()
    if not args.confirm_lock_test:
        return 64
    root = Path(__file__).resolve().parent.parent
    binary = root / ".build/locked-use/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian"
    if not binary.is_file():
        print("Build the Guardian bundle first.", file=sys.stderr)
        return 1
    probe = subprocess.run([str(binary), "--diagnose"], capture_output=True, text=True, timeout=10)
    diagnostics = json.loads(probe.stdout)
    if probe.returncode or not all(diagnostics.get(key) is True for key in ["accessibility", "inputMonitoring", "lockSPIAvailable"]):
        print(json.dumps({"event": "preflightFailed", "diagnostics": diagnostics}), flush=True)
        return 1
    if diagnostics.get("secureInput") or diagnostics.get("session") != "unlocked":
        print("Rehearsal requires a manually unlocked GUI session with Secure Input off.", file=sys.stderr)
        return 1
    print(json.dumps({"event": "controllerStarting", "timeoutSeconds": 35,
                      "unlockRequested": False}), flush=True)
    process = subprocess.Popen([str(binary), "--rehearse", "--confirm-lock-test"], start_new_session=True)
    recovered = False
    try:
        return process.wait(timeout=35)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        recovered = True
        print(json.dumps({"event": "rehearsalRecovery", "productionReady": False}), flush=True)
        return 2
    finally:
        # The watchdog is intentionally a separate process. Remove only this
        # controller's new process group, including any surviving test child.
        if recovered or process.poll() is not None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()


if __name__ == "__main__":
    sys.exit(main())
