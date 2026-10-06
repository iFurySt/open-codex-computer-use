"""Native controller transport shutdown, without GUI or system authentication."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location('native_validation', Path(__file__).resolve().parents[1] / 'run-locked-use-native-validation.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class TransportTests(unittest.TestCase):
    def testAgentExitDoesNotMaskOriginalFailureDuringCleanup(self):
        rpc = native.RPC.__new__(native.RPC)
        rpc.process = Mock()
        rpc.process.stdin.closed = False
        rpc.process.stdin.close.side_effect = BrokenPipeError('agent exited')
        rpc.close()
        rpc.process.wait.assert_called_once_with(timeout=5)
        rpc.process.terminate.assert_not_called()


if __name__ == '__main__': unittest.main()
