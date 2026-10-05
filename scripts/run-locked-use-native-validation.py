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

    def call(self, method, params=None, timeout=25):
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


def session(guardian):
    result = subprocess.run([str(guardian), "--diagnose"], capture_output=True, timeout=3, check=True)
    for line in result.stdout.splitlines():
        value = json.loads(line)
        if value.get("event") == "diagnostics": return value["session"]
    raise RuntimeError("Native session observation unavailable")


def wait_for(guardian, state, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if session(guardian) == state: return
        time.sleep(0.2)
    raise TimeoutError("Did not observe original session " + state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--confirm-lock-test", action="store_true")
    mode.add_argument("--unlocked-fixture-test", action="store_true")
    parser.add_argument("--legacy-only", action="store_true", help="Does not produce production validation evidence")
    parser.add_argument("--hold-seconds", type=int, default=15, choices=range(5, 21))
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    binary = root / "dist/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse"
    components = root / ".build/locked-use/components"
    guardian = components / "Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian"
    fixture_binary = components / "Locked Use Native Fixture (Dev).app/Contents/MacOS/OpenComputerUseGuardian"
    if session(guardian) != "unlocked": raise RuntimeError("Unlock normally before starting validation")
    rpc = RPC(binary)
    fixture = None
    locked = False
    completed = False
    try:
        prepare = "prepare-legacy" if args.legacy_only else "prepare"
        result = rpc.call("ocu/locked-use/keychain/" + prepare)
        assert result["passed"] and result["existingItemsRead"] is False
        print(json.dumps({"event": "isolatedKeychainPrepared", "dataProtectionIncluded": not args.legacy_only}), flush=True)
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
        wait_for(guardian, "locked")
        result = rpc.call("ocu/locked-use/validate")
        assert result["passed"]
        print(json.dumps({"event": "protectedNativeAXSCKKeychainPassed", "dataProtectionIncluded": not args.legacy_only}), flush=True)
        time.sleep(args.hold_seconds)
        rpc.notify("notifications/turn-ended")
        wait_for(guardian, "locked")
        print("Relock observed. Unlock normally, then enter continue here.", flush=True)
        if sys.stdin.readline().strip() != "continue": raise RuntimeError("Manual verification interrupted")
        wait_for(guardian, "unlocked", timeout=5)
        assert rpc.call("ocu/locked-use/keychain/verify-manual")["passed"]
        assert rpc.call("ocu/locked-use/keychain/cleanup")["passed"]
        completed = True
        print(json.dumps({"event": "manualUnlockKeychainCleanupPassed", "productionEvidenceEligible": not args.legacy_only}), flush=True)
    finally:
        if not completed and locked:
            subprocess.run([str(guardian), "--request-lock"], stdout=subprocess.DEVNULL, timeout=3)
            print("Validation failed; independent guards retain their recovery barrier. Unlock normally before retrying cleanup.", file=sys.stderr)
        if not locked or completed:
            try: rpc.call("ocu/locked-use/keychain/cleanup", timeout=5)
            except Exception: pass
        rpc.close()
        if fixture is not None: fixture.terminate()


if __name__ == "__main__":
    main()
