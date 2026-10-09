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
import re
import subprocess
import sys
import tempfile
import zipfile

import candidate
from device_profile import check, decode, REQUIRED

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
    signature = subprocess.run(['codesign', '--display', '--verbose=4', str(app)], check=True, capture_output=True, text=True)
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


def validate_distribution(profile, entitlements, team, now=None):
    """Check exported profile/capabilities; this does not claim Apple acceptance."""
    granted = profile.get('Entitlements', {})
    app_id = f'{team}.dev.halopad.HaloPad'
    if (profile.get('TeamIdentifier') != [team]
            or granted.get('application-identifier') != app_id
            or granted.get('com.apple.developer.team-identifier') != team
            or entitlements.get('application-identifier') != app_id
            or entitlements.get('com.apple.developer.team-identifier') != team):
        raise ValueError('distribution profile/signature App ID or team differs')
    if (profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices')
            or granted.get('get-task-allow') is not False
            or granted.get('beta-reports-active') is not True
            or entitlements.get('beta-reports-active') is not True
            or entitlements.get('get-task-allow', False) is not False):
        raise ValueError('export must use an App Store profile, not development, ad hoc or enterprise')
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime.datetime) or expiry <= (now or datetime.datetime.now(datetime.timezone.utc)).replace(tzinfo=None):
        raise ValueError('distribution profile is expired or has no expiration date')
    for key in REQUIRED:
        if granted.get(key) is not True or entitlements.get(key) is not True:
            raise ValueError(f'distribution profile and signature must both retain {key}')


def verify_export(result, directory, team, *, require_notices=False):
    ipas = list(directory.glob('*.ipa'))
    if len(ipas) != 1:
        raise ValueError('expected exactly one exported IPA')
    ipa = ipas[0]
    checked = candidate.audit(ipa, 'ios', result['engine'], result['version'], result['build'],
                              allow_profile=True, require_notices=require_notices)
    with tempfile.TemporaryDirectory(prefix='halopad-export-check-') as folder:
        app = extract_ipa.extract(ipa, Path(folder) / 'input')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', '-R=anchor apple generic', str(app)],
                       check=True, capture_output=True)
        entitlements = plistlib.loads(subprocess.check_output(
            ['codesign', '--display', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
        profile = decode(app / 'embedded.mobileprovision')
        validate_distribution(profile, entitlements, team)
    if candidate.digest(ipa) != checked['sha256']:
        raise ValueError('exported IPA changed during verification')
    proof = {'artifact': checked, 'team': team, 'profile_uuid': profile.get('UUID'),
             'profile_expires': profile['ExpirationDate'].isoformat(),
             'memory_entitlements': list(REQUIRED), 'uploaded': False,
             'apple_acceptance': False, 'consumer_upgrade': False}
    candidate.write_json(directory / 'export-proof.json', proof)
    return proof


def api_auth(path=None, key_id=None, issuer=None):
    """Use an explicit team API key on CI; never fall back after partial setup."""
    if path is None and key_id is None and issuer is None:
        return []
    if (path is None or not re.fullmatch(r'[A-Z0-9]{10}', key_id or '')
            or not re.fullmatch(r'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', issuer or '')
            or not Path(path).is_file()):
        raise ValueError('provide a complete App Store Connect team API key, key ID and issuer ID')
    return ['-authenticationKeyPath', str(Path(path).resolve()),
            '-authenticationKeyID', key_id, '-authenticationKeyIssuerID', issuer]


def export(result, out, profile, identity, auth=(), *, require_notices=False):
    archive, options = prepare(result, out, profile, identity)
    subprocess.run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
                    '-exportPath', str(out / 'export'), '-exportOptionsPlist', str(options),
                    '-allowProvisioningUpdates', *auth], check=True)
    return verify_export(result, out / 'export', plistlib.loads(options.read_bytes())['teamID'],
                         require_notices=require_notices)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--export', action='store_true', help='use the saved Xcode account for local distribution export')
    parser.add_argument('--api-key-path', type=Path)
    parser.add_argument('--api-key-id')
    parser.add_argument('--api-issuer')
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(candidate.ROOT / 'generated'):
            raise ValueError('signed archives must stay under ignored generated/')
        auth = api_auth(args.api_key_path, args.api_key_id, args.api_issuer)
        result = json.loads(args.candidate.read_text())
        if args.export:
            export(result, out, args.profile.resolve(), args.identity, auth)
        else:
            prepare(result, out, args.profile.resolve(), args.identity)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Archive/export stopped: {error}\n')
    print(f'Prepared in {out}; nothing uploaded or submitted.')


if __name__ == '__main__':
    main()
