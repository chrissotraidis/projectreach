#!/usr/bin/env python3
"""Resolve once; skip upstream candidates already retained for this product source."""
import argparse
import json
import os
from pathlib import Path
import subprocess

import candidate
import draft_release as draft
import release


def retained(selected, source_hash, version, releases):
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
            if (data['schema'] == 1 and archive.get('digest') == 'sha256:' + data['archive_sha256']
                    and record['status'] == 'built-awaiting-acceptance' and record['version'] == version
                    and record['source']['tree_sha256'] == source_hash
                    and all(record['engine'][key] == selected[key] for key in ('revision', 'release'))):
                return True
        except (ValueError, KeyError, TypeError):
            continue  # Incomplete/edited receipts never suppress a needed build.
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channel', choices=('release', 'upstream'), required=True)
    parser.add_argument('--app-version', required=True)
    parser.add_argument('--skip-retained', action='store_true')
    args = parser.parse_args()
    try:
        selected = (release.resolve(json.loads(release.LOCK.read_text())) if args.channel == 'upstream'
                    else release.read_record(release.BUNDLED))
        skip = args.skip_retained and retained(selected, candidate.product_digest(), args.app_version,
            draft.api(draft.API + '?per_page=100', pages=True))
        result = {'build': not skip, 'record': selected}
        if os.environ.get('GITHUB_OUTPUT'):
            with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
                stream.write('build=' + str(not skip).lower() + '\nrecord=' + json.dumps(selected) + '\n')
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Upstream check failed; previous candidates remain unchanged: {error}\n')


if __name__ == '__main__':
    main()
