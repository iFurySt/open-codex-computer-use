#!/usr/bin/env python3
"""Prepare narrowly scoped Keychain entitlements from a macOS profile.

OS code-signature/profile validation remains authoritative at launch. This
build-time check refuses mismatched, expired and debugging-enabled profiles.
It never copies private certificate keys or unrelated profile entitlements.
"""
import argparse
import datetime
import pathlib
import plistlib
import subprocess


def entitlements(profile, bundle_id, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiry = profile.get("ExpirationDate")
    claims = profile.get("Entitlements", {})
    team = claims.get("com.apple.developer.team-identifier", "")
    app_id = claims.get("com.apple.application-identifier", "")
    if not isinstance(expiry, datetime.datetime):
        raise ValueError("Profile expiry is missing")
    expiry = expiry.replace(tzinfo=datetime.timezone.utc) if expiry.tzinfo is None else expiry
    if ("OSX" not in profile.get("Platform", []) or expiry <= now
            or claims.get("get-task-allow", False)
            or claims.get("com.apple.security.get-task-allow", False)
            or len(team) != 10 or not team.isascii() or not team.isalnum()
            or team not in profile.get("TeamIdentifier", [])
            or app_id not in (team + "." + bundle_id, team + ".*")):
        raise ValueError("Use a valid non-debug macOS profile matching this bundle")
    exact = team + "." + bundle_id
    groups = claims.get("keychain-access-groups", [])
    if exact not in groups and team + ".*" not in groups:
        raise ValueError("Profile does not authorize the app's own Keychain group")
    return {"com.apple.application-identifier": exact,
            "com.apple.developer.team-identifier": team,
            "keychain-access-groups": [exact]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile")
    parser.add_argument("bundle_id")
    parser.add_argument("output")
    args = parser.parse_args()
    decoded = subprocess.run(["/usr/bin/security", "cms", "-D", "-i", args.profile],
                             capture_output=True, check=True).stdout
    result = entitlements(plistlib.loads(decoded), args.bundle_id)
    pathlib.Path(args.output).write_bytes(plistlib.dumps(result))


if __name__ == "__main__":
    main()
