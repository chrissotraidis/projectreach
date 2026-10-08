#!/usr/bin/env python3
"""Prepare an audited candidate for Xcode distribution export using an existing account.

Works on a private copy. --export lets Xcode provision and sign for App Store
Connect, but exports locally only: it never uploads or submits for review.
"""
import argparse
import datetime
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile

import candidate
from device_profile import check

spec = importlib.util.spec_from_file_location('extract_ipa', candidate.ROOT / 'scripts/extract-ipa.py')
extract_ipa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract_ipa)


def prepare(result, out, profile, identity):
    if result.get('status') != 'built-awaiting-acceptance':
        raise ValueError('candidate has not passed its build checks')
    ipa = Path(result['artifacts']['ios']['path'])
    if candidate.digest(ipa) != result['artifacts']['ios']['sha256']:
        raise ValueError('candidate IPA changed after its audit')
    candidate.audit(ipa, 'ios', result['engine'], result['version'], result['build'])
    with zipfile.ZipFile(ipa) as package:
        info = plistlib.loads(package.read('Payload/HaloPad.app/Info.plist'))
    if info.get('DTPlatformName') != 'iphoneos':
        raise ValueError('rebuild the candidate with iPhoneOS platform metadata before exporting')
    granted = check(profile, info['CFBundleIdentifier'], identity)
    team = granted['com.apple.developer.team-identifier']
    out.mkdir(parents=True, exist_ok=False)
    extracted = extract_ipa.extract(ipa, out / 'input')
    archive = out / 'HaloPad.xcarchive'
    app = archive / 'Products/Applications/HaloPad.app'
    app.parent.mkdir(parents=True)
    extracted.rename(app)
    subprocess.run([sys.executable, str(candidate.ROOT / 'scripts/sign-app.py'), str(app),
                    '--profile', str(profile), '--identity', identity], check=True)
    signature = subprocess.run(['codesign', '-dv', str(app)], check=True, capture_output=True, text=True)
    authorities = [s.removeprefix('Authority=') for s in signature.stderr.splitlines() if s.startswith('Authority=')]
    if not authorities:
        raise ValueError('archive needs a certificate-backed development signature')
    properties = {k: info[k] for k in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')}
    properties.update(ApplicationPath='Applications/HaloPad.app', SigningIdentity=authorities[0],
                      Team=team, Architectures=['arm64'])
    (archive / 'Info.plist').write_bytes(plistlib.dumps({
        'ArchiveVersion': 2, 'ApplicationProperties': properties, 'Name': 'HaloPad', 'SchemeName': 'HaloPad',
        'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)}))
    options = out / 'ExportOptions.plist'
    options.write_bytes(plistlib.dumps({'method': 'app-store-connect', 'destination': 'export',
        'signingStyle': 'automatic', 'teamID': team, 'manageAppVersionAndBuildNumber': False,
        'uploadSymbols': False, 'generateAppStoreInformation': True}))
    candidate.write_json(out / 'source.json', {'candidate': result, 'uploaded': False})
    if candidate.digest(ipa) != result['artifacts']['ios']['sha256']:
        raise ValueError('source IPA changed during archive preparation')
    return archive, options


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--export', action='store_true', help='use the saved Xcode account for local distribution export')
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(candidate.ROOT / 'generated'):
            raise ValueError('signed archives must stay under ignored generated/')
        archive, options = prepare(json.loads(args.candidate.read_text()), out, args.profile.resolve(), args.identity)
        if args.export:
            subprocess.run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
                            '-exportPath', str(out / 'export'), '-exportOptionsPlist', str(options),
                            '-allowProvisioningUpdates'], check=True)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Archive/export stopped: {error}\n')
    print(f'Prepared in {out}; nothing uploaded or submitted.')


if __name__ == '__main__':
    main()
