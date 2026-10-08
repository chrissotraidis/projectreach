#!/usr/bin/env python3
"""One private OpenCE update cycle: resolve, test, build, audit, remember.

Safe to invoke repeatedly on one Mac. No upload, signing account, device install,
feed promotion or gameplay-acceptance claim. All packages remain private.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import signal
import stat
import subprocess
import sys
import tempfile
import zipfile

import release

ROOT = Path(__file__).resolve().parents[2]
LOCK_FD = None
sys.path.insert(0, str(ROOT / 'scripts'))
from app_version import validate


def digest(path):
    with path.open('rb') as stream:
        result = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
        return result.hexdigest()


def write_json(path, value):
    """Replace complete metadata, never leave a partially written pointer."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temp = Path(stream.name)
        stream.write((json.dumps(value, indent=2) + '\n').encode())
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)


def source_identity():
    # Include uncommitted source edits; ignored private inputs/output are excluded.
    names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT)
    result = hashlib.sha256()
    for name in sorted(set(names.split(b'\0')) - {b''}):
        if name.split(b'/')[0] not in (b'port', b'scripts', b'config', b'assets', b'tests', b'tools'):
            continue
        path = ROOT / os.fsdecode(name)
        result.update(name + b'\0')
        result.update(path.read_bytes() if path.is_file() else b'<absent>')
        result.update(b'\0')
    return {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'tree_sha256': result.hexdigest(),
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            'guest_compiler': subprocess.check_output([str(Path(os.environ.get('XBOX_LLVM_BIN', '/opt/homebrew/opt/llvm/bin')) / 'clang'), '--version'], text=True).strip()}


def command(argv, log):
    with log.open('w') as stream:
        # Retain the lock in the child if the parent is killed mid-build.
        process = subprocess.Popen(argv, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True, pass_fds=() if LOCK_FD is None else (LOCK_FD,))
        try:
            status = process.wait(timeout=4 * 3600 if argv[0] == '/bin/bash' else 600)
            if status:
                raise subprocess.CalledProcessError(status, argv)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise


def audit(path, platform, selected, version, build):
    """Inspect the delivered archive, not a possibly different build directory."""
    mac = platform == 'mac'
    bundle = 'HaloPad.app' if mac else 'Payload/HaloPad.app'
    resources = bundle + ('/Contents/Resources' if mac else '')
    plist = bundle + ('/Contents/Info.plist' if mac else '/Info.plist')
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names):
            raise ValueError('duplicate archive entries')
        for item in archive.infolist():
            parts = PurePosixPath(item.filename)
            if parts.is_absolute() or '..' in parts.parts or '\\' in item.filename:
                raise ValueError('unsafe archive path')
            if stat.S_ISLNK(item.external_attr >> 16):
                raise ValueError('unexpected archive symlink')
        if any(name.endswith('embedded.mobileprovision') for name in names):
            raise ValueError('private provisioning profile in candidate')
        info = plistlib.loads(archive.read(plist))
        if (info.get('CFBundleIdentifier') != 'dev.halopad.HaloPad'
                or info.get('CFBundleShortVersionString') != version
                or info.get('CFBundleVersion') != build
                or info.get('CFBundleSupportedPlatforms') != ['MacOSX' if mac else 'iPhoneOS']):
            raise ValueError('packaged application identity differs from candidate')
        data = resources + '/data/'
        expected = {data + 'xbox/' + name for name in ('build.json', 'halo_guest.elf', 'brokers.txt')}
        if {name for name in names if name.startswith(data) and not name.endswith('/')} != expected:
            raise ValueError('candidate must contain only Xbox engine data, no PC or player data')
        engine = json.loads(archive.read(data + 'xbox/build.json'))
        if any(engine.get(key) != selected[key] for key in ('revision', 'release')):
            raise ValueError('packaged engine differs from resolved release')
        if type(engine.get('network_version')) is not int or engine['network_version'] < 0:
            raise ValueError('missing multiplayer protocol identity')
        if hashlib.sha256(archive.read(data + 'xbox/halo_guest.elf')).hexdigest() != engine.get('guest_sha256'):
            raise ValueError('packaged guest checksum mismatch')
        if not archive.read(data + 'xbox/brokers.txt').strip():
            raise ValueError('empty multiplayer broker configuration')
        with tempfile.TemporaryDirectory(prefix='halopad-candidate-audit-') as folder:
            archive.extractall(folder)
            # zipfile does not restore executable permissions, which codesign needs.
            for item in archive.infolist():
                target = Path(folder) / item.filename
                if target.is_file():
                    target.chmod((item.external_attr >> 16) & 0o777 or 0o644)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(Path(folder) / bundle)],
                           check=True, capture_output=True)
    return {'path': str(path), 'sha256': digest(path), 'size': path.stat().st_size,
            'version': version, 'build': build, 'network_version': engine['network_version'],
            'minimum_os': info.get('LSMinimumSystemVersion' if mac else 'MinimumOSVersion'),
            'signature': 'verified; consumer signing not tested'}


