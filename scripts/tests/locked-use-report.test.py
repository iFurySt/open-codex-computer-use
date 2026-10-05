"""Report privacy filters; no desktop, daemon, lock or authentication calls."""
import importlib.util
from pathlib import Path
import unittest

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


if __name__ == "__main__": unittest.main()
