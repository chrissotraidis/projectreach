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
import app_channel
import draft_release as draft
import update_source

FILES = ('HaloPad.ipa', 'HaloPad-Mac.zip', 'icon.png', 'halopad-update.json', 'altstore.json', 'SHA256SUMS')


def assets(release):
    result = {a['name']: a for a in release['assets']}
    if len(result) != len(release['assets']) or set(result) - set(FILES):
        raise ValueError('release has duplicate or unexpected assets; nothing overwritten')
    return result


version_key = app_channel.version_key


def require_newer(result, releases):
    app_channel.require_forward(result, app_channel.published_record(releases))


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
        require_newer(result, draft.api(draft.API + '?per_page=100', pages=True))
        # Every package and both feeds exist and have been downloaded/verified.
        draft.api(endpoint, 'PATCH', {'draft': False, 'prerelease': False, 'make_latest': 'true'})
        release = read_release()
        if release['draft'] or release['prerelease'] or draft.api(draft.API + '/latest')['id'] != release['id']:
            raise ValueError('publication/latest state is not confirmed; inspect before retrying')
    channel_commit = app_channel.advance(out) if publish else None
    proof = {'channel_commit': channel_commit, 'tag': tag, 'release_id': release['id'], 'published': not release['draft'],
             'assets': hashes, 'apple_services_used': False, 'consumer_upgrade': False}
    candidate.write_json(out / 'publication.json', proof)
    return proof


def completed(tag, commit, *, publish):
    """Cheap Ubuntu preflight: verified delivery avoids another Mac runner."""
    delivery_tag = tag.replace('halopad-candidate-', 'halopad-', 1)
    releases = draft.api(draft.API + '?per_page=100', pages=True)
    matches = [r for r in releases if r['tag_name'] == delivery_tag]
    if not matches:
        return False
    if len(matches) != 1 or matches[0]['target_commitish'] != commit:
        raise ValueError('delivery release identity differs')
    release = matches[0]
    remote = assets(release)
    if set(remote) != set(FILES) or any(a['state'] != 'uploaded' for a in remote.values()):
        return False
    sums = draft.asset_bytes(remote['SHA256SUMS'])
    if remote['SHA256SUMS'].get('digest') != 'sha256:' + hashlib.sha256(sums).hexdigest():
        return False
    expected = {}
    for line in sums.decode().splitlines():
        sha, name = line.split('  ', 1)
        if name in expected or not re.fullmatch(r'[0-9a-f]{64}', sha):
            raise ValueError('invalid published checksums')
        expected[name] = sha
    if set(expected) != set(FILES) - {'SHA256SUMS'}:
        raise ValueError('incomplete published checksums')
    if any(remote[name].get('digest') != 'sha256:' + sha for name, sha in expected.items()):
        return False
    feed = json.loads(draft.asset_bytes(remote['altstore.json']))
    if feed['sourceURL'] != app_channel.BASE + '/altstore.json':
        return False
    if not publish:
        return True
    if release['draft'] or release['prerelease']:
        return False
    _, channel = app_channel.snapshot()
    if not channel:
        return False
    current = json.loads(channel['halopad-update.json'])
    record = json.loads(draft.asset_bytes(remote['halopad-update.json']))
    if current == record:
        return channel['altstore.json'].encode() == draft.asset_bytes(remote['altstore.json'])
    if version_key(current['version'], current['build']) < version_key(record['version'], record['build']):
        return False  # Public assets exist, but the feed commit still needs retrying.
    app_channel.require_forward(current, record)
    return True  # This exact public package has already been superseded.


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
