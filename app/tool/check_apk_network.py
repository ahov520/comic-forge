"""Verify the network capabilities of the APK that will be distributed."""

import argparse
import subprocess
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    parser.add_argument("--apkanalyzer", default="apkanalyzer")
    args = parser.parse_args()
    result = subprocess.run(
        [args.apkanalyzer, "manifest", "print", args.apk],
        check=True,
        capture_output=True,
        text=True,
    )
    manifest = ET.fromstring(result.stdout)
    android = "{http://schemas.android.com/apk/res/android}"
    errors = []
    if not any(
        permission.get(android + "name") == "android.permission.INTERNET"
        and permission.get(android + "maxSdkVersion") is None
        for permission in manifest.findall("uses-permission")
    ):
        errors.append("release APK is missing unrestricted INTERNET permission")
    application = manifest.find("application")
    if application is None or application.get(android + "usesCleartextTraffic") != "true":
        errors.append("release APK must allow the built-in HTTP sources")
    if errors:
        raise SystemExit("\n".join(errors))
    print("APK network check passed: INTERNET permission and HTTP sources enabled")


if __name__ == "__main__":
    main()
