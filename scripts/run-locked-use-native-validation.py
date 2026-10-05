#!/usr/bin/env python3
"""Supervised real unlock test. Never print screenshots or Keychain contents.

Run --prepare-only first. --confirm-lock-test locks the current session, invokes
the fixed signed native AX/SCK probe, holds the lease, ends it and waits for
manual unlock. Do not terminate Guardian/watchdog on a failed transaction.
"""
import argparse
import json
import os
import pathlib
import select
import subprocess
import sys
import time
from locked_use_report import LiveAuthenticationTrace, write_report


class RPC:
    def __init__(self, binary):
        environment = dict(os.environ)
        environment["OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE"] = "locked-use-native-validation"
        environment["OPEN_COMPUTER_USE_VISUAL_CURSOR"] = "0"
        self.process = subprocess.Popen([str(binary), "mcp"], env=environment,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL)
        self.buffer = b""
        self.sequence = 0
        self.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                 "clientInfo": {"name": "locked-use-native-validation", "version": "1"}})

    def notify(self, method):
        self.send({"jsonrpc": "2.0", "method": method})

    def send(self, message):
        self.process.stdin.write(json.dumps(message).encode() + b"\n")
        self.process.stdin.flush()

    def call(self, method, params=None, timeout=10):
        self.sequence += 1
        identifier = self.sequence
        self.send({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params or {}})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                response = json.loads(line)
                if response.get("id") == identifier:
                    if "error" in response:
                        raise RuntimeError(response["error"].get("message", "Native RPC failed"))
                    return response.get("result")
            ready, _, _ = select.select([self.process.stdout], [], [], min(1, max(0, deadline-time.monotonic())))
            if ready:
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk: raise RuntimeError("Native validation connection closed")
                self.buffer += chunk
                if len(self.buffer) > 8*1024*1024: raise RuntimeError("Native response exceeded bound")
        raise TimeoutError("Native validation response timed out")

    def close(self):
        if self.process.stdin and not self.process.stdin.closed: self.process.stdin.close()
        try: self.process.wait(timeout=5)
        except subprocess.TimeoutExpired: self.process.terminate()


def session(guardian, timeout=3):
    result = subprocess.run([str(guardian), "--session-only"], capture_output=True, timeout=timeout, check=True)
    for line in result.stdout.splitlines():
        value = json.loads(line)
        if value.get("event") == "sessionState": return value["session"]
    raise RuntimeError("Native session observation unavailable")


