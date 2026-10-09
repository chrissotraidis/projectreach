#!/usr/bin/env python3
"""Exercise real macOS keychain setup/cleanup with an ephemeral CI-only fixture."""
import base64
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/xbox'))
import ci_signing


def main():
    if (sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'):
        sys.exit('This credential-free smoke test runs only on disposable GitHub-hosted Macs.')
    original = shlex.split(ci_signing.run(['security', 'list-keychains', '-d', 'user']))
    with tempfile.TemporaryDirectory(prefix='halopad-keychain-test-', dir=os.environ['RUNNER_TEMP']) as temp:
        root = Path(temp)
        config = root / 'openssl.cnf'
        config.write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n'
                          '[dn]\nCN=HaloPad CI Signing Fixture\n[extensions]\n'
                          'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n'
                          'extendedKeyUsage=codeSigning\n')
        subprocess.run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-config', str(config), '-keyout', str(root / 'key.pem'), '-out', str(root / 'cert.pem')],
                       check=True, capture_output=True)
        subprocess.run(['openssl', 'pkcs12', '-export', '-inkey', str(root / 'key.pem'), '-in', str(root / 'cert.pem'),
                        '-name', 'HaloPad CI Signing Fixture', '-out', str(root / 'fixture.p12'),
                        '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1',
                        '-passout', 'pass:inert-ci-fixture'], check=True, capture_output=True)
        fingerprint = subprocess.check_output(['openssl', 'x509', '-in', str(root / 'cert.pem'),
                                               '-noout', '-fingerprint', '-sha1'], text=True).strip().split('=')[1].replace(':', '')
        for valid in (True, False):
            env_file = root / ('valid.env' if valid else 'invalid.env')
            env = {**os.environ, 'GITHUB_ENV': str(env_file), 'HALOPAD_SIGNING_P12_PASSWORD': 'inert-ci-fixture',
                   'HALOPAD_SIGNING_P12_BASE64': base64.b64encode((root / 'fixture.p12').read_bytes() if valid else b'invalid fixture').decode(),
                   'HALOPAD_PROFILE_BASE64': base64.b64encode(b'inert profile fixture').decode(),
                   'HALOPAD_API_KEY_BASE64': base64.b64encode(b'inert API fixture').decode()}
            failed = False
            try:
                folder = ci_signing.prepare(env)
                identities = ci_signing.run(['security', 'find-identity', '-p', 'codesigning', str(folder / 'signing.keychain-db')])
                if fingerprint not in identities:
                    raise AssertionError('fixture private identity was not imported')
            except RuntimeError:
                if valid:
                    raise
                failed = True
            finally:
                if env_file.exists():
                    env.update(line.split('=', 1) for line in env_file.read_text().splitlines())
                    ci_signing.cleanup(env)
                    if Path(env['HALOPAD_SIGNING_DIR']).exists():
                        raise AssertionError('temporary credentials survived cleanup')
                if shlex.split(ci_signing.run(['security', 'list-keychains', '-d', 'user'])) != original:
                    raise AssertionError('original keychain search list was not restored')
            if failed == valid:
                raise AssertionError('unexpected signing fixture result')
    print('PASS: real CI keychain import/access setup, failed-import cleanup and search-list restoration.')


if __name__ == '__main__':
    main()
