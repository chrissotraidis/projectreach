"""Personal signing accepts either edition without bypassing device/profile checks."""
import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('sign_app', ROOT / 'scripts/sign-app.py')
sign_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sign_app)


class SignAppTests(unittest.TestCase):
    def run_sign(self, edition, platform='iPhoneOS', profile_error=False, check_only=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            app = root / 'HaloPad.app'
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'dev.halopad.HaloPad',
                'CFBundleSupportedPlatforms': [platform],
            }))
            files = []
            if edition in ('pc', 'combined'):
                files.append('core-identity.json')
            if edition in ('xbox', 'combined', 'incomplete'):
                files.extend('xbox/' + n for n in ('build.json', 'halo_guest.elf', 'brokers.txt'))
            if edition == 'incomplete':
                files.remove('xbox/halo_guest.elf')
            for name in files:
                path = app / 'data' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('inert fixture')
            profile = root / 'profile'
            profile.write_text('inert profile')
            entitlements = []

            def codesign(command, **kwargs):
                if '--entitlements' in command:
                    path = Path(command[command.index('--entitlements') + 1])
                    entitlements.append(plistlib.loads(path.read_bytes()))

            with patch.object(sys, 'argv', ['sign-app.py', str(app), '--identity', 'fixture', '--profile', str(profile), *(['--check-only'] if check_only else [])]), \
                    patch.object(sign_app, 'check', return_value={'get-task-allow': True}) as check, \
                    patch.object(sign_app.subprocess, 'run', side_effect=codesign) as run:
                if profile_error:
                    check.side_effect = ValueError('fixture profile rejected')
                if edition in ('empty', 'incomplete') or platform != 'iPhoneOS' or profile_error:
                    with self.assertRaises(SystemExit):
                        sign_app.main()
                    run.assert_not_called()
                    self.assertFalse((app / 'embedded.mobileprovision').exists())
                    if not profile_error:
                        check.assert_not_called()
                else:
                    sign_app.main()
                    check.assert_called_once_with(profile, 'dev.halopad.HaloPad', 'fixture')
                    if check_only:
                        run.assert_not_called()
                        self.assertFalse((app / 'embedded.mobileprovision').exists())
                        return
                    self.assertEqual(run.call_count, 2)
                    self.assertEqual((app / 'embedded.mobileprovision').read_bytes(), profile.read_bytes())
                    self.assertEqual(entitlements, [dict(sign_app.ENTITLEMENTS, **{'get-task-allow': True})])
                    self.assertEqual(run.call_args.args[0], ['codesign', '--verify', '--deep', '--strict', str(app)])

    def test_both_editions_and_xbox_only_keep_signing_checks(self):
        for edition in ('pc', 'combined', 'xbox'):
            with self.subTest(edition=edition):
                self.run_sign(edition)

    def test_rejects_incomplete_or_empty_app(self):
        for edition in ('empty', 'incomplete'):
            with self.subTest(edition=edition):
                self.run_sign(edition)

    def test_rejects_mac_and_simulator_xbox_apps(self):
        for platform in ('MacOSX', 'iPhoneSimulator'):
            with self.subTest(platform=platform):
                self.run_sign('xbox', platform=platform)

    def test_xbox_only_does_not_bypass_profile_validation(self):
        self.run_sign('xbox', profile_error=True)

    def test_check_only_validates_without_signing_or_copying_profile(self):
        self.run_sign('xbox', check_only=True)
        self.run_sign('xbox', check_only=True, profile_error=True)


if __name__ == '__main__':
    unittest.main()
