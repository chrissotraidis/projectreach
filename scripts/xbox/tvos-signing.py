#!/usr/bin/env python3
"""Choose how an Apple TV build is signed, from what Xcode already has.

A tvOS app installs on an Apple TV only with a development profile that
names the device. Xcode makes one, for any Apple account (a free one too),
the first time it runs an app with that bundle identifier on the Apple TV;
docs/INSTALL-APPLE-TV.md has the steps. This finds such a profile and the
signing identity in the keychain whose certificate it lists, so a player
does not have to pass either.

  tvos-signing.py --entitlements OUT [--profile FILE] [--team TEAM] [--bundle-id ID]

Prints three tab-separated fields: the bundle identifier, the signing
identity's SHA-1 and the profile's path. Writes OUT, the entitlements the
app is signed with: those the profile grants that the game uses (the
increased memory limit is never granted on tvOS; extended virtual addressing
is kept when granted, but the game does not need it). Exits 1 with an
explanation when nothing fits.
"""
import argparse
import datetime
import hashlib
import pathlib
import plistlib
import re
import subprocess
import sys

PROFILE_FOLDERS = [
    pathlib.Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles',
    pathlib.Path.home() / 'Library/MobileDevice/Provisioning Profiles',
]
KEPT = ('application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow',
        'com.apple.developer.kernel.extended-virtual-addressing')


def decode(path):
    """A profile's contents (the signed plist inside it), or None."""
    try:
        data = subprocess.run(['security', 'cms', '-D', '-i', str(path)], check=True,
                              capture_output=True).stdout
        return plistlib.loads(data)
    except (subprocess.CalledProcessError, plistlib.InvalidFileException, ValueError):
        return None


def bundle_of(profile):
    """(team, bundle identifier) a profile is for; the identifier may be a wildcard."""
    app_id = profile.get('Entitlements', {}).get('application-identifier', '')
    team, _, bundle = app_id.partition('.')
    return team, bundle


def usable(profile, team, bundle_id, now):
    if 'tvOS' not in profile.get('Platform', []) or profile.get('ExpirationDate', now) <= now:
        return False
    if not profile.get('Entitlements', {}).get('get-task-allow'):
        return False                       # a development profile: installs from Xcode's tools
    found_team, found_bundle = bundle_of(profile)
    if '*' in found_bundle:
        return False                       # one app, so the build has one bundle identifier
    return (not team or team == found_team) and (not bundle_id or bundle_id == found_bundle)


def identities():
    """SHA-1 -> name of the keychain's valid code-signing identities."""
    listing = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'],
                             capture_output=True, text=True).stdout
    return {m.group(1): m.group(2) for m in re.finditer(r'\)\s+([0-9A-F]{40})\s+"([^"]+)"', listing)}


def choose(profile_path, team, bundle_id):
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if profile_path:
        candidates = [(pathlib.Path(profile_path), decode(profile_path))]
        if not candidates[0][1]:
            sys.exit('tvos-signing: %s is not a provisioning profile' % profile_path)
        if not usable(candidates[0][1], team, bundle_id, now):
            sys.exit('tvos-signing: %s is not an unexpired tvOS development profile for one app'
                     '%s' % (profile_path, ' matching --team/--bundle-id' if team or bundle_id else ''))
    else:
        candidates = []
        for folder in PROFILE_FOLDERS:
            for path in sorted(folder.glob('*.mobileprovision')) if folder.is_dir() else []:
                profile = decode(path)
                if profile and usable(profile, team, bundle_id, now):
                    candidates.append((path, profile))
    known = identities()
    fitting = []
    for path, profile in candidates:
        signers = [hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])]
        signer = next((sha for sha in signers if sha in known), None)
        if signer:
            fitting.append((profile.get('CreationDate', now), path, profile, signer))
    if not fitting:
        sys.exit('tvos-signing: no tvOS development profile with a signing identity in this keychain%s.\n'
                 'Make one with Xcode first: docs/INSTALL-APPLE-TV.md, "Signing".'
                 % (' for ' + ' '.join(filter(None, [team, bundle_id])) if team or bundle_id else ''))
    fitting.sort(key=lambda item: item[0], reverse=True)
    bundles = {bundle_of(item[2]) for item in fitting}
    if len(bundles) > 1 and not (team and bundle_id):
        sys.exit('tvos-signing: several tvOS profiles fit; choose one with --bundle-id (and --team):\n' +
                 '\n'.join('  --team %s --bundle-id %s' % pair for pair in sorted(bundles)))
    return fitting[0][1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--entitlements', required=True)
    parser.add_argument('--profile')
    parser.add_argument('--team')
    parser.add_argument('--bundle-id')
    options = parser.parse_args()
    path, profile, signer = choose(options.profile, options.team, options.bundle_id)
    granted = profile['Entitlements']
    plistlib.dump({key: granted[key] for key in KEPT if key in granted}, open(options.entitlements, 'wb'))
    print('%s\t%s\t%s' % (bundle_of(profile)[1], signer, path))


if __name__ == '__main__':
    main()
