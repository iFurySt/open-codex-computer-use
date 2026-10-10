import datetime
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("profile_check", pathlib.Path(__file__).with_name("prepare-macos-keychain-profile.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProfileTests(unittest.TestCase):
    def profile(self):
        return {"Platform": ["OSX"], "TeamIdentifier": ["TESTTEAM12"],
                "ExpirationDate": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
                "Entitlements": {"com.apple.application-identifier": "TESTTEAM12.dev.example.ocu",
                                 "com.apple.developer.team-identifier": "TESTTEAM12",
                                 "keychain-access-groups": ["TESTTEAM12.*", "unrelated.group"]}}

    def test_scopes_claims_to_own_group(self):
        result = module.entitlements(self.profile(), "dev.example.ocu")
        self.assertEqual(result["keychain-access-groups"], ["TESTTEAM12.dev.example.ocu"])
        self.assertEqual(len(result), 3)

    def test_rejects_wrong_app_and_debug_and_expiry(self):
        for change in ("app", "debug", "expiry", "platform", "team", "group"):
            profile = self.profile()
            if change == "app": profile["Entitlements"]["com.apple.application-identifier"] = "TESTTEAM12.other"
            if change == "debug": profile["Entitlements"]["get-task-allow"] = True
            if change == "expiry": profile["ExpirationDate"] = datetime.datetime(2000, 1, 1)
            if change == "platform": profile["Platform"] = ["iOS"]
            if change == "team": profile["TeamIdentifier"] = ["OTHERTEAM1"]
            if change == "group": profile["Entitlements"]["keychain-access-groups"] = ["unrelated.group"]
            with self.subTest(change=change), self.assertRaises(ValueError):
                module.entitlements(profile, "dev.example.ocu")


if __name__ == "__main__":
    unittest.main()
