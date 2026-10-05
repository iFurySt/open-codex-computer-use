"""Report privacy filters; no desktop, daemon, lock or authentication calls."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import json
import subprocess
import sys

spec = importlib.util.spec_from_file_location("report", Path(__file__).resolve().parents[1]/"locked_use_report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class ReportTests(unittest.TestCase):
    def entry(self, message, category="UnlockTrigger", process="OpenComputerUseGuardian"):
        return {"eventMessage": message, "category": category, "processImagePath": "/private/"+process,
                "timestamp": "2026-10-05T10:00:00+00:00", "privateData": "must never be retained"}

    def testKeepsCodesAndBooleansWithoutRawMetadata(self):
        result = report.curate([self.entry("AXProbe nodes=14 primaryMatches=0 fallbackMatches=1 complete=true")], 0)
        self.assertEqual(len(result), 1)
        self.assertEqual(set(result[0]), {"elapsedSeconds", "category", "message"})
        self.assertNotIn("privateData", str(result))

    def testUnknownAXContentAndTrailingFieldsAreDiscarded(self):
        for message in ["AXValue=user-secret", "AXProbe nodes=14 primaryMatches=0 fallbackMatches=1 complete=true password=user-secret",
                        "AXProbe writable=true status=0 AXTitle=User Name"]:
            self.assertEqual(report.curate([self.entry(message)], 0), [])

    def testSystemRuleEventsDoNotRetainCallerOrAccount(self):
        entry = self.entry("Succeeded authorizing right 'system.login.screensaver' by client /private/example user=secret-account", process="authd")
        result = report.curate([entry], 0)
        self.assertEqual(result[0]["message"], "systemRightSucceeded")
        self.assertNotIn("secret-account", str(result))

    def testPluginPositiveAndNegativeResultsArePreserved(self):
        for message in ["brokerTaskVerification status=1", "pluginConsume replied=1 allowed=1", "resultDelivered allowed=1 status=0"]:
            self.assertEqual(len(report.curate([self.entry(message, "AuthorizationMechanism")], 0)), 1)

    def testMalformedLogsAreDiscarded(self):
        self.assertEqual(report.curate({"unexpected": "object"}, 0), [])
        self.assertEqual(report.curate([None, {"processImagePath": 3}, {"timestamp": []}], 0), [])

    def testOfflineABIAndPreviousRunsCannotCountAsLiveResults(self):
        self.assertEqual(report.curate([self.entry("resultDelivered allowed=1 status=0", "AuthorizationMechanism", "remote-plugin-abi-tests")], 0), [])
        self.assertEqual(report.curate([self.entry("AXProbe writable=true status=0")], 9999999999), [])

    def testSystemStartAndInputMarkersRetainNoCredentials(self):
        for message, process, expected in [
            ('engine 77 evaluates 1 rights "system.login.screensaver" username=secret', 'authd', 'systemRightEvaluationObserved'),
            ('loginPressed password=secret', 'loginwindow', 'localSubmitObserved'),
            ('APEventTouchIDMatch user=secret', 'loginwindow', 'touchIDMatchObserved'),
            ('attempting to unlock with empty might rekey secret', 'loginwindow', 'emptyInputKeychainPathObserved')]:
            result = report.curate([self.entry(message, process=process)], 0)
            self.assertEqual(result[0]['message'], expected)
            self.assertNotIn('secret', str(result))
        self.assertEqual(report.curate([self.entry('loginPressed', process='fake-loginwindow')], 0), [])

    def testManualRecoveryCannotCountAsAutomaticAuthorization(self):
        def event(at, category, message):
            return {'elapsedSeconds': at, 'category': category, 'message': message}
        events = [event(1, 'Broker', 'phase=authorizing stopReason=none'),
                  event(6, 'Broker', 'phase=relocking stopReason=unlockTimeout'),
                  event(10, 'LoginWindow', 'localSubmitObserved'),
                  event(11, 'AuthorizationMechanism', 'mechanismInvoked'),
                  event(12, 'SystemAuthorization', 'systemRightSucceeded')]
        window = report.authentication_windows(events)[0]
        self.assertEqual(window['endedAt'], 6)
        self.assertFalse(window['rightEvaluationObserved'])
        self.assertFalse(window['mechanismObserved'])
        self.assertFalse(window['localAuthenticationObserved'])
        # Root transitions before SetResult; do not drop the actual Allow.
        events = [event(1, 'Broker', 'phase=authorizing stopReason=none'),
                  event(2, 'Broker', 'phase=unlocking stopReason=none'),
                  event(3, 'AuthorizationMechanism', 'resultDelivered allowed=1 status=0')]
        self.assertTrue(report.authentication_windows(events)[0]['allowObserved'])

    def testRepeatedAuthorizingTransitionDoesNotLeaveAnOpenWindow(self):
        def event(at, message):
            return {'elapsedSeconds': at, 'category': 'Broker', 'message': message}
        windows = report.authentication_windows([
            event(1, 'phase=authorizing stopReason=none'),
            event(1.012, 'phase=authorizing stopReason=none'),
            event(6, 'phase=relocking stopReason=unlockTimeout'),
            event(6.012, 'phase=relocking stopReason=unlockTimeout')])
        self.assertEqual(len(windows), 1)
        self.assertEqual(windows[0]['startedAt'], 1)
        self.assertEqual(windows[0]['endedAt'], 6)

    def testUnavailableStreamRemainsDiagnosticOnly(self):
        trace = report.LiveAuthenticationTrace(0)
        with patch.object(report.subprocess, 'Popen', side_effect=OSError): trace.start()
        events, status = trace.finish()
        self.assertEqual(events, [])
        self.assertEqual(status, 'unavailable')

    def testStreamDiscardsOversizedRawRecordsAndResumes(self):
        # A synthetic pipe exercises framing/lifecycle without invoking OS logs.
        record = self.entry('loginPressed credential=must_not_persist', process='loginwindow')
        code = 'import sys; sys.stdout.write("x"*70000+"\\n"+' + repr(json.dumps(record)+'\n') + '); sys.stdout.flush()'
        child = subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE)
        trace = report.LiveAuthenticationTrace(0, max_seconds=1)
        with patch.object(report.subprocess, 'Popen', return_value=child): trace.start()
        trace.thread.join(timeout=2)
        events, status = trace.finish()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['message'], 'localSubmitObserved')
        self.assertNotIn('must_not_persist', str(events))
        self.assertEqual(status, 'ended')


if __name__ == "__main__": unittest.main()
