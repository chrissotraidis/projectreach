"""Publish two small update feeds atomically, independently of source releases."""
import base64
import json
import re

import candidate
import draft_release as draft

BRANCH = 'halopad-updates'
BASE = f'https://raw.githubusercontent.com/{draft.REPO}/{BRANCH}'
FILES = ('altstore.json', 'halopad-update.json')
API = f'repos/{draft.REPO}/git'


def version_key(version, build):
    candidate.validate(version, str(build))
    parts = tuple(map(int, version.split('.')))
    return parts + (0,) * (3 - len(parts)), int(build)


def engine_key(record):
    engine = record['engine']
    match = re.fullmatch(r'build-([0-9]+)', engine['release'])
    if not match or not re.fullmatch(r'[0-9a-f]{40}', engine['revision']):
        raise ValueError('invalid engine identity')
    return int(match[1]), engine['revision']


def require_forward(new, old):
    """Same-engine app fixes are allowed, engine regressions/retags are not."""
    new_engine = engine_key(new)
    if old is None:
        return
    if old.get('bundle_id') != 'dev.halopad.HaloPad':
        raise ValueError('previous update metadata belongs to another app')
    previous = engine_key(old)
    if new_engine[0] < previous[0] or (new_engine[0] == previous[0] and new_engine[1] != previous[1]):
        raise ValueError('engine regression or retag; publication stopped')
    if version_key(new['version'], new['build']) <= version_key(old['version'], old['build']):
        raise ValueError('candidate is not newer than the current public app; publication stopped')


def published_record(releases):
    """Ignore recipe-only releases, even when GitHub calls one latest."""
    apps = []
    for item in releases:
        match = re.fullmatch(r'halopad-([0-9.]+)-([0-9]+)', item['tag_name'])
        if match and not item['draft'] and not item['prerelease']:
            apps.append((version_key(*match.groups()), item))
    if not apps:
        return None
    _, latest = max(apps, key=lambda pair: pair[0])
    assets = [a for a in latest['assets'] if a['name'] == 'halopad-update.json']
    if len(assets) != 1:
        raise ValueError('published app is missing its update identity')
    record = json.loads(draft.asset_bytes(assets[0]))
    if latest['tag_name'] != f'halopad-{record["version"]}-{record["build"]}':
        raise ValueError('published app identity differs from tag')
    return record


def snapshot():
    refs = draft.api(f'{API}/matching-refs/heads/{BRANCH}')
    matches = [r for r in refs if r['ref'] == f'refs/heads/{BRANCH}']
    if not matches:
        return None, {}
    if len(matches) != 1:
        raise ValueError('ambiguous update channel')
    head = matches[0]['object']['sha']
    commit = draft.api(f'{API}/commits/{head}')
    tree = draft.api(f'{API}/trees/{commit["tree"]["sha"]}')
    if tree.get('truncated') or {i['path'] for i in tree['tree']} != set(FILES) or len(tree['tree']) != 2:
        raise ValueError('unexpected update channel files; nothing overwritten')
    files = {}
    for item in tree['tree']:
        if item['type'] != 'blob' or item['mode'] != '100644':
            raise ValueError('unexpected update channel file type')
        blob = draft.api(f'{API}/blobs/{item["sha"]}')
        if blob['encoding'] != 'base64':
            raise ValueError('unexpected update channel encoding')
        files[item['path']] = base64.b64decode(blob['content']).decode('utf-8')
    return head, files


def advance(out):
    """Only called after all release assets are public and verified."""
    files = {name: (out / name).read_text() for name in FILES}
    record = json.loads(files['halopad-update.json'])
    feed = json.loads(files['altstore.json'])
    app = feed['apps'][0]
    version = app['versions'][0]
    if (record['bundle_id'] != 'dev.halopad.HaloPad' or app['bundleIdentifier'] != record['bundle_id']
            or feed['sourceURL'] != BASE + '/altstore.json'
            or (version['version'], version['buildVersion'], version['downloadURL']) !=
               (record['version'], record['build'], record['artifacts']['ios']['url'])):
        raise ValueError('update feeds disagree')
    head, previous = snapshot()
    if previous == files:
        return head  # A retry after a lost response performs no mutation.
    require_forward(record, json.loads(previous['halopad-update.json']) if previous else None)
    tree = draft.api(f'{API}/trees', 'POST', {'tree': [
        {'path': name, 'mode': '100644', 'type': 'blob', 'content': files[name]} for name in FILES]})
    commit = draft.api(f'{API}/commits', 'POST', {
        'message': f'HaloPad {record["version"]} ({record["build"]}) update feeds',
        'tree': tree['sha'], 'parents': [head] if head else []})
    # A fast-forward-only ref update rejects competing writers instead of erasing them.
    if head:
        draft.api(f'{API}/refs/heads/{BRANCH}', 'PATCH', {'sha': commit['sha'], 'force': False})
    else:
        draft.api(f'{API}/refs', 'POST', {'ref': f'refs/heads/{BRANCH}', 'sha': commit['sha']})
    verified_head, verified_files = snapshot()
    if verified_head != commit['sha'] or verified_files != files:
        raise ValueError('update channel readback differs; inspect before retrying')
    return verified_head
