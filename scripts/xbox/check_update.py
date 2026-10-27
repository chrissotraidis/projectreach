#!/usr/bin/env python3
"""Resolve once; prioritize protocol changes and reuse retained private candidates."""
import argparse
import json
import os
from pathlib import Path
import subprocess

import candidate
import draft_release as draft
import network_policy
import release


def retained_candidate(selected, source_hash, version, releases):
    matches = []
    for item in releases:
        assets = {a['name']: a for a in item.get('assets', [])}
        if draft.ASSET not in assets or draft.RECEIPT not in assets:
            continue
        archive, receipt = assets[draft.ASSET], assets[draft.RECEIPT]
        if (archive.get('state') != 'uploaded' or receipt.get('state') != 'uploaded'
                or not 0 < receipt.get('size', 0) < 65536):
            continue
        try:
            data = json.loads(draft.asset_bytes(receipt))
            record = data['candidate']
            candidate.validate(record['version'], record['build'])
            if (item['tag_name'] != f'halopad-candidate-{record["version"]}-{record["build"]}'
                    or item['target_commitish'] != record['source']['commit']):
                continue
            if (data['schema'] == 1 and archive.get('digest') == 'sha256:' + data['archive_sha256']
                    and record['status'] == 'built-awaiting-acceptance' and record['version'] == version
                    and record['source']['tree_sha256'] == source_hash
                    and all(record['engine'][key] == selected[key] for key in ('revision', 'release'))):
                matches.append(record)
        except (ValueError, KeyError, TypeError):
            continue  # Incomplete/edited receipts never suppress a needed build.
    return max(matches, key=lambda r: int(r["build"]), default=None)


def retained(selected, source_hash, version, releases):
    return retained_candidate(selected, source_hash, version, releases) is not None


def select(channel, version, *, skip_retained=False, network_change_only=False):
    if network_change_only and channel != 'upstream':
        raise ValueError('--network-change-only requires --channel upstream')
    candidate.validate(version, '1')
    current = release.read_record(release.BUNDLED)
    selected = (release.resolve(json.loads(release.LOCK.read_text()))
                if channel == 'upstream' else current)
    result = {'build': True, 'record': selected, 'candidate': '', 'commit': '',
              'reason': 'new-candidate'}
    if network_change_only:
        result['baseline'] = current
        if selected['revision'] == current['revision']:
            return {**result, 'build': False, 'reason': 'current-engine'}
        # Read both headers at the exact resolved commits, never moving tags or
        # policy rows for older installed engines. A policy cannot add code.
        versions = {name: network_policy.network_version(network_policy.raw(
            network_policy.OPENCE, record['revision'], network_policy.LIMITS))
            for name, record in (('current', current), ('upstream', selected))}
        result['network'] = versions
        if versions['upstream'] < versions['current']:
            raise ValueError('Upstream network version is older than the bundled engine; inspect before retrying')
        if versions['upstream'] == versions['current']:
            return {**result, 'build': False, 'reason': 'same-network-version'}
        result['reason'] = 'network-version-change'
    if skip_retained:
        previous = retained_candidate(selected, candidate.product_digest(), version,
                                      draft.api(draft.API + '?per_page=100', pages=True))
        if previous:
            result.update(build=False, reason='retained-candidate',
                          candidate=f'halopad-candidate-{previous["version"]}-{previous["build"]}',
                          commit=previous['source']['commit'])
    return result


def summary(result):
    messages = {
        'current-engine': 'Already using this engine. No Mac build needed.',
        'same-network-version': 'Same network version. Defer to a maintenance update; no Mac build needed.',
        'network-version-change': 'Network version changed. Prepare a private candidate for review.',
        'retained-candidate': 'Exact candidate already retained. Reuse it without rebuilding.',
        'new-candidate': 'Build the selected engine as a private candidate.',
    }
    selected = result['record']
    lines = ['## HaloPad candidate selection', '',
             f'Engine: {selected["release"]} (`{selected["revision"]}`).', '',
             messages[result['reason']]]
    if 'network' in result:
        lines += ['', f'Network: {result["network"]["current"]} → {result["network"]["upstream"]}.']
    if result['candidate']:
        lines += ['', f'Retained candidate: `{result["candidate"]}`.']
    if result['reason'] in ('current-engine', 'same-network-version'):
        lines += ['', 'For an important fix or a maintenance update, use Run workflow with engine=upstream.']
    lines += ['', 'Candidate preparation does not publish a release or establish player/device acceptance.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channel', choices=('release', 'upstream'), required=True)
    parser.add_argument('--app-version', required=True)
    parser.add_argument('--skip-retained', action='store_true')
    parser.add_argument('--network-change-only', action='store_true',
                        help='prepare automatic candidates only for a newer network version')
    args = parser.parse_args()
    try:
        result = select(args.channel, args.app_version, skip_retained=args.skip_retained,
                        network_change_only=args.network_change_only)
        if os.environ.get('GITHUB_OUTPUT'):
            with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
                stream.write('build=' + str(result['build']).lower() + '\nrecord=' + json.dumps(result['record']) + '\n')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as stream:
                stream.write(summary(result))
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Upstream check failed; previous candidates remain unchanged: {error}\n')


if __name__ == '__main__':
    main()