def wait_for(guardian, state, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if session(guardian) == state: return
        time.sleep(0.2)
    raise TimeoutError("Did not observe original session " + state)


def wait_for_release(rpc, timeout=3):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if rpc.call("ocu/locked-use/protection-released", timeout=min(2, deadline-time.monotonic()))["passed"]: return
        time.sleep(0.1)
    raise TimeoutError("Both protection release acknowledgments were not observed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--confirm-lock-test", action="store_true")
    mode.add_argument("--unlocked-fixture-test", action="store_true")
    mode.add_argument("--observe-auth-only", action="store_true", help="Read normalized authentication logs only; never lock, submit credentials or acquire a permit")
    mode.add_argument("--confirm-recovery-test", action="store_true", help="Lock once and verify both guards drain, without issuing an unlock permit")
    mode.add_argument("--confirm-wake-test", action="store_true", help="Validate protected unlock then immediately relock; no GUI/Keychain operations")
    parser.add_argument("--wait-for-manual-unlock", action="store_true", help="Observe normal user unlock without an interactive continue prompt")
    parser.add_argument("--legacy-only", action="store_true", help="Does not produce production validation evidence")
    parser.add_argument("--hold-seconds", type=int, default=15, choices=range(0, 21))
    parser.add_argument("--fast", action="store_true", help="Relock immediately after the fixed AX/SCK validation")
    parser.add_argument("--observe-seconds", type=int, default=30, choices=range(5, 61))
    args = parser.parse_args()
    if args.fast: args.hold_seconds = 0
    run_started = time.time()
    events = []
    failure = None
    def record(event, **details):
        value = {"event": event, "elapsedSeconds": round(time.time()-run_started, 3), **details}
        events.append(value)
        print(json.dumps(value), flush=True)
    root = pathlib.Path(__file__).resolve().parent.parent
    if args.observe_auth_only:
        trace = LiveAuthenticationTrace(run_started, max_seconds=args.observe_seconds)
        trace.start()
        record("authenticationObserverStarted", authenticationRequested=False, lockRequested=False)
        try:
            time.sleep(args.observe_seconds)
        finally:
            live_events, trace_status = trace.finish()
            report = write_report(root, run_started, events, live_events=live_events, trace_status=trace_status)
            record("diagnosticReportSaved", path=str(report), traceStatus=trace_status)
        return
    binary = root / "dist/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse"
    components = root / ".build/locked-use/components"
    guardian = components / "Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian"
    fixture_binary = components / "Locked Use Native Fixture (Dev).app/Contents/MacOS/OpenComputerUseGuardian"
    if session(guardian, timeout=15) != "unlocked": raise RuntimeError("Unlock normally before starting validation")
    rpc = RPC(binary)
    fixture = None
    locked = False
    completed = False
    trace = LiveAuthenticationTrace(run_started)
    trace.start()
    try:
        if args.confirm_lock_test or args.confirm_recovery_test or args.confirm_wake_test:
            if not rpc.call("ocu/locked-use/ready", timeout=5)["passed"]:
                raise RuntimeError("Broker has not observed a normal unlock and released protection; no lock test started")
            record("brokerReady", passed=True)
        if args.confirm_recovery_test or args.confirm_wake_test:
            print("Locking in 5 seconds; recovery-only." if args.confirm_recovery_test else
                  "Locking in 5 seconds; protected wake/unlock then immediate relock.", flush=True)
            time.sleep(5)
            subprocess.run([str(guardian), "--request-lock"], check=True, stdout=subprocess.DEVNULL, timeout=3)
            locked = True
            wait_for(guardian, "locked", timeout=5)
            record("lockedObserved")
            started = time.monotonic()
            method = "ocu/locked-use/validate-recovery" if args.confirm_recovery_test else "ocu/locked-use/validate-unlock"
            assert rpc.call(method, timeout=10)["passed"]
            if args.confirm_wake_test:
                record("protectedUnlockObserved", acquisitionSeconds=round(time.monotonic()-started, 3), guiActionsPerformed=False)
                rpc.notify("notifications/turn-ended")
                wait_for(guardian, "locked", timeout=5)
            wait_for_release(rpc)
            record("bothGuardsReleased", passed=True)
            completed = True
            record("bothGuardsRecoveryPassed" if args.confirm_recovery_test else "relockObserved",
                   transactionSeconds=round(time.monotonic()-started, 3), unlockPermitIssued=args.confirm_wake_test, guiActionsPerformed=False)
            return
        prepare = "prepare-legacy" if args.legacy_only else "prepare"
        result = rpc.call("ocu/locked-use/keychain/" + prepare)
        assert result["passed"] and result["existingItemsRead"] is False
        record("isolatedKeychainPrepared", dataProtectionIncluded=not args.legacy_only)
        if args.prepare_only:
            assert rpc.call("ocu/locked-use/keychain/cleanup")["passed"]
            completed = True
            return
        fixture = subprocess.Popen([str(fixture_binary), "--external-fixture"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rpc.call("tools/call", {"name": "get_app_state", "arguments": {"app": "dev.opencomputeruse.locked-use.fixture.dev"}})
        if args.unlocked_fixture_test:
            assert rpc.call("ocu/locked-use/validate-unlocked")["passed"]
            assert rpc.call("ocu/locked-use/keychain/cleanup")["passed"]
            completed = True
            print(json.dumps({"event": "unlockedRealAXSCKPassed", "unlockRequested": False}), flush=True)
            return
        print("Locking in 5 seconds. Leave mouse and keyboard still.", flush=True)
        time.sleep(5)
        subprocess.run([str(guardian), "--request-lock"], check=True, stdout=subprocess.DEVNULL, timeout=3)
        locked = True
        wait_for(guardian, "locked", timeout=5)
        record("lockedObserved")
        result = rpc.call("ocu/locked-use/validate", timeout=10)
        assert result["passed"]
        record("protectedNativeAXSCKKeychainPassed", dataProtectionIncluded=not args.legacy_only)
        time.sleep(args.hold_seconds)
        rpc.notify("notifications/turn-ended")
        wait_for(guardian, "locked", timeout=5)
        record("relockObserved")
        wait_for_release(rpc)
        record("bothGuardsReleased", passed=True)
        if args.wait_for_manual_unlock:
            print("Relock observed. Waiting for normal manual unlock.", flush=True)
            wait_for(guardian, "unlocked", timeout=120)
        else:
            print("Relock observed. Unlock normally, then enter continue here.", flush=True)
            if sys.stdin.readline().strip() != "continue": raise RuntimeError("Manual verification interrupted")
            wait_for(guardian, "unlocked", timeout=5)
        assert rpc.call("ocu/locked-use/keychain/verify-manual")["passed"]
        assert rpc.call("ocu/locked-use/keychain/cleanup")["passed"]
        completed = True
        record("manualUnlockKeychainCleanupPassed", productionEvidenceEligible=not args.legacy_only)
    except Exception as error:
        failure = type(error).__name__
        record("failed", failureType=failure)
        raise
    finally:
        if not completed and locked:
            # Root and the independent guards own relock. An extra controller
            # SPI request can interrupt a user's normal recovery login.
            print("Validation failed; independent guards own recovery. Unlock normally before retrying cleanup.", file=sys.stderr)
            try:
                wait_for_release(rpc)
                record("bothGuardsReleasedAfterFailure", passed=True)
            except Exception:
                record("bothGuardsReleasedAfterFailure", passed=False)
            else:
                if args.wait_for_manual_unlock:
                    try:
                        # Protection is gone; this wait does not keep the desktop
                        # covered. Capture the normal-login mechanism diagnostics.
                        wait_for(guardian, "unlocked", timeout=60)
                        record("manualUnlockAfterFailure", passed=True)
                        if fixture is not None:
                            assert rpc.call("ocu/locked-use/keychain/verify-manual")["passed"]
                            assert rpc.call("ocu/locked-use/keychain/cleanup")["passed"]
                            record("isolatedKeychainCleanupAfterFailure", passed=True)
                    except Exception:
                        record("manualRecoveryVerification", passed=False)
        if not locked or completed:
            try: rpc.call("ocu/locked-use/keychain/cleanup", timeout=5)
            except Exception: pass
        rpc.close()
        if fixture is not None: fixture.terminate()
        live_events, trace_status = trace.finish()
        report = write_report(root, run_started, events, failure, live_events, trace_status)
        print(json.dumps({"event": "diagnosticReportSaved", "path": str(report)}), flush=True)


if __name__ == "__main__":
    main()
