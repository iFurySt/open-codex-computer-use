#!/usr/bin/env python3
import importlib.util
import pathlib
import sys
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
spec = importlib.util.spec_from_file_location("smoke", root / "run-locked-use-smoke.py")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class SmokeReadbackTests(unittest.TestCase):
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
