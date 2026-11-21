"""Write a SideStore/AltStore source file describing one build of the app.

Adding a source to SideStore once means later builds appear there as updates.
The format follows AltStore's "Make a Source" guide, which SideStore supports.

Usage:
  python3 scripts/make_source.py --app build/Payload/Shortlist.app \
      --ipa build/Shortlist.ipa --entitlements app/Shortlist.entitlements \
      --channel test --download-url https://.../Shortlist.ipa \
      --icon-url https://.../icon.png --out build/source.json
"""

import argparse
import datetime
import json
import os
import plistlib
import sys

CHANNEL_TEXT = {
    "latest": ("Shortlist", "Builds of the main branch."),
    "test": ("Shortlist test builds", "Work-in-progress builds from any branch. May be unstable."),
}


def build_source(info, entitlements, channel, ipa_size, download_url, icon_url, built_at):
    if channel not in CHANNEL_TEXT:
        raise ValueError(f"unknown channel {channel!r}; expected one of {sorted(CHANNEL_TEXT)}")
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
        if not info.get(key):
            raise ValueError(f"Info.plist is missing {key}")

    source_name, source_description = CHANNEL_TEXT[channel]
    # SideStore refuses an app whose listed permissions differ from the downloaded file,
    # so both lists are read from the build rather than written by hand.
    privacy = {
        key: value
        for key, value in sorted(info.items())
        if key.startswith("NS") and key.endswith("UsageDescription")
    }

    version = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": str(info["CFBundleVersion"]),
        "date": built_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": f"{channel} build {info['CFBundleVersion']}",
        "downloadURL": download_url,
        "size": ipa_size,
    }
    if info.get("MinimumOSVersion"):
        version["minOSVersion"] = info["MinimumOSVersion"]

    app = {
        "name": info.get("CFBundleDisplayName") or info.get("CFBundleName") or "Shortlist",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "Shortlist",
        "localizedDescription": "Suggests which photos to share and uploads the chosen ones.",
        "iconURL": icon_url,
        "category": "photo-video",
        "appPermissions": {
            "entitlements": sorted(entitlements.keys()),
            "privacy": privacy,
        },
        "versions": [version],
    }

    # No marketplaceID: SideStore treats a source that has one as notarized and rejects it.
    return {
        "name": source_name,
        "description": source_description,
        "iconURL": icon_url,
        "apps": [app],
        "news": [],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", required=True, help="path to the built .app folder")
    parser.add_argument("--ipa", required=True, help="path to the packaged .ipa")
    parser.add_argument("--entitlements", required=True, help="path to the entitlements plist")
    parser.add_argument("--channel", required=True, choices=sorted(CHANNEL_TEXT))
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--icon-url", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    with open(os.path.join(args.app, "Info.plist"), "rb") as handle:
        info = plistlib.load(handle)
    with open(args.entitlements, "rb") as handle:
        entitlements = plistlib.load(handle)

    source = build_source(
        info=info,
        entitlements=entitlements,
        channel=args.channel,
        ipa_size=os.path.getsize(args.ipa),
        download_url=args.download_url,
        icon_url=args.icon_url,
        built_at=datetime.datetime.now(datetime.timezone.utc),
    )
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(source, handle, indent=2)
        handle.write("\n")
    print(json.dumps(source["apps"][0]["versions"][0], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
