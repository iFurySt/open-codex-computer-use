#!/usr/bin/env python3
"""Exercise normal MCP tools through the installed Locked Use service.

No credential access or test-only unlock RPC. The signed demo stays open after
success so the user can inspect Counter: 1 after normal manual unlock.
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import re
import subprocess
import time

spec = importlib.util.spec_from_file_location("locked_use_runner", pathlib.Path(__file__).with_name("run-locked-use-native-validation.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def read_state(result):
    if result.get("isError"):
        raise RuntimeError("GUI tool failed")
    content = result.get("content", [])
    text = "\n".join(item.get("text", "") for item in content if item.get("type") == "text")
    counts = re.findall(r"Counter: ([0-9]+)", text)
    buttons = [line.split()[0] for line in text.splitlines()
               if "Increment Counter" in line and "locked-use-validation-increment" in line]
    images = [item.get("data", "") for item in content if item.get("type") == "image"]
    if len(counts) != 1 or len(buttons) != 1 or not buttons[0].isdigit() or not images or not images[0]:
        raise RuntimeError("Demo counter, button, or capture missing")
    return int(counts[0]), buttons[0], hashlib.sha256(images[0].encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=pathlib.Path, required=True)
    parser.add_argument("--guardian", type=pathlib.Path, required=True)
    parser.add_argument("--fixture", type=pathlib.Path, required=True)
    parser.add_argument("--confirm-lock-test", action="store_true")
    args = parser.parse_args()
    if runner.session(args.guardian, timeout=15) != "unlocked":
        raise RuntimeError("Unlock normally before testing")
    rpc = runner.RPC(args.app / "Contents/MacOS/OpenComputerUse")
    fixture = None
    locked = False
    completed = False
    started = time.time()
    events = []
    trace = runner.LiveAuthenticationTrace(started)
    trace.start()

    def record(event, **details):
        value = {"event": event, "elapsedSeconds": round(time.time() - started, 3), **details}
        events.append(value)
        print(json.dumps(value), flush=True)

    def snapshot():
        return read_state(rpc.call("tools/call", {"name": "get_app_state", "arguments": {"app": "dev.opencomputeruse.locked-use.fixture.dev"}}, timeout=28))

    try:
        if not rpc.call("ocu/locked-use/ready", timeout=5)["passed"]:
            raise RuntimeError("Broker not ready; no lock requested")
        fixture = subprocess.Popen([str(args.fixture / "Contents/MacOS/OCUGuardian"), "--external-fixture"],
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, start_new_session=True)
        time.sleep(1)
        initial, _, _ = snapshot()
        if initial != 0:
            raise RuntimeError("Expected a fresh demo counter")
        record("demoReady", counter=initial, credentialAccess=False)
        if not args.confirm_lock_test:
            completed = True
            record("unlockedPreflightPassed")
            return
        print("Locking in 5 seconds. Keep the mouse and keyboard still until relock.", flush=True)
        time.sleep(5)
        subprocess.run([str(args.guardian), "--request-lock"], check=True, stdout=subprocess.DEVNULL, timeout=3)
        locked = True
        runner.wait_for(args.guardian, "locked", timeout=5)
        record("lockedObserved")
        before, index, image = snapshot()
        record("normalMCPUnlockedAndCaptured", counter=before)
        click = rpc.call("tools/call", {"name": "click", "arguments": {"app": "dev.opencomputeruse.locked-use.fixture.dev", "element_index": index, "click_method": "accessibility"}}, timeout=10)
        if click.get("isError"):
            raise RuntimeError("Click failed")
        after, _, after_image = snapshot()
        if after != before + 1 or image == after_image:
            raise RuntimeError("Counter or screenshot did not change")
        record("realAXAndCapturePassed", counter=after, imageChanged=True)
        time.sleep(5)
        rpc.notify("notifications/turn-ended")
        runner.wait_for(args.guardian, "locked", timeout=5)
        runner.wait_for_release(rpc)
        record("relockedAndBothGuardsReleased")
        print("Unlock normally. The Counter: 1 window will remain open.", flush=True)
        runner.wait_for(args.guardian, "unlocked", timeout=120)
        final, _, _ = snapshot()
        if final != after:
            raise RuntimeError("Counter changed after manual unlock")
        completed = True
        record("manualUnlockAndCounterPassed", counter=final)
    finally:
        if locked and not completed:
            try:
                rpc.notify("notifications/turn-ended")
                runner.wait_for_release(rpc)
                record("failureGuardsReleased")
            except Exception:
                record("failureRecoveryPending")
        rpc.close()
        if fixture and (not completed or not args.confirm_lock_test):
            fixture.terminate()
        live_events, trace_status = trace.finish()
        path = runner.write_report(pathlib.Path(__file__).resolve().parent.parent, started, events,
                                   live_events=live_events, trace_status=trace_status)
        print(json.dumps({"event": "reportSaved", "path": str(path)}), flush=True)


if __name__ == "__main__":
    main()
