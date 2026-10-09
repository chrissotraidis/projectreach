#!/usr/bin/env python3
"""Make, sign, verify and publish HaloPad's network compatibility policy.

An installed HaloPad keeps its engine. OpenCE refuses hosts of any other network
version, although each raise so far has been additive (older machines drop the
newer messages and still play). The policy tells each HaloPad engine version which
newer version to announce and which host versions to join, so a compatible raise
needs no new app (port/ios/HaloPadXboxNetworkPolicy.h applies it).

A raise is followed only when every version between the engine's and OpenCE's
latest is classified additive by ChupathingyCE's cross-play-tested table
(port/linux/include/delta.h, DELTA_LEGACY_VERSIONS), or approved by hand with
--approve-through. A breaking raise keeps the previous rows and is reported: that
change needs a new HaloPad build. Nothing here builds or downloads an engine.

    network_policy.py update [--mode follow|exact] [--approve-through N]
                             [--key KEY.pem] [--publish] [--out FILE] [--report FILE]
    network_policy.py verify FILE
    network_policy.py notify REPORT     (GitHub Actions: summary, and an issue when attention is needed)

The document is JSON; the published file is an envelope holding the document's
exact bytes and their ECDSA P-256/SHA-256 signature (both base64). Serials only
rise, so a cached newer policy is never replaced by an older one; --mode exact
publishes a newer policy that withdraws every widening.
"""
import argparse
import base64
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = 'chrissotraidis/projectreach'
BRANCH = 'halopad-network'
FILE = 'network-policy.json'
PUBLIC_KEY = ROOT / 'config/network-policy-public.pem'
RECORD = ROOT / 'config/xbox-release.json'
OPENCE = 'OpenCommunityEdition/OpenCE'
CLASSIFIER = 'ChupathingyCE/chupathingyce'
LIMITS = 'port/linux/include/halo_port_limits.h'
DELTA = 'port/linux/include/delta.h'
MAXIMUM_DOCUMENT = 16384
NETWORK_VERSION = re.compile(rb'^#define HALO_PORT_NETWORK_VERSION (\d+)[ \t]*$', re.M)
CLASSIFIED = re.compile(r'X\((\d+),\s*"(build-\d+)",\s*(additive|breaking)\)')
TAG = re.compile(r'[A-Za-z0-9._-]{1,32}')
# A raise unclassified this long is reported for a maintainer's decision.
WAITING_ALERT_SECONDS = 48 * 3600


class PolicyError(ValueError):
    pass


# ---------- the document


def network_version(header):
    """HALO_PORT_NETWORK_VERSION in an OpenCE halo_port_limits.h"""
    found = NETWORK_VERSION.findall(header)
    if len(found) != 1 or not 1 <= int(found[0]) <= 65535:
        raise PolicyError('halo_port_limits.h has no single network version')
    return int(found[0])


def classification(delta):
    """{version: 'additive' | 'breaking'} from ChupathingyCE's delta.h"""
    start = delta.find('#define DELTA_LEGACY_VERSIONS')
    if start < 0:
        raise PolicyError('delta.h has no DELTA_LEGACY_VERSIONS table')
    block = delta[start:delta.find('\n\n', start) if '\n\n' in delta[start:] else len(delta)]
    kinds = {}
    for number, _, kind in CLASSIFIED.findall(block):
        if int(number) in kinds:
            raise PolicyError(f'delta.h classifies network version {number} twice')
        kinds[int(number)] = kind
    if not kinds:
        raise PolicyError('delta.h classifies no network versions')
    return kinds


def exact(engine):
    return {'announce': engine, 'minimum': engine, 'maximum': engine}


def check_row(engine, row):
    if not isinstance(row, dict) or set(row) - {'announce', 'minimum', 'maximum', 'follows'}:
        raise PolicyError(f'engine {engine}: not a policy row')
    numbers = [row.get(k) for k in ('minimum', 'announce', 'maximum')]
    if any(type(n) is not int or not 1 <= n <= 65535 for n in numbers):
        raise PolicyError(f'engine {engine}: versions must be whole numbers from 1 to 65535')
    if not row['minimum'] <= engine <= row['announce'] <= row['maximum']:
        raise PolicyError(f'engine {engine}: needs minimum <= engine <= announce <= maximum')
    if 'follows' in row and not (isinstance(row['follows'], str) and TAG.fullmatch(row['follows'])):
        raise PolicyError(f'engine {engine}: follows is not a release tag')


