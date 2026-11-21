"""Tests for make_source.py. Run with: python -m unittest discover -s scripts"""

import datetime
import json
import os
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_source  # noqa: E402

BUILT_AT = datetime.datetime(2026, 11, 21, 3, 4, 5, tzinfo=datetime.timezone.utc)
INFO = {
    "CFBundleIdentifier": "dev.shortlist.app",
    "CFBundleShortVersionString": "0.0.1",
    "CFBundleVersion": "42",
    "CFBundleDisplayName": "Shortlist",
    "MinimumOSVersion": "17.0",
}


def make(info=None, entitlements=None, channel="test"):
    return make_source.build_source(
        info=INFO if info is None else info,
        entitlements={} if entitlements is None else entitlements,
        channel=channel,
        ipa_size=12345,
        download_url="https://example.invalid/Shortlist.ipa",
        icon_url="https://example.invalid/icon.png",
        built_at=BUILT_AT,
    )


class BuildSourceTests(unittest.TestCase):
    def test_version_entry_matches_info_plist(self):
        version = make()["apps"][0]["versions"][0]

        self.assertEqual(version["version"], "0.0.1")
        self.assertEqual(version["buildVersion"], "42")
        self.assertEqual(version["size"], 12345)
        self.assertEqual(version["minOSVersion"], "17.0")
        self.assertEqual(version["date"], "2026-11-21T03:04:05Z")
        self.assertEqual(version["downloadURL"], "https://example.invalid/Shortlist.ipa")

    def test_app_entry_has_fields_sidestore_requires(self):
        app = make()["apps"][0]

        for key in ("name", "bundleIdentifier", "developerName", "localizedDescription",
                    "iconURL", "versions", "appPermissions"):
            self.assertIn(key, app)
        self.assertEqual(app["bundleIdentifier"], "dev.shortlist.app")
        self.assertNotIn("marketplaceID", app)

    def test_permissions_come_from_the_build(self):
        info = dict(INFO, NSPhotoLibraryUsageDescription="Reads photos to suggest shares.",
                    NSCameraUsageDescription="Not used.", UILaunchScreen={})
        entitlements = {"keychain-access-groups": ["x"], "aps-environment": "development"}

        permissions = make(info=info, entitlements=entitlements)["apps"][0]["appPermissions"]

        self.assertEqual(permissions["entitlements"], ["aps-environment", "keychain-access-groups"])
        self.assertEqual(permissions["privacy"], {
            "NSCameraUsageDescription": "Not used.",
            "NSPhotoLibraryUsageDescription": "Reads photos to suggest shares.",
        })

    def test_empty_permissions(self):
        permissions = make()["apps"][0]["appPermissions"]

        self.assertEqual(permissions, {"entitlements": [], "privacy": {}})

    def test_channels_have_distinct_names(self):
        self.assertNotEqual(make(channel="latest")["name"], make(channel="test")["name"])

    def test_rejects_unknown_channel(self):
        with self.assertRaises(ValueError):
            make(channel="nightly")

    def test_rejects_missing_version(self):
        info = {k: v for k, v in INFO.items() if k != "CFBundleVersion"}
        with self.assertRaises(ValueError):
            make(info=info)

    def test_omits_min_os_when_absent(self):
        info = {k: v for k, v in INFO.items() if k != "MinimumOSVersion"}

        self.assertNotIn("minOSVersion", make(info=info)["apps"][0]["versions"][0])


class CommandLineTests(unittest.TestCase):
    def test_writes_valid_json_from_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            app_dir = os.path.join(tmp, "Shortlist.app")
            os.mkdir(app_dir)
            with open(os.path.join(app_dir, "Info.plist"), "wb") as handle:
                plistlib.dump(INFO, handle, fmt=plistlib.FMT_BINARY)
            entitlements = os.path.join(tmp, "app.entitlements")
            with open(entitlements, "wb") as handle:
                plistlib.dump({}, handle)
            ipa = os.path.join(tmp, "Shortlist.ipa")
            with open(ipa, "wb") as handle:
                handle.write(b"\0" * 2048)
            out = os.path.join(tmp, "source.json")

            make_source.main([
                "--app", app_dir, "--ipa", ipa, "--entitlements", entitlements,
                "--channel", "latest", "--download-url", "https://example.invalid/a.ipa",
                "--icon-url", "https://example.invalid/i.png", "--out", out,
            ])

            with open(out, encoding="utf-8") as handle:
                source = json.load(handle)
        self.assertEqual(source["apps"][0]["versions"][0]["size"], 2048)
        self.assertEqual(source["apps"][0]["versions"][0]["buildVersion"], "42")


if __name__ == "__main__":
    unittest.main()
