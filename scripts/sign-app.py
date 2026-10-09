#!/usr/bin/env python3
"""Sign a prebuilt device HaloPad.app for your own team, on any Mac with Xcode.

The app is built on the Mac that holds the translated game (scripts/build-ios-app.py --iphoneos).
This signs a copy of it with your identity and provisioning profile, requesting the two memory
entitlements Halo needs, so another Mac can install it without the build tree.
Uses only the Python standard library.

Usage: scripts/sign-app.py HaloPad.app --identity "Apple Development: Name (TEAMID)" --profile X.mobileprovision
"""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
from device_profile import check

ENTITLEMENTS = {
    'com.apple.developer.kernel.extended-virtual-addressing': True,
    'com.apple.developer.kernel.increased-memory-limit': True,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('app', type=pathlib.Path)
    ap.add_argument('--identity', required=True)
    ap.add_argument('--profile', type=pathlib.Path, required=True)
    ap.add_argument('--check-only', action='store_true', help='validate app and profile without changing or signing the app')
    a = ap.parse_args()
    app = a.app.resolve()
    pc = (app / 'data' / 'core-identity.json').is_file()
    xbox = all((app / 'data' / 'xbox' / name).is_file()
               for name in ('build.json', 'halo_guest.elf', 'brokers.txt'))
    if not (app / 'Info.plist').is_file() or not (pc or xbox):
        sys.exit(f'{app} is not a HaloPad device build')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        sys.exit(f'{app} is not a device build; use the app built with --iphoneos')
    bundle = info['CFBundleIdentifier']
    try:
        granted = check(a.profile, bundle, a.identity)
    except (ValueError, subprocess.CalledProcessError, plistlib.InvalidFileException) as exc:
        sys.exit(f'profile preflight failed: {exc}')
    if a.check_only:
        print('PASS: device app and signing profile; no files changed')
        return
    entitlements = dict(ENTITLEMENTS)
    entitlements.update({k: granted[k] for k in ('application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow') if k in granted})
    shutil.copy2(a.profile, app / 'embedded.mobileprovision')
    with tempfile.TemporaryDirectory(prefix='halopad-sign-') as folder:
        entitlements_path = pathlib.Path(folder) / 'entitlements.plist'
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(['codesign', '--force', '--sign', a.identity, '--entitlements', str(entitlements_path), '--timestamp=none', str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print('signed', app)


if __name__ == '__main__':
    main()