def check_document(document):
    """The checks HaloPad makes (HaloPadXboxNetworkPolicy.h), on the exact bytes."""
    if len(document) > MAXIMUM_DOCUMENT:
        raise PolicyError('policy document is too large')
    policy = json.loads(document)
    if not isinstance(policy, dict) or policy.get('format') != 1 or type(policy.get('format')) is not int:
        raise PolicyError('not a format 1 network policy')
    serial = policy.get('serial')
    if type(serial) is not int or not 1 <= serial <= 1 << 53:
        raise PolicyError('serial must be a whole number from 1 to 2^53')
    engines = policy.get('engines')
    if not isinstance(engines, dict):
        raise PolicyError('engines must be an object')
    for key, row in engines.items():
        if not re.fullmatch(r'[1-9][0-9]{0,4}', key) or int(key) > 65535:
            raise PolicyError(f'engine {key!r} is not a network version')
        check_row(int(key), row)
    return policy


def decide(engine, upstream, kinds, previous=None, approved_through=0, upstream_tag=''):
    """(row, status) for one HaloPad engine version.

    current: OpenCE has not moved past this engine; exact row.
    following: every newer version is additive; announce and join up to upstream.
    waiting: a newer version is not classified yet; previous row kept.
    needs-release: a newer version is breaking; previous row kept, a new HaloPad is needed.
    """
    kept = previous if previous else exact(engine)
    if upstream <= engine:
        return exact(engine), 'current'
    newer = range(engine + 1, upstream + 1)
    if any(kinds.get(v) == 'breaking' and v > approved_through for v in newer):
        return kept, 'needs-release'
    if all(v <= approved_through or kinds.get(v) == 'additive' for v in newer):
        row = {'announce': upstream, 'minimum': engine, 'maximum': upstream}
        if previous and all(previous.get(k) == row[k] for k in row):
            return previous, 'following'  # same range: no new policy for every OpenCE build
        if upstream_tag:
            row['follows'] = upstream_tag
        return row, 'following'
    return kept, 'waiting'


def render(policy):
    return (json.dumps(policy, indent=2, sort_keys=True) + '\n').encode()


