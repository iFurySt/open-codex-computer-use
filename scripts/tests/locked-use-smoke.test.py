#!/usr/bin/env python3
import importlib.util
import pathlib
import sys
import unittest
from unittest.mock import Mock, patch
from contextlib import ExitStack

root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
spec = importlib.util.spec_from_file_location("smoke", root / "run-locked-use-smoke.py")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class SmokeReadbackTests(unittest.TestCase):
    def test_manual_unlock_timeout_retains_counter_after_guard_release(self):
        def state(count):
            return {"content": [{"type": "text", "text": f"Counter: {count}\n3 button Increment Counter locked-use-validation-increment"},
                                {"type": "image", "data": f"image-{count}"}]}
        rpc, fixture, trace = Mock(), Mock(), Mock()
        rpc.call.side_effect = [{"passed": True}, state(0), state(0), {}, state(1)]
        trace.finish.return_value = ([], "ended")
        def wait_for(_guardian, state, **_kwargs):
            if state == "unlocked": raise TimeoutError("Manual unlock not observed")
        with ExitStack() as stack:
            stack.enter_context(patch.object(sys, "argv", ["smoke", "--app", "/tmp/app", "--guardian", "/tmp/guardian", "--fixture", "/tmp/fixture", "--confirm-lock-test"]))
            stack.enter_context(patch.object(smoke.runner, "session", return_value="unlocked"))
            stack.enter_context(patch.object(smoke.runner, "RPC", return_value=rpc))
            stack.enter_context(patch.object(smoke.runner, "LiveAuthenticationTrace", return_value=trace))
            stack.enter_context(patch.object(smoke.runner, "wait_for", side_effect=wait_for))
            released = stack.enter_context(patch.object(smoke.runner, "wait_for_release"))
            stack.enter_context(patch.object(smoke.runner, "write_report", return_value=pathlib.Path("report.json")))
            stack.enter_context(patch.object(smoke.subprocess, "Popen", return_value=fixture))
            stack.enter_context(patch.object(smoke.subprocess, "run"))
            stack.enter_context(patch.object(smoke.time, "sleep"))
            stack.enter_context(patch("builtins.print"))
            with self.assertRaises(TimeoutError): smoke.main()
        fixture.terminate.assert_not_called()
        released.assert_called_once_with(rpc)
        rpc.close.assert_called_once()
        rpc.notify.assert_called_once_with("notifications/turn-ended")

    def test_missing_capture_cannot_pass_counter_verification(self):
        result = {"content": [{"type": "text", "text": "Counter: 1\n3 button Increment Counter locked-use-validation-increment"}]}
        with self.assertRaises(RuntimeError):
            smoke.read_state(result)

    def test_tool_error_cannot_be_used_as_a_successful_readback(self):
        result = {"isError": True, "content": [{"type": "text", "text": "Counter: 1"}, {"type": "image", "data": "image"}]}
        with self.assertRaises(RuntimeError):
            smoke.read_state(result)

    def test_ambiguous_counter_is_rejected(self):
        result = {"content": [{"type": "text", "text": "Counter: 0\nCounter: 1\n3 button Increment Counter locked-use-validation-increment"}, {"type": "image", "data": "image"}]}
        with self.assertRaises(RuntimeError):
            smoke.read_state(result)


if __name__ == "__main__":
    unittest.main()
