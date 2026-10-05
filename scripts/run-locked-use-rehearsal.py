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
import time


def recover_lock(binary):
    """Retain the independent watchdog while requesting and observing relock."""
    try:
        subprocess.run([str(binary), "--request-lock"], timeout=3, check=False)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            result = subprocess.run([str(binary), "--diagnose"], capture_output=True, text=True, timeout=2)
            state = json.loads(result.stdout).get("session")
            if state == "locked":
                print(json.dumps({"event": "recoveryLockConfirmed"}), flush=True)
                return True
            time.sleep(0.1)
    except (subprocess.TimeoutExpired, ValueError, OSError):
        pass
    print(json.dumps({"event": "recoveryLockUnconfirmed", "productionReady": False}), flush=True)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--confirm-lock-test", action="store_true",
                        help="confirm that the user is ready for shields and a screen lock")
    modes.add_argument("--shield-preview", action="store_true",
                       help="show countdown shields only; no lock, unlock, AX action or capture")
    parser.add_argument("--delay", type=float, default=5,
                        help="seconds before preflight, to let the user release input (default: 5)")
    args = parser.parse_args()
    if not 0 <= args.delay <= 30:
        parser.error("--delay must be between 0 and 30 seconds")
    root = Path(__file__).resolve().parent.parent
    binary = root / ".build/locked-use/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian"
    if not binary.is_file():
        print("Build the Guardian bundle first.", file=sys.stderr)
        return 1
    print(json.dumps({"event": "countdown", "seconds": args.delay}), flush=True)
    time.sleep(args.delay)
    probe = subprocess.run([str(binary), "--diagnose"], capture_output=True, text=True, timeout=10)
    diagnostics = json.loads(probe.stdout)
    required = ["inputMonitoring"] if args.shield_preview else ["accessibility", "inputMonitoring", "lockSPIAvailable"]
    if probe.returncode or not all(diagnostics.get(key) is True for key in required):
        print(json.dumps({"event": "preflightFailed", "diagnostics": diagnostics}), flush=True)
        return 1
    if (not args.shield_preview and diagnostics.get("secureInput")) or diagnostics.get("session") != "unlocked":
        print("Rehearsal requires a manually unlocked GUI session with Secure Input off.", file=sys.stderr)
        return 1
    print(json.dumps({"event": "controllerStarting", "timeoutSeconds": 35,
                      "mode": "shieldPreview" if args.shield_preview else "rehearsal",
                      "unlockRequested": False}), flush=True)
    command = ["--shield-preview"] if args.shield_preview else ["--rehearse", "--confirm-lock-test"]
    process = subprocess.Popen([str(binary), *command], start_new_session=True)
    recovered = False
    try:
        status = process.wait(timeout=35)
        if status != 0:
            recovered = True
            print(json.dumps({"event": "guardianUnexpectedExit", "status": status}), flush=True)
            # Do not kill the independent watchdog before it has relocked.
            if not args.shield_preview:
                recover_lock(binary)
        return status
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        recovered = True
        print(json.dumps({"event": "rehearsalRecovery", "productionReady": False}), flush=True)
        if not args.shield_preview:
            recover_lock(binary)
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
