#!/usr/bin/env python3
"""Retain/retrieve audited candidates in unpublished GitHub releases. Never publish."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

import candidate

REPO = 'chrissotraidis/projectreach'
API = f'repos/{REPO}/releases'
ASSET = 'HaloPad-candidate.zip'
PACKAGES = {'ios': 'HaloPad.ipa', 'mac': 'HaloPad-Mac.zip'}
MEMBERS = {'candidate.json', *PACKAGES.values()}


def api(path, method='GET', body=None, pages=False):
    args = ['gh', 'api', path, '--method', method]
    if body is not None:
        args += ['--input', '-']
    if pages:
        args += ['--paginate', '--slurp']
    output = subprocess.check_output(args, input=json.dumps(body) if body is not None else None, text=True)
    result = json.loads(output) if output.strip() else None
    return [item for page in result for item in page] if pages else result


def find_draft(tag):
    matches = [r for r in api(API + '?per_page=100', pages=True) if r['tag_name'] == tag]
    if len(matches) > 1 or (matches and matches[0]['draft'] is not True):
        raise ValueError('tag is already published or ambiguous; will not modify it')
    return matches[0] if matches else None


def check_draft(release_id):
    result = api(f'{API}/{release_id}')
    if result['draft'] is not True:
        raise ValueError('release is no longer private; stopped')
    return result


def asset_bytes(asset):
    # Use the fixed repository API, not an arbitrary URL from a manifest.
    return subprocess.check_output(['gh', 'api', f'{API}/assets/{int(asset["id"])}',
                                    '-H', 'Accept: application/octet-stream'])


def audit_result(result):
    if result.get('status') != 'built-awaiting-acceptance':
        raise ValueError('candidate has not passed build checks')
    for platform in PACKAGES:
        recorded = result['artifacts'][platform]
        checked = candidate.audit(Path(recorded['path']), platform, result['engine'], result['version'], result['build'])
        if any(checked[k] != recorded[k] for k in ('sha256', 'size', 'network_version', 'minimum_os')):
            raise ValueError(f'{platform} package changed after candidate audit')


def retain(result, out):
    audit_result(result)
    candidate.validate(result['version'], result['build'])
    commit = result['source']['commit']
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('missing exact source commit')
    # A dirty-build record must not be labelled as a reproducible source commit.
    identity = candidate.source_identity()
    if identity['commit'] != commit or identity['tree_sha256'] != result['source']['tree_sha256']:
        raise ValueError('checkout differs from candidate source; retain from its exact source checkout')
    out.mkdir(parents=True, exist_ok=False)
    record = copy.deepcopy(result)
    record.pop('run', None)
    for platform, name in PACKAGES.items():
        record['artifacts'][platform]['path'] = name
    bundle = out / ASSET
    with zipfile.ZipFile(bundle, 'w', compression=zipfile.ZIP_STORED) as archive:
        archive.writestr(zipfile.ZipInfo('candidate.json'), json.dumps(record, sort_keys=True, indent=2))
        for platform, name in PACKAGES.items():
            # Fixed metadata makes retries byte-identical, independent of mtime.
            archive.writestr(zipfile.ZipInfo(name), Path(result['artifacts'][platform]['path']).read_bytes())
    tag = f'halopad-candidate-{result["version"]}-{result["build"]}'
    release = find_draft(tag)
    if release is None:
        release = api(API, 'POST', {'tag_name': tag, 'target_commitish': commit,
            'name': f'HaloPad {result["version"]} ({result["build"]}) private candidate',
            'body': 'Unpublished build handoff. Build audits passed; gameplay, consumer delivery and publication are not established.',
            'draft': True, 'prerelease': True})
    release = check_draft(release['id'])
    if release['target_commitish'] != commit:
        raise ValueError('existing draft has a different source commit')
    assets = release['assets']
    if assets:
        if len(assets) != 1 or assets[0]['name'] != ASSET or asset_bytes(assets[0]) != bundle.read_bytes():
            raise ValueError('existing draft content differs; nothing overwritten')
    else:
        subprocess.run(['gh', 'release', 'upload', tag, str(bundle), '--repo', REPO], check=True)
    release = check_draft(release['id'])
    if (len(release['assets']) != 1 or release['assets'][0]['name'] != ASSET
            or hashlib.sha256(asset_bytes(release['assets'][0])).hexdigest() != candidate.digest(bundle)):
        raise ValueError('retained candidate readback differs')
    return {'tag': tag, 'release_id': release['id'], 'sha256': candidate.digest(bundle), 'published': False}


def retrieve(tag, out):
    if not re.fullmatch(r'halopad-candidate-[0-9.]+-[0-9]+', tag):
        raise ValueError('invalid candidate tag')
    release = find_draft(tag)
    if release is None or len(release['assets']) != 1 or release['assets'][0]['name'] != ASSET:
        raise ValueError('no complete private candidate at this tag')
    out.mkdir(parents=True, exist_ok=False)
    bundle = out / ASSET
    bundle.write_bytes(asset_bytes(release['assets'][0]))
    with zipfile.ZipFile(bundle) as archive:
        if set(archive.namelist()) != MEMBERS or len(archive.namelist()) != len(MEMBERS):
            raise ValueError('unexpected or duplicate candidate archive members')
        record = json.loads(archive.read('candidate.json'))
        for platform, name in PACKAGES.items():
            if record['artifacts'][platform]['path'] != name:
                raise ValueError('unexpected candidate package path')
            (out / name).write_bytes(archive.read(name))
            record['artifacts'][platform]['path'] = str((out / name).resolve())
    if tag != f'halopad-candidate-{record["version"]}-{record["build"]}' or record['source']['commit'] != release['target_commitish']:
        raise ValueError('downloaded candidate identity differs from draft')
    audit_result(record)
    check_draft(release['id'])
    candidate.write_json(out / 'result.json', record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument('--candidate', type=Path)
    choice.add_argument('--download', metavar='TAG')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(candidate.ROOT / 'generated'):
            raise ValueError('private candidates must stay under ignored generated/')
        result = retain(json.loads(args.candidate.read_text()), out) if args.candidate else retrieve(args.download, out)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Private candidate handoff stopped: {error}\n')


if __name__ == '__main__':
    main()
