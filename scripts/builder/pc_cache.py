"""Verified reuse of this checkout's PC translation, across Xbox-only updates.

Only the personal builder records receipts. Missing, changed or damaged inputs
and outputs cause a full translation. No game data or key is stored in a receipt.
"""
import argparse
import hashlib
import importlib.metadata
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROFILE = 'custom-en-1.0.10.0621'
RECEIPT = pathlib.Path('generated/builder/pc-translation.json')


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            sha.update(block)
    return sha.hexdigest()


def hashes(root, paths):
    return {str(path.relative_to(root)): digest(path) for path in sorted(set(paths))}


def inputs(root):
    profile = json.loads((root / f'config/profiles/{PROFILE}.json').read_text())
    files = [root / name for name in ('dependencies.lock.json', 'toolchains.lock.json')]
    # Conservative dependency set: PC code/config/tools, including local edits.
    # Xbox engine/renderer changes do not invalidate the independent PC edition.
    for folder in ('scripts', 'config', 'port'):
        files.extend(p for p in (root / folder).rglob('*') if p.is_file()
                     and '__pycache__' not in p.parts and p.suffix != '.pyc'
                     and 'xbox' not in p.relative_to(root).parts
                     and not p.name.startswith(('xbox-', 'HaloPadXbox')))
    modules = [{'file': profile['executable'], 'sha256': profile['accepted_sha256']},
               *profile['modules'].values()]
    for module in modules:
        path = root / module.get('root', profile['original_root']) / module['file']
        if digest(path) != module['sha256']:
            raise ValueError(f'PC input does not match the accepted profile: {path.name}')
        files.append(path)
    return hashes(root, files)


def outputs(root, work):
    work = work.resolve()
    work.relative_to(root / f'generated/srw/{PROFILE}')
    va = work / 'va'
    profile = json.loads((root / f'config/profiles/{PROFILE}.json').read_text())
    analysis = root / f'generated/analysis/{PROFILE}'
    required = [va / 'haloce.va.ll', va / 'dispatch.ll', analysis / 'image.bin']
    for name in profile['modules']:
        required += [va / name / f'{name}.va.ll', analysis / 'modules' / name / 'image.bin']
    for src in (root / 'port/llasm-runtime').glob('*.llasm'):
        generated = va / (src.stem + '.ll')
        # Match the app builder's freshness guard, including identical files
        # touched by a checkout or restore after the last translation.
        if generated.stat().st_mtime < src.stat().st_mtime:
            raise ValueError(f'PC runtime translation is stale: {src.name}')
        required.append(generated)
    # Also verify cached objects, if the prior build compiled a target already.
    return hashes(root, [*required, *va.rglob('*.ll'), *work.glob('slices-va-*/*.o')])


def toolchain():
    return {'python': sys.version, 'packages': {name: importlib.metadata.version(name)
            for name in ('pefile', 'capstone', 'scons')},
            'clang': subprocess.check_output(['clang', '--version'], text=True),
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True)}


def lookup(root, tools):
    try:
        receipt = json.loads((root / RECEIPT).read_text())
        work = root / receipt['work']
        if (receipt['schema'] == 1 and receipt['tools'] == tools
                and receipt['inputs'] == inputs(root) and receipt['outputs'] == outputs(root, work)):
            return work
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def record(root, work, tools):
    receipt = {'schema': 1, 'work': str(work.relative_to(root)), 'tools': tools,
               'inputs': inputs(root), 'outputs': outputs(root, work)}
    path = root / RECEIPT
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(receipt, sort_keys=True, indent=2) + '\n')
    temporary.replace(path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('lookup', 'record'))
    parser.add_argument('--work', type=pathlib.Path)
    args = parser.parse_args()
    if args.action == 'record':
        if not args.work:
            parser.error('record needs --work')
        record(ROOT, args.work.resolve(), toolchain())
    else:
        work = lookup(ROOT, toolchain())
        if work:
            print(work.relative_to(ROOT))
