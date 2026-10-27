#!/usr/bin/env python3
"""Check source-release inputs; optionally stage recipe-only assets. Never publish.

Without --out this is read-only. Outputs remain under ignored generated/ and do
not establish package, player-build, device or publication acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

import release

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from app_version import validate


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def source_identity(root, expected=None, require_clean=False):
    require(Path(git(root, 'rev-parse', '--show-toplevel').decode().strip()).resolve() == root,
            'source must be the repository root')
    clean = not git(root, 'status', '--porcelain', '--untracked-files=all').strip()
    require(not require_clean or clean, 'source checkout must be clean, including untracked files')
    commit = git(root, 'rev-parse', 'HEAD').decode().strip()
    require(expected is None or expected == commit, 'source HEAD differs from --source')
    return {'commit': commit, 'tree': git(root, 'rev-parse', 'HEAD^{tree}').decode().strip(), 'clean': clean}


def argument(argv, flag):
    require(argv.count(flag) == 1, 'expected exactly one ' + flag)
    index = argv.index(flag) + 1
    require(index < len(argv), 'missing value after ' + flag)
    return argv[index]


def scalar(text, keys):
    """Read one known mapping field in this repository's two-space YAML style.

    Deliberately not a general YAML parser: changed/ambiguous structure fails
    closed. Comments and unrelated fields cannot satisfy a required field.
    """
    lines = text.splitlines()
    start, end = 0, len(lines)
    for depth, key in enumerate(keys):
        prefix = '  ' * depth + key + ':'
        matches = [i for i in range(start, end) if lines[i].startswith(prefix)]
        require(len(matches) == 1, 'missing or duplicate workflow field ' + '.'.join(keys))
        index = matches[0]
        value = lines[index][len(prefix):].strip()
        start = index + 1
        end = next((i for i in range(start, end) if lines[i].strip()
                    and not lines[i].lstrip().startswith('#')
                    and len(lines[i]) - len(lines[i].lstrip()) <= depth * 2), end)
    tokens = shlex.split(value, comments=True)
    require(len(tokens) == 1, 'workflow field must be one scalar: ' + '.'.join(keys))
    return tokens[0]


def commands(text):
    """Extract shell command lines only from workflow run blocks."""
    lines = text.splitlines()
    result = []
    index = 0
    while index < len(lines):
        line = lines[index]
        match = re.fullmatch(r'( *)(?:- )?run: *\| *', line)
        index += 1
        if not match:
            single = re.fullmatch(r' *(?:- )?run: *(python3 scripts/xbox/.*|scripts/builder/build.sh .*)', line)
            if single:
                result.append(shlex.split(single[1], comments=True))
            continue
        indent = len(match[1])
        pending = ''
        while index < len(lines):
            line = lines[index]
            if line.strip() and len(line) - len(line.lstrip()) <= indent:
                break
            index += 1
            line = line.strip()
            pending += line[:-1] + ' ' if line.endswith('\\') else line
            if line.endswith('\\'):
                continue
            # Other shell/Python heredoc lines are not release invocations.
            if pending.startswith(('python3 scripts/xbox/', 'scripts/builder/build.sh ')):
                result.append(shlex.split(pending, comments=True))
            pending = ''
    return result


def invocation(items, program):
    matches = [args for args in items if args[:2] == ['python3', program]]
    require(len(matches) == 1, 'missing or duplicate workflow invocation: ' + program)
    return matches[0]


def check_versions(recipe, build_workflow, player_workflow, version):
    validate(version, '1')
    require(len(version.split('.')) == 3, 'release version needs three components')
    require(recipe.get('id') == 'projectreach' and recipe.get('schema_version') == 1,
            'expected the HaloPad PadMint recipe')
    require(recipe.get('publication', {}).get('public_binaries') is False,
            'recipe must prohibit public binaries')
    require(set(recipe.get('targets', {})) == {'ios', 'macos'}, 'expected iOS and Mac recipe targets')
    for platform, target in recipe['targets'].items():
        argv = target.get('command')
        require(isinstance(argv, list) and all(isinstance(x, str) for x in argv),
                'invalid recipe command for ' + platform)
        require(argument(argv, '--app-version') == version, 'recipe version differs: ' + platform)
    build = commands(build_workflow)
    for program in ('check_update.py', 'candidate.py'):
        require(argument(invocation(build, 'scripts/xbox/' + program), '--app-version') == version,
                'workflow version differs: ' + program)
    if any(args[:2] == ['python3', 'scripts/xbox/prepare_release.py'] for args in build):
        require(argument(invocation(build, 'scripts/xbox/prepare_release.py'), '--version') == version,
                'workflow preparation version differs')
    tag = argument(invocation(build, 'scripts/xbox/update_source.py'), '--tag')
    require(tag == 'halopad-' + version + '-$((1000 + GITHUB_RUN_NUMBER))',
            'workflow staging tag differs from release version')
    # The actual cache-key field, excluding comments and script strings.
    keys = [line.strip().split(':', 1)[1].strip() for line in build_workflow.splitlines()
            if re.match(r'^\s+key:\s+halopad-failure-', line)]
    require(len(keys) == 1 and keys[0].startswith('halopad-failure-v1-' + version + '-${{'),
            'workflow failure-cache version differs')
    require(scalar(player_workflow, ('jobs', 'build', 'env', 'APP_VERSION')) == version,
            'player workflow APP_VERSION differs')
    # Keep this small checker tied to the simple current workflow: a step env or
    # shell assignment can shadow the job's value. New binding syntax needs review.
    bindings = 0
    for line in player_workflow.splitlines():
        if re.search(r'\bAPP_VERSION[\'\"]?\s*[:=]', line):
            tokens = shlex.split(line.rstrip().rstrip('\\'), comments=True)
            content = ' '.join(tokens)
            bindings += len(re.findall(r'\bAPP_VERSION\s*:', content))
            require(not re.search(r'\bAPP_VERSION\s*=', content),
                    'player workflow must not reassign APP_VERSION')
    require(bindings == 1, 'player workflow must have only its job-level APP_VERSION binding')
    player_builds = [args for args in commands(player_workflow) if args[0] == 'scripts/builder/build.sh']
    require(len(player_builds) == 2, 'expected both player workflow builds')
    require(all(argument(args, '--app-version') == '$APP_VERSION' for args in player_builds),
            'player builds must use their checked APP_VERSION')


def prepare(root, version, expected=None, out=None):
    root = root.resolve()
    source = source_identity(root, expected, require_clean=out is not None)
    recipe_bytes = (root / 'padmint.json').read_bytes()
    recipe = json.loads(recipe_bytes)
    workflows = [(root / '.github/workflows' / name).read_text()
                 for name in ('halopad-build.yml', 'halopad-player-build.yml')]
    check_versions(recipe, *workflows, version)
    selected = release.read_record(root / 'config/xbox-release.json')
    if out is not None:
        for name, data in zip(('padmint.json', '.github/workflows/halopad-build.yml',
                               '.github/workflows/halopad-player-build.yml'),
                              (recipe_bytes, *(text.encode() for text in workflows))):
            require(git(root, 'show', source['commit'] + ':' + name) == data,
                    'release inputs differ from the source commit: ' + name)
        require(git(root, 'show', source['commit'] + ':config/xbox-release.json') ==
                (root / 'config/xbox-release.json').read_bytes(), 'engine record differs from source commit')
        require(source_identity(root, source['commit'], require_clean=True) == source,
                'source changed during preparation')
    asset = 'HaloPad-v' + version + '-padmint.json'
    checksum = hashlib.sha256(recipe_bytes).hexdigest()
    report = {
        'schema': 1, 'status': 'inputs-checked; acceptance-not-checked',
        'version': version, 'tag': 'v' + version, 'source': source,
        'engine_record': selected,
        'assets': {asset: {'sha256': checksum, 'bytes': len(recipe_bytes)}, 'SHA256SUMS': {}},
        'validation_scope': 'Version fields and engine-record format only; no source/adaptation review or build run.',
        'acceptance': {name: 'not_checked' for name in (
            'upstream_and_adaptation_review', 'repository_and_public_content_review', 'current_padmint_main',
            'pre_player_checks', 'package_audits', 'physical_runtime',
            'publication_and_anonymous_readback', 'post_player_checks')},
        'player_check_commands': {
            'working_directory': '<clean current PadMint main checkout>',
            'pre': [['bash', 'scripts/player-check.sh', 'projectreach', platform,
                     '<your Xbox ISO>', str(root)] for platform in ('ios', 'macos')],
            'post': [['bash', 'scripts/player-check.sh', 'projectreach', platform,
                      '<your Xbox ISO>'] for platform in ('ios', 'macos')],
            'note': 'Prechecks run before tagging. Postchecks run after publishing, without a checkout; '
                    'verify they select the expected public tag and source commit. Commands are not executed.'},
        'published': False,
    }
    sums = (checksum + '  ' + asset + '\n').encode()
    report['assets']['SHA256SUMS'] = {'sha256': hashlib.sha256(sums).hexdigest(), 'bytes': len(sums)}
    if out is not None:
        out = out.resolve()
        require(out != root / 'generated' and out.is_relative_to(root / 'generated'),
                '--out must be a new directory beneath this checkout\'s generated/')
        require(not out.exists(), '--out already exists; nothing overwritten')
        ignored = subprocess.run(['git', '-C', str(root), 'check-ignore', '--no-index', '-q', str(out)])
        require(ignored.returncode == 0, '--out must be ignored by Git')
        out.mkdir(parents=True, exist_ok=False)
        assets = out / 'public-assets'
        assets.mkdir()
        (assets / asset).write_bytes(recipe_bytes)
        (assets / 'SHA256SUMS').write_bytes(sums)
        report['output'] = str(out)
        (out / 'preparation.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--source', help='expected full HEAD commit; staging additionally requires a clean checkout')
    parser.add_argument('--out', type=Path, help='fresh ignored directory under generated/; omit for read-only checks')
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(ROOT, args.version, args.source, args.out), indent=2))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        parser.exit(1, 'Release preparation stopped: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