def plan(published, engines, upstream, upstream_tag, kinds, mode='follow', approved_through=0, now=None):
    """(document bytes or None when unchanged, report)"""
    now = int(time.time()) if now is None else now
    old = published['engines'] if published else {}
    report = {'upstream': {'release': upstream_tag, 'network_version': upstream}, 'engines': {}}
    rows = {}
    for engine in sorted(set(engines) | {int(k) for k in old}):
        previous = old.get(str(engine))
        if mode == 'exact':
            row, status = exact(engine), 'withdrawn'
        else:
            row, status = decide(engine, upstream, kinds, previous, approved_through, upstream_tag)
        check_row(engine, row)
        rows[str(engine)] = row
        report['engines'][str(engine)] = {'status': status, **row}
    if published and rows == old:
        report['changed'] = False
        return None, report
    serial = max(now, (published or {}).get('serial', 0) + 1)
    policy = {'format': 1, 'serial': serial, 'engines': rows,
              'issued': datetime.datetime.fromtimestamp(now, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
              'basis': f'OpenCE {upstream_tag} network {upstream}; additive versions from {CLASSIFIER} delta.h'
                       + (f'; maintainer approved through {approved_through}' if approved_through else '')}
    document = render(policy)
    check_document(document)
    report.update(changed=True, serial=serial)
    return document, report


# ---------- signatures (openssl: OpenSSL 3 or LibreSSL)


def openssl(*args, data=None):
    return subprocess.run([os.environ.get('OPENSSL', 'openssl'), *args], input=data, check=True,
                          capture_output=True).stdout


def sign(document, key):
    check_document(document)
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'document'
        path.write_bytes(document)
        signature = openssl('dgst', '-sha256', '-sign', str(key), str(path))
    envelope = {'format': 1, 'document': base64.b64encode(document).decode(),
                'signature': base64.b64encode(signature).decode()}
    result = (json.dumps(envelope, indent=2) + '\n').encode()
    verify(result, public_key_of(key))
    return result


def public_key_of(key):
    with tempfile.NamedTemporaryFile(suffix='.pem', delete=False) as stream:
        stream.write(openssl('ec', '-in', str(key), '-pubout'))
    return Path(stream.name)


def verify(envelope, public=PUBLIC_KEY):
    """The verified policy, or PolicyError."""
    try:
        outer = json.loads(envelope)
        document = base64.b64decode(outer['document'], validate=True)
        signature = base64.b64decode(outer['signature'], validate=True)
    except (ValueError, KeyError, TypeError) as error:
        raise PolicyError(f'not a policy envelope: {error}')
    if outer.get('format') != 1 or not 8 <= len(signature) <= 80:
        raise PolicyError('not a format 1 policy envelope')
    with tempfile.TemporaryDirectory() as folder:
        (Path(folder) / 'document').write_bytes(document)
        (Path(folder) / 'signature').write_bytes(signature)
        try:
            openssl('dgst', '-sha256', '-verify', str(public), '-signature', str(Path(folder) / 'signature'),
                    str(Path(folder) / 'document'))
        except subprocess.CalledProcessError:
            raise PolicyError('policy signature does not verify')
    return check_document(document)


# ---------- the world (GitHub; read-only except --publish)


def http(url):
    headers = {'User-Agent': 'HaloPad-network-policy'}
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if token and url.startswith('https://api.github.com/'):
        headers['Authorization'] = f'Bearer {token}'
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
        return response.read()


def api(path):
    return json.loads(http(f'https://api.github.com/{path}'))


def raw(repo, ref, path):
    return http(f'https://raw.githubusercontent.com/{repo}/{ref}/{path}')


def gh(path, method='GET', body=None):
    args = ['gh', 'api', path, '--method', method] + (['--input', '-'] if body is not None else [])
    output = subprocess.check_output(args, input=json.dumps(body) if body is not None else None, text=True)
    return json.loads(output) if output.strip() else None


def published_policy():
    """(verified policy or None, envelope bytes or None); refuses unverifiable content.

    Read through the API, never the raw CDN the app uses: the CDN can lag a new
    commit by minutes, and a stale read must not drive the next decision."""
    try:
        item = api(f'repos/{REPO}/contents/{FILE}?ref={BRANCH}')
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None, None
        raise
    envelope = base64.b64decode(item['content'])
    return verify(envelope), envelope


def gather():
    latest = api(f'repos/{OPENCE}/releases/latest')
    tag = latest['tag_name']
    if not re.fullmatch(r'build-[0-9]+', tag):
        raise PolicyError(f'unexpected OpenCE release tag {tag!r}')
    commit = api(f'repos/{OPENCE}/commits/{tag}')['sha']
    upstream = network_version(raw(OPENCE, commit, LIMITS))
    record = json.loads(RECORD.read_text())
    if not re.fullmatch(r'[0-9a-f]{40}', record.get('revision', '')):
        raise PolicyError('config/xbox-release.json has no engine revision')
    engine = network_version(raw(OPENCE, record['revision'], LIMITS))
    classifier = api(f'repos/{CLASSIFIER}/commits/main')['sha']
    kinds = classification(raw(CLASSIFIER, classifier, DELTA).decode())
    changed = api(f'repos/{OPENCE}/commits?path={LIMITS}&sha={commit}&per_page=1')
    raised = changed[0]['commit']['committer']['date'] if changed else None
    return {'tag': tag, 'commit': commit, 'upstream': upstream, 'engine': engine,
            'engine_release': record.get('release'), 'kinds': kinds, 'classifier': classifier, 'raised': raised}


def snapshot():
    refs = gh(f'repos/{REPO}/git/matching-refs/heads/{BRANCH}')
    matches = [r for r in refs if r['ref'] == f'refs/heads/{BRANCH}']
    if not matches:
        return None
    head = matches[0]['object']['sha']
    tree = gh(f'repos/{REPO}/git/trees/{gh(f"repos/{REPO}/git/commits/{head}")["tree"]["sha"]}')
    if tree.get('truncated') or [i['path'] for i in tree['tree']] != [FILE]:
        raise PolicyError(f'unexpected files on {BRANCH}; nothing overwritten')
    return head


def publish(envelope, serial):
    """One fast-forward commit holding only the policy, then read it back."""
    head = snapshot()
    tree = gh(f'repos/{REPO}/git/trees', 'POST',
              {'tree': [{'path': FILE, 'mode': '100644', 'type': 'blob', 'content': envelope.decode()}]})
    commit = gh(f'repos/{REPO}/git/commits', 'POST', {'message': f'HaloPad network policy {serial}',
                                                       'tree': tree['sha'], 'parents': [head] if head else []})
    if head:
        gh(f'repos/{REPO}/git/refs/heads/{BRANCH}', 'PATCH', {'sha': commit['sha'], 'force': False})
    else:
        gh(f'repos/{REPO}/git/refs', 'POST', {'ref': f'refs/heads/{BRANCH}', 'sha': commit['sha']})
    if snapshot() != commit['sha']:
        raise PolicyError('network policy branch readback differs; inspect before retrying')
    blob = gh(f'repos/{REPO}/contents/{FILE}?ref={commit["sha"]}')
    if base64.b64decode(blob['content']) != envelope:
        raise PolicyError('published network policy differs from the signed file')
    return commit['sha']


def update(args):
    world = gather()
    published, _ = published_policy()
    document, report = plan(published, {world['engine']}, world['upstream'], world['tag'], world['kinds'],
                            args.mode, args.approve_through)
    report['classifier'] = f'{CLASSIFIER}@{world["classifier"]}'
    report['engine_release'] = world['engine_release']
    report['raised'] = world['raised']
    statuses = {e['status'] for e in report['engines'].values()}
    report['attention'] = 'needs-release' in statuses
    if 'waiting' in statuses and world['raised']:
        raised = datetime.datetime.fromisoformat(world['raised'].replace('Z', '+00:00'))
        report['attention'] |= (datetime.datetime.now(datetime.timezone.utc) - raised).total_seconds() > WAITING_ALERT_SECONDS
    if document is not None:
        if not args.key:
            raise PolicyError('a changed policy needs --key to sign it')
        envelope = sign(document, args.key)
        if args.out:
            Path(args.out).write_bytes(envelope)
        if args.publish:
            report['commit'] = publish(envelope, report['serial'])
            published_again, _ = published_policy()
            if published_again != json.loads(document):
                raise PolicyError('published network policy did not read back')
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


def summary(report):
    upstream = report['upstream']
    lines = [f'OpenCE {upstream["release"]} uses network version {upstream["network_version"]}.', '',
             '| HaloPad engine | Status | Announces | Joins |', '| --- | --- | --- | --- |']
    for engine, row in sorted(report['engines'].items(), key=lambda item: int(item[0])):
        lines.append(f'| {engine} | {row["status"]} | {row["announce"]} | {row["minimum"]} to {row["maximum"]} |')
    lines += ['', f'Published signed policy {report["serial"]}.' if report.get('commit') else
              'A new policy was prepared but not published.' if report.get('changed') else
              'The published policy is unchanged.']
    return '\n'.join(lines) + '\n'


def notify(report):
    """Write the run summary; open one issue per upstream version that needs a person."""
    text = summary(report)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(text)
    print(text)
    if not report.get('attention'):
        return
    version = report['upstream']['network_version']
    breaking = any(row['status'] == 'needs-release' for row in report['engines'].values())
    title = (f'OpenCE network version {version} needs a new HaloPad build' if breaking else
             f'OpenCE network version {version} is waiting for a compatibility decision')
    existing = subprocess.check_output(['gh', 'issue', 'list', '--state', 'open', '--search', f'in:title "{title}"',
                                        '--json', 'title'], text=True)
    if any(item['title'] == title for item in json.loads(existing)):
        return
    advice = ('ChupathingyCE classifies this change as breaking, so installed HaloPad apps cannot follow it. '
              'A new HaloPad build with a newer engine is needed; existing apps keep playing with each other '
              'and with OpenCE players on the versions they already follow.' if breaking else
              'ChupathingyCE has not classified this OpenCE network version yet, so installed apps still use the '
              'previous policy. If you have tested it, run the HaloPad network compatibility workflow with '
              f'approve_through = {version}; otherwise wait or build a new HaloPad.')
    body = f'{advice}\n\n{text}\nClassifier: {report.get("classifier", "")}\n'
    with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False) as stream:
        stream.write(body)
    subprocess.run(['gh', 'issue', 'create', '--title', title, '--body-file', stream.name], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    command = commands.add_parser('update')
    command.add_argument('--mode', choices=('follow', 'exact'), default='follow')
    command.add_argument('--approve-through', type=int, default=0,
                         help='treat OpenCE network versions up to this one as additive (a maintainer decision)')
    command.add_argument('--key', type=Path)
    command.add_argument('--publish', action='store_true')
    command.add_argument('--out', type=Path)
    command.add_argument('--report', type=Path)
    command = commands.add_parser('verify')
    command.add_argument('file', type=Path)
    command = commands.add_parser('notify')
    command.add_argument('report', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            print(json.dumps(verify(args.file.read_bytes()), indent=2))
        elif args.command == 'notify':
            notify(json.loads(args.report.read_text()))
        else:
            update(args)
    except (PolicyError, OSError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        print(f'network policy: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
