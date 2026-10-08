"""Unattended delivery stops before upload on configuration/export/audit failures."""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import candidate
import ci_signing
import export_archive
import testflight


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        key = self.root / 'key.p8'; key.write_text('private fixture')
        self.env = {'HALOPAD_TESTFLIGHT_CHANNEL': 'internal', 'HALOPAD_TESTFLIGHT_GROUPS': '["Internal"]',
                    'HALOPAD_USES_NON_EXEMPT_ENCRYPTION': 'true', 'HALOPAD_API_KEY_PATH': str(key),
                    'HALOPAD_API_KEY_ID': 'ABCDE12345', 'HALOPAD_API_ISSUER': '11111111-2222-3333-4444-555555555555'}
        self.result = {'engine': {'release': 'build-155'}, 'version': '0.3.8', 'build': '1020'}
        self.out = self.root / 'delivery'
        ipa = self.root / 'verified.ipa'; ipa.write_bytes(b'signed fixture')
        self.proof = {'artifact': {'path': str(ipa), 'sha256': candidate.digest(ipa)}}

    def call(self, **kwargs):
        return testflight.deliver(self.result, self.out, self.root / 'profile', 'identity', self.env, **kwargs)

    def test_incomplete_configuration_never_contacts_apple(self):
        for key in self.env:
            with self.subTest(key=key), patch.dict(self.env, self.env, clear=True):
                del self.env[key]
                with patch.object(export_archive, 'export') as export, self.assertRaises(ValueError):
                    self.call()
                export.assert_not_called()

    def test_invalid_channel_groups_declaration_or_partial_key_never_falls_back(self):
        for key, value in (('HALOPAD_TESTFLIGHT_CHANNEL', 'latest'), ('HALOPAD_TESTFLIGHT_GROUPS', '[]'),
                           ('HALOPAD_TESTFLIGHT_GROUPS', '[2]'), ('HALOPAD_TESTFLIGHT_GROUPS', '"Team"'),
                           ('HALOPAD_USES_NON_EXEMPT_ENCRYPTION', ''), ('HALOPAD_API_ISSUER', '-' * 36)):
            with self.subTest(key=key), patch.dict(self.env, {key: value}), \
                    patch.object(export_archive, 'export') as export, self.assertRaises(ValueError):
                self.call()
            export.assert_not_called()
        self.assertEqual(export_archive.api_auth(), [])

    def test_failed_export_or_wrong_profile_cannot_invoke_delivery(self):
        for error in (subprocess.CalledProcessError(70, 'xcodebuild'), ValueError('profile lost memory entitlement')):
            with self.subTest(error=error), patch.object(export_archive, 'export', side_effect=error), \
                    patch.object(testflight.subprocess, 'run') as upload, self.assertRaises(type(error)):
                self.call()
            upload.assert_not_called()
            self.assertFalse((self.out / 'testflight-submission.json').exists())

    def test_changed_ipa_cannot_invoke_delivery(self):
        Path(self.proof['artifact']['path']).write_text('changed')
        with patch.object(export_archive, 'export', return_value=self.proof), \
                patch.object(testflight.subprocess, 'run') as upload, self.assertRaisesRegex(ValueError, 'changed'):
            self.call()
        upload.assert_not_called()

    def test_exact_verified_bytes_forwarded_without_keys_or_acceptance_claims(self):
        with patch.object(export_archive, 'export', return_value=self.proof) as export, \
                patch.object(testflight.subprocess, 'run') as upload:
            receipt = self.call(resume=True)
        self.assertIn('-authenticationKeyPath', export.call_args.args[-1])
        self.assertTrue(export.call_args.kwargs['require_notices'])
        request = json.loads((self.out / 'testflight-request.json').read_text())
        self.assertEqual(request['sha256'], self.proof['artifact']['sha256'])
        self.assertEqual(request['build'], '1020')
        self.assertTrue(request['resume'])
        self.assertTrue(request['uses_non_exempt_encryption'])
        self.assertNotIn('private fixture', json.dumps(receipt))
        self.assertNotIn('api_key', json.dumps(receipt))
        self.assertFalse(receipt['apple_review_approved'])
        self.assertFalse(receipt['consumer_upgrade'])
        self.assertEqual(upload.call_args.kwargs['timeout'], 3600)

    def test_upload_failure_leaves_request_but_no_success_receipt(self):
        with patch.object(export_archive, 'export', return_value=self.proof), \
                patch.object(testflight.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'bundle')), \
                self.assertRaises(subprocess.CalledProcessError):
            self.call()
        self.assertTrue((self.out / 'testflight-request.json').exists())
        self.assertFalse((self.out / 'testflight-submission.json').exists())

    def test_export_passes_explicit_api_key_and_verifies_before_returning(self):
        self.out.mkdir()
        options = self.out / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps({'teamID': 'TEAM'}))
        auth = testflight.settings(self.env)['auth']
        with patch.object(export_archive, 'prepare', return_value=(self.out / 'app.xcarchive', options)), \
                patch.object(export_archive.subprocess, 'run') as run, \
                patch.object(export_archive, 'verify_export', return_value=self.proof) as verify:
            self.assertEqual(export_archive.export(self.result, self.out, self.root / 'profile', 'identity', auth), self.proof)
        self.assertEqual(run.call_args.args[0][-len(auth):], auth)
        verify.assert_called_once_with(self.result, self.out / 'export', 'TEAM', require_notices=False)


