#!/usr/bin/env python3
"""Prepare a private IPA release; --publish explicitly makes verified assets public."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

import candidate
import draft_release as draft
import update_source

FILES = ('HaloPad.ipa', 'HaloPad-Mac.zip', 'icon.png', 'halopad-update.json', 'altstore.json', 'SHA256SUMS')


def assets(release):
    result = {a['name']: a for a in release['assets']}
    if len(result) != len(release['assets']) or set(result) - set(FILES):
        raise ValueError('release has duplicate or unexpected assets; nothing overwritten')
    return result


def version_key(version, build):
    candidate.validate(version, str(build))
    return tuple(map(int, version.split('.'))), int(build)


def require_newer(result, releases):
    if not any(not r['draft'] and not r['prerelease'] for r in releases):
        return
    latest = draft.api(draft.API + '/latest')
    metadata = [a for a in latest['assets'] if a['name'] == 'halopad-update.json']
    if len(metadata) == 1:
        record = json.loads(draft.asset_bytes(metadata[0]))
        if record['bundle_id'] != 'dev.halopad.HaloPad':
            raise ValueError('latest update metadata belongs to another app')
        previous = version_key(record['version'], record['build'])
    elif not metadata and re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', latest['tag_name']):
        # Source-only historical releases have no app build number.
        previous = (tuple(map(int, latest['tag_name'][1:].split('.'))), 0)
    else:
        raise ValueError('cannot establish latest release identity; publication stopped')
    if version_key(result['version'], result['build']) <= previous:
        raise ValueError('candidate is not newer than the current public app; publication stopped')


def deliver(result, out, *, publish=False):
    commit = result['source']['commit']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('missing exact candidate source commit')
    # Stable dates make a retry reproduce the original feed bytes.
    if datetime.datetime.fromisoformat(result['started']).tzinfo is None:
        raise ValueError('candidate start time must include its timezone')
    for platform in ('ios', 'mac'):
        item = result['artifacts'][platform]
        candidate.audit(Path(item['path']), platform, result['engine'], result['version'],
                        result['build'], require_notices=True)
    tag = f'halopad-{result["version"]}-{result["build"]}'
    update_source.stage(result, out, tag)
    hashes = {name: candidate.digest(out / name) for name in FILES}
    releases = draft.api(draft.API + '?per_page=100', pages=True)
    matches = [r for r in releases if r['tag_name'] == tag]
    if len(matches) > 1:
        raise ValueError('release tag is ambiguous')
    release = matches[0] if matches else draft.api(draft.API, 'POST', {
        'tag_name': tag, 'target_commitish': commit, 'draft': True, 'prerelease': False,
        'name': f'HaloPad {result["version"]} ({result["build"]})',
        'body': f'Xbox-only HaloPad, OpenCE {result["engine"]["release"]}. Import your own Xbox disc. '
                'The IPA requires signing with a profile granting both memory entitlements. '
                'Install over the existing app with the same signing identity to retain imported files. '
                'This build has passed package checks; those checks do not establish gameplay or consumer-upgrade acceptance.'})
    endpoint = f'{draft.API}/{release["id"]}'

    def read_release():
        current = draft.api(endpoint)
        if current['target_commitish'] != commit or current['tag_name'] != tag:
            raise ValueError('release source identity differs; nothing overwritten')
        assets(current)
        return current

    for name in FILES:
        release = read_release()
        remote = assets(release).get(name)
        if remote is None:
            if not release['draft']:
                raise ValueError('published release is incomplete; nothing modified')
            subprocess.run(['gh', 'release', 'upload', tag, str(out / name), '--repo', draft.REPO], check=True)
            remote = assets(read_release()).get(name)
        if (remote is None or remote['state'] != 'uploaded'
                or hashlib.sha256(draft.asset_bytes(remote)).hexdigest() != hashes[name]):
            raise ValueError(f'{name} readback differs; publication stopped without overwriting')
    release = read_release()
    if publish and release['draft']:
        require_newer(result, releases)
        # Every package and both feeds exist and have been downloaded/verified.
        draft.api(endpoint, 'PATCH', {'draft': False, 'prerelease': False, 'make_latest': 'true'})
        release = read_release()
        if release['draft'] or release['prerelease'] or draft.api(draft.API + '/latest')['id'] != release['id']:
            raise ValueError('publication/latest state is not confirmed; inspect before retrying')
    proof = {'tag': tag, 'release_id': release['id'], 'published': not release['draft'],
             'assets': hashes, 'apple_services_used': False, 'consumer_upgrade': False}
    candidate.write_json(out / 'publication.json', proof)
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--publish', action='store_true', help='make the checked app packages public and latest')
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(candidate.ROOT / 'generated'):
            raise ValueError('release staging must stay under ignored generated/')
        print(json.dumps(deliver(json.loads(args.candidate.read_text()), out, publish=args.publish), indent=2))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f'IPA release stopped; existing packages are preserved: {error}\n')


if __name__ == '__main__':
    main()
