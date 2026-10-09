#!/usr/bin/env python3
"""Stage exact candidate packages and update metadata. Never upload or promote."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

import candidate
import app_channel

REPOSITORY = 'https://github.com/chrissotraidis/projectreach'
REQUIRED = {'com.apple.developer.kernel.extended-virtual-addressing',
            'com.apple.developer.kernel.increased-memory-limit'}


def stage(result, out, tag):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,80}', tag):
        raise ValueError('release tag must be a single simple URL component')
    if result.get('status') != 'built-awaiting-acceptance':
        raise ValueError('candidate did not pass its build checks')
    base = f'{REPOSITORY}/releases/download/{tag}'
    version, build = result['version'], result['build']
    candidate.validate(version, build)
    artifacts = {}
    for platform, filename in [('ios', 'HaloPad.ipa'), ('mac', 'HaloPad-Mac.zip')]:
        recorded = result['artifacts'][platform]
        path = Path(recorded['path'])
        if candidate.digest(path) != recorded['sha256']:
            raise ValueError(f'{platform} package changed since candidate audit')
        checked = candidate.audit(path, platform, result['engine'], version, build)
        artifacts[platform] = {k: checked[k] for k in ('sha256', 'size', 'minimum_os', 'network_version')}
        artifacts[platform]['url'] = f'{base}/{filename}'
    ipa = Path(result['artifacts']['ios']['path'])
    with zipfile.ZipFile(ipa) as archive, tempfile.TemporaryDirectory() as folder:
        archive.extractall(folder)  # candidate.audit already rejected unsafe paths/symlinks
        app = Path(folder) / 'Payload/HaloPad.app'
        entitlements = plistlib.loads(subprocess.check_output(
            ['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
        if set(entitlements) != REQUIRED or any(entitlements[k] is not True for k in REQUIRED):
            raise ValueError('unexpected consumer-signing entitlements')
        info = plistlib.loads(archive.read('Payload/HaloPad.app/Info.plist'))
    metadata = {'schema': 1, 'bundle_id': 'dev.halopad.HaloPad', 'version': version,
                'build': build, 'engine': result['engine'], 'artifacts': artifacts}
    feed = {'name': 'HaloPad', 'identifier': 'dev.halopad.source',
            'sourceURL': app_channel.BASE + '/altstore.json',
            'apps': [{'name': 'HaloPad', 'bundleIdentifier': 'dev.halopad.HaloPad',
                      'developerName': 'Chris Sotraidis',
                      'localizedDescription': 'Xbox Halo on Apple devices. Import your own disc once; app updates keep your files.',
                      'iconURL': f'{base}/icon.png',
                      'versions': [{'version': version, 'buildVersion': build,
                                    'date': result.get('started') or datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                    'downloadURL': artifacts['ios']['url'], 'size': artifacts['ios']['size'],
                                    'minOSVersion': artifacts['ios']['minimum_os']}],
                      'appPermissions': {'entitlements': sorted(entitlements),
                                         'privacy': {k: v for k, v in info.items() if k.startswith('NS') and k.endswith('UsageDescription')}}}],
            'news': []}
    # Never replace a previously staged/distributed release directory.
    out.mkdir(parents=True, exist_ok=False)
    for platform, filename in [('ios', 'HaloPad.ipa'), ('mac', 'HaloPad-Mac.zip')]:
        shutil.copyfile(result['artifacts'][platform]['path'], out / filename)
        if candidate.digest(out / filename) != artifacts[platform]['sha256']:
            raise ValueError('staged package checksum differs')
    shutil.copyfile(candidate.ROOT / 'assets/Assets.xcassets/AppIcon.appiconset/AppIcon.png', out / 'icon.png')
    candidate.write_json(out / 'halopad-update.json', metadata)
    candidate.write_json(out / 'altstore.json', feed)
    candidate.write_json(out / 'review.json', {'candidate': result, 'published': False,
        'note': 'Private staging only. Acceptance and publication must be established separately.'})
    (out / 'SHA256SUMS').write_text(''.join(f'{candidate.digest(p)}  {p.name}\n'
        for p in sorted(out.iterdir()) if p.is_file() and p.name != 'review.json'))
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(candidate.ROOT / 'generated'):
            raise ValueError('private staging must stay under ignored generated/')
        stage(json.loads(args.candidate.read_text()), out, args.tag)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Update source staging stopped: {error}\n')
    print(f'Staged for review in {out}; nothing uploaded or published.')


if __name__ == '__main__':
    main()
