"""Resolve one immutable OpenCE release before starting a personal build.

Failure is an update failure, never permission to silently ship an older engine.
The reviewed pin remains an explicit offline choice (HALOPAD_XBOX_PINNED=1).
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import urllib.request

LOCK = pathlib.Path(__file__).resolve().parents[2] / 'config/xbox-engine.lock.json'


def resolve(lock, pinned=False):
    if pinned:
        return {**{k: lock[k] for k in ('revision', 'release')}, 'channel': 'pinned'}
    match = re.fullmatch(r'https://github\.com/([\w.-]+/[\w.-]+)\.git', lock['url'])
    if not match:
        raise ValueError('OpenCE source must be a GitHub repository URL')
    request = urllib.request.Request(
        f'https://api.github.com/repos/{match[1]}/releases/latest',
        headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'HaloPad-builder'})
    with urllib.request.urlopen(request, timeout=20) as response:
        release = json.load(response)
    if not isinstance(release, dict):
        raise ValueError('OpenCE returned invalid release metadata')
    tag = release.get('tag_name')
    if not isinstance(tag, str) or not re.fullmatch(r'build-[0-9]+', tag):
        raise ValueError('OpenCE returned an unexpected release tag')
    # Annotated tags name a tag object, not a commit. Prefer the peeled ref.
    ref = f'refs/tags/{tag}'
    result = subprocess.run(['git', 'ls-remote', '--exit-code', lock['url'], ref, ref + '^{}'],
                            check=True, capture_output=True, text=True, timeout=30)
    refs = dict((name, sha) for sha, name in (line.split() for line in result.stdout.splitlines()))
    revision = refs.get(ref + '^{}', refs.get(ref, ''))
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('OpenCE release no longer resolves to a commit; retry the update')
    return {'revision': revision, 'release': tag, 'channel': 'latest'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pinned', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(resolve(json.loads(LOCK.read_text()), args.pinned)))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Cannot resolve the Xbox update: {error}. Retry when online. '
              'HALOPAD_XBOX_PINNED=1 explicitly builds the tested older engine instead.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
