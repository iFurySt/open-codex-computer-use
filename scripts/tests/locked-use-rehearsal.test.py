"""Controller recovery tests. No GUI launch, system lock or real processes."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "rehearsal", Path(__file__).resolve().parents[1] / "run-locked-use-rehearsal.py")
rehearsal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rehearsal)


class RecoveryTests(unittest.TestCase):
    def run_controller(self, mode, wait_result, session="unlocked"):
        diagnostics = {"session": session, "secureInput": False,
                       "accessibility": True, "inputMonitoring": True,
                       "lockSPIAvailable": True}
        probe = Mock(returncode=0, stdout=json.dumps(diagnostics))
        process = Mock(pid=4242)
        process.poll.return_value = -5
        if isinstance(wait_result, BaseException):
            process.wait.side_effect = [wait_result, 0]
        else:
            process.wait.return_value = wait_result
        calls = []
        with patch.object(rehearsal.sys, "argv", ["test", mode, "--delay", "0"]), \
             patch.object(rehearsal.Path, "is_file", return_value=True), \
             patch.object(rehearsal.time, "sleep"), \
             patch.object(rehearsal.subprocess, "run", return_value=probe), \
             patch.object(rehearsal.subprocess, "Popen", return_value=process) as launch, \
             patch.object(rehearsal, "recover_lock", side_effect=lambda _: calls.append("relock")), \
             patch.object(rehearsal.os, "killpg", side_effect=lambda *_: calls.append("cleanup")), \
             patch("builtins.print"):
            result = rehearsal.main()
        return result, calls, launch

    def test_crash_retains_watchdog_until_relock_attempt(self):
        result, calls, _ = self.run_controller("--confirm-lock-test", -5)
        self.assertEqual(result, -5)
        self.assertEqual(calls, ["relock", "cleanup"])

    def test_timeout_retains_watchdog_until_relock_attempt(self):
        result, calls, _ = self.run_controller(
            "--confirm-lock-test", subprocess.TimeoutExpired("test", 35))
        self.assertEqual(result, 2)
        self.assertEqual(calls, ["relock", "cleanup"])

    def test_preview_crash_and_timeout_never_request_lock(self):
        for failure in [-5, subprocess.TimeoutExpired("test", 35)]:
            with self.subTest(failure=failure):
                _, calls, launch = self.run_controller("--shield-preview", failure)
                self.assertEqual(calls, ["cleanup"])
                self.assertEqual(launch.call_args.args[0][1:], ["--shield-preview"])

    def test_locked_session_never_launches_preview_or_rehearsal(self):
        for mode in ["--shield-preview", "--confirm-lock-test"]:
            with self.subTest(mode=mode):
                result, calls, launch = self.run_controller(mode, 0, session="locked")
                self.assertEqual(result, 1)
                self.assertEqual(calls, [])
                launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