def iterate(out, version, first_build, record=None, retry=False):
    validate(version, str(first_build))
    source = source_identity()
    selected = release.read_record(record) if record else release.resolve(json.loads(release.LOCK.read_text()))
    identity = {'source': source, 'engine': {k: selected[k] for k in ('revision', 'release')}, 'version': version}
    cache_identity = {**identity, 'source': {k: v for k, v in source.items() if k != 'commit'}}
    key = hashlib.sha256(json.dumps(cache_identity, sort_keys=True).encode()).hexdigest()
    state_path = out / 'states' / (key + '.json')
    if state_path.exists():
        previous = json.loads(state_path.read_text())
        if previous['status'] == 'built-awaiting-acceptance':
            for artifact in previous['artifacts'].values():
                path = Path(artifact['path'])
                if not path.is_file() or digest(path) != artifact['sha256']:
                    raise ValueError('retained candidate changed; inspect it before retrying')
            return {**previous, 'unchanged': True}
        if not retry:
            return {**previous, 'unchanged': True}
    counter = out / 'next-build.json'
    number = json.loads(counter.read_text()) if counter.exists() else first_build
    if type(number) is not int or number < first_build:
        raise ValueError('invalid build counter or --first-build exceeds the existing counter')
    validate(version, str(number))
    # Reserve before expensive work, including failed/interrupted attempts.
    write_json(counter, number + 1)
    run = out / 'runs' / f'{number}-{selected["release"]}'
    run.mkdir(parents=True, exist_ok=False)
    record_path = run / 'xbox-release.json'
    write_json(record_path, selected)
    result = {**identity, 'build': str(number), 'run': str(run), 'status': 'building',
              'started': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'artifacts': {}}
    write_json(state_path, result)
    try:
        for pattern in ('test_xbox*.py', 'test_builder_updates.py'):
            command([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', pattern],
                    run / ('tests-' + pattern.replace('*', 'all') + '.log'))
        for platform in ('mac', 'ios'):
            package = run / ('HaloPad-Mac.zip' if platform == 'mac' else 'HaloPad.ipa')
            argv = ['/bin/bash', 'scripts/builder/build.sh', '--xbox-only',
                    '--xbox-release-record', str(record_path), '--app-version', version, '--app-build', str(number),
                    '--out', str(run / platform), '--zip' if platform == 'mac' else '--ipa', str(package)]
            if platform == 'mac':
                argv.append('--mac')
            print(f'Building {selected["release"]} for {platform}; log: {run / (platform + ".log")}', flush=True)
            command(argv, run / (platform + '.log'))
            result['artifacts'][platform] = audit(package, platform, selected, version, str(number))
        if result['artifacts']['mac']['network_version'] != result['artifacts']['ios']['network_version']:
            raise ValueError('Mac and iOS multiplayer versions differ')
        if {k: v for k, v in source_identity().items() if k != 'commit'} != cache_identity['source']:
            raise ValueError('HaloPad source changed during build; candidate is not reproducible')
        result['status'] = 'built-awaiting-acceptance'
        result['acceptance'] = {'gameplay': False, 'consumer_upgrade': False, 'publication': False}
        write_json(run / 'result.json', result)
        write_json(state_path, result)
        # This is a private built-candidate pointer, NEVER a player update feed.
        write_json(out / 'latest-built.json', result)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError, KeyboardInterrupt) as error:
        result.update(status='failed', error=str(error) or type(error).__name__)
        write_json(run / 'result.json', result)
        write_json(state_path, result)
        raise
    return result


def main():
    global LOCK_FD
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / 'generated/xbox-candidates')
    parser.add_argument('--app-version', required=True)
    parser.add_argument('--first-build', type=int, required=True, help='initial unused build number; persisted thereafter')
    parser.add_argument('--record', type=Path, help='replay a private release record instead of resolving latest')
    parser.add_argument('--retry-failed', action='store_true', help='new attempt for an unchanged failed/interrupted candidate')
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(ROOT / 'generated'):
            raise ValueError('--out must be under ignored generated/; candidate packages are private')
        out.mkdir(parents=True, exist_ok=True)
        # Serialize runner instances even when they use different output folders.
        # Direct manual builds also use the engine cache; do not run those concurrently.
        with (ROOT / 'generated/.xbox-candidate.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            LOCK_FD = lock.fileno()
            try:
                result = iterate(out, args.app_version, args.first_build, args.record, args.retry_failed)
            finally:
                LOCK_FD = None
        print(json.dumps(result, indent=2))
        return 0 if result['status'] == 'built-awaiting-acceptance' else 1
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        print(f'Candidate cycle stopped: {error}. Previous built packages are retained.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
