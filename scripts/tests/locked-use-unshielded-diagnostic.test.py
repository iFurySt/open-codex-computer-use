"""Diagnostic attribution must distinguish user biometrics from unlock proof."""
import importlib.util
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location('unshielded', Path(__file__).resolve().parents[1] / 'run-locked-use-unshielded-diagnostic.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class AttributionTests(unittest.TestCase):
    def event(self, at, category, message):
        return dict(elapsedSeconds=at, category=category, message=message)
    def window(self):
        return [self.event(1, 'Broker', 'phase=authorizing stopReason=none'),
                self.event(20, 'Broker', 'phase=idle stopReason=none')]
    def testTouchIDBeforePermitIsNotAutomaticUnlock(self):
        events = self.window() + [self.event(15, 'LoginWindow', 'touchIDMatchObserved'),
            self.event(16, 'AuthorizationMechanism', 'resultDelivered allowed=1 status=0')]
        self.assertTrue(module.touch_id_intervened(events))
    def testManualRecoveryAndEarlierTouchIDAreExcluded(self):
        events = self.window() + [self.event(0, 'LoginWindow', 'touchIDMatchObserved'),
                                self.event(21, 'LoginWindow', 'touchIDMatchObserved')]
        self.assertFalse(module.touch_id_intervened(events))
    def testUIEvaluationOrSubmitDoesNotProveHumanInput(self):
        events = self.window() + [self.event(2, 'LoginWindow', 'localAuthenticationEvaluationObserved'),
                                 self.event(3, 'LoginWindow', 'localSubmitObserved')]
        self.assertFalse(module.touch_id_intervened(events))

if __name__ == '__main__': unittest.main()