class KeychainTests(unittest.TestCase):
    def test_cli_refuses_to_change_a_personal_macs_keychains(self):
        result = subprocess.run([sys.executable, str(Path(ci_signing.__file__)), 'prepare'],
                                env={**os.environ, 'GITHUB_ACTIONS': 'false'}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('restricted to a disposable GitHub-hosted runner', result.stderr)

    def test_setup_failure_is_cleanable_and_restores_the_original_search_list(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            env = {'RUNNER_TEMP': folder, 'GITHUB_ENV': str(root / 'env'), 'HALOPAD_SIGNING_P12_PASSWORD': 'sensitive-marker'}
            for key in ('HALOPAD_SIGNING_P12_BASE64', 'HALOPAD_PROFILE_BASE64', 'HALOPAD_API_KEY_BASE64'):
                env[key] = base64.b64encode(b'private-fixture').decode()
            def run(argv):
                if argv[1] == 'list-keychains': return '"/original/login.keychain-db"\n'
                if argv[1] == 'create-keychain': Path(argv[-1]).touch()
                if argv[1] == 'import': raise RuntimeError('fixture import failure')
                return ''
            with patch.object(ci_signing, 'run', side_effect=run), self.assertRaises(RuntimeError):
                ci_signing.prepare(env)
            env.update(line.split('=', 1) for line in (root / 'env').read_text().splitlines())
            signing = Path(env['HALOPAD_SIGNING_DIR'])
            self.assertEqual((signing / 'api-key.p8').stat().st_mode & 0o777, 0o600)
            self.assertNotIn('private-fixture', (root / 'env').read_text())
            with patch.object(ci_signing, 'run') as cleanup:
                ci_signing.cleanup(env)
            self.assertIn(['security', 'list-keychains', '-d', 'user', '-s', '/original/login.keychain-db'],
                          [c.args[0] for c in cleanup.call_args_list])
            self.assertFalse(signing.exists())

    def test_command_failure_never_reports_password_or_tool_output(self):
        with patch.object(ci_signing.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, 'secret', 'secret')), \
                self.assertRaises(RuntimeError) as caught:
            ci_signing.run(['security', 'import', '-P', 'secret'])
        self.assertNotIn('secret', str(caught.exception))

    def test_cleanup_rejects_non_runner_directory(self):
        with self.assertRaisesRegex(ValueError, 'unexpected'), patch.object(ci_signing, 'run') as run:
            ci_signing.cleanup({'RUNNER_TEMP': '/tmp/runner', 'HALOPAD_SIGNING_DIR': '/Users/someone/Library'})
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
