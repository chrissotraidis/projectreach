#!/usr/bin/env python3
"""Install scoped signing inputs on a disposable GitHub-hosted Mac only."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import tempfile


def run(args):
    # security import/ACL commands take passwords as arguments. Never include
    # their argv or captured output in errors or uploaded build reports.
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('signing keychain command failed; no credentials printed')
    return result.stdout


def prepare(env):
    inputs = {}
    for name in ('HALOPAD_SIGNING_P12_BASE64', 'HALOPAD_PROFILE_BASE64', 'HALOPAD_API_KEY_BASE64'):
        try:
            value = base64.b64decode(env[name], validate=True)
            if not value:
                raise ValueError()
            inputs[name] = value
        except (KeyError, ValueError):
            raise ValueError(f'missing or invalid signing secret: {name}') from None
    if 'HALOPAD_SIGNING_P12_PASSWORD' not in env:
        raise ValueError('missing signing certificate password')
    folder = Path(tempfile.mkdtemp(prefix='halopad-signing-', dir=env['RUNNER_TEMP']))
    keychain = folder / 'signing.keychain-db'
    # Register cleanup before importing anything; GitHub's always() step also
    # runs if a later provisioning, upload or review request fails.
    with open(env['GITHUB_ENV'], 'a') as output:
        output.write(f'HALOPAD_SIGNING_DIR={folder}\nHALOPAD_SIGNING_PROFILE={folder / "profile.mobileprovision"}\n'
                     f'HALOPAD_API_KEY_PATH={folder / "api-key.p8"}\n')
    for name, path in (('HALOPAD_SIGNING_P12_BASE64', 'certificate.p12'),
                       ('HALOPAD_PROFILE_BASE64', 'profile.mobileprovision'),
                       ('HALOPAD_API_KEY_BASE64', 'api-key.p8')):
        target = folder / path
        target.touch(mode=0o600)
        target.write_bytes(inputs[name])
    previous = shlex.split(run(['security', 'list-keychains', '-d', 'user']))
    (folder / 'previous-keychains.json').write_text(json.dumps(previous))
    password = secrets.token_hex(32)
    run(['security', 'create-keychain', '-p', password, str(keychain)])
    run(['security', 'set-keychain-settings', '-lut', '7200', str(keychain)])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    run(['security', 'import', str(folder / 'certificate.p12'), '-k', str(keychain),
         '-P', env['HALOPAD_SIGNING_P12_PASSWORD'], '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'])
    run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain)])
    run(['security', 'list-keychains', '-d', 'user', '-s', str(keychain), *previous])
    return folder


def cleanup(env):
    if not env.get('HALOPAD_SIGNING_DIR'):
        return
    folder = Path(env['HALOPAD_SIGNING_DIR']).resolve()
    if folder.parent != Path(env['RUNNER_TEMP']).resolve() or not folder.name.startswith('halopad-signing-'):
        raise ValueError('unexpected signing directory; nothing removed')
    previous = folder / 'previous-keychains.json'
    try:
        if previous.exists():
            run(['security', 'list-keychains', '-d', 'user', '-s', *json.loads(previous.read_text())])
    finally:
        try:
            if (folder / 'signing.keychain-db').exists():
                run(['security', 'delete-keychain', str(folder / 'signing.keychain-db')])
        finally:
            shutil.rmtree(folder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'cleanup'))
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
        parser.exit(1, 'Signing setup is restricted to a disposable GitHub-hosted runner.\n')
    try:
        (prepare if args.action == 'prepare' else cleanup)(os.environ)
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        parser.exit(1, f'CI signing {args.action} stopped: {error}\n')


if __name__ == '__main__':
    main()
