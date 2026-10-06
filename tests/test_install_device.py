"""The device wrapper installs this build's app, never an older directory match."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallDeviceTests(unittest.TestCase):
    def run_install(self, version, platform='iPhoneOS', build_exit=0):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'scripts').mkdir()
            shutil.copy2(ROOT / 'scripts/install-device.sh', root / 'scripts/install-device.sh')
            # Leave an older device output and newer non-device outputs as decoys.
            for name in ('ios17.0', 'ios17.4-macabi', 'ios17.4-simulator'):
                (root / f'generated/srw/profile/run-old/ios-app-arm64-apple-{name}/HaloPad.app').mkdir(parents=True)
            work = root / 'custom work'
            app = work / f'ios-app-arm64-apple-ios{version}/HaloPad.app'
            app.mkdir(parents=True)
            (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleSupportedPlatforms': [platform]}))
            (root / 'game').mkdir()
            (root / 'profile').touch()
            py = root / '.venv/bin/python'
            py.parent.mkdir(parents=True)
            py.write_text(f'''#!{sys.executable}
import os, sys
from pathlib import Path
name = Path(sys.argv[1]).name
if name == 'build-ios-app.py':
    print('building fixture')
    print('built ' + os.environ['TEST_APP'])
    sys.exit(int(os.environ['TEST_BUILD_EXIT']))
elif name == 'prepare-game-data.py':
    Path(os.environ['TEST_PREPARE']).write_text(sys.argv[sys.argv.index('--app-data') + 1])
elif name != 'device_profile.py':
    os.execv(sys.executable, [sys.executable, *sys.argv[1:]])
''')
            py.chmod(0o755)
            xcrun = py.parent / 'xcrun'
            xcrun.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_INSTALL"\n')
            xcrun.chmod(0o755)
            env = dict(os.environ, PATH=f'{py.parent}:{os.environ["PATH"]}',
                       TEST_APP=str(app.relative_to(root)), TEST_PREPARE=str(root / 'prepared'),
                       TEST_INSTALL=str(root / 'installed'), TEST_BUILD_EXIT=str(build_exit))
            result = subprocess.run(['/bin/bash', str(root / 'scripts/install-device.sh'),
                                     '--identity', 'fixture', '--profile', str(root / 'profile'),
                                     '--device', 'fixture', '--game', str(root / 'game'), '--work', str(work)],
                                    env=env, capture_output=True, text=True)
            if platform == 'iPhoneOS' and not build_exit:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((root / 'prepared').read_text(), str(app / 'data'))
                self.assertIn(str(app), (root / 'installed').read_text())
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / 'prepared').exists())
                self.assertFalse((root / 'installed').exists())

    def test_current_device_build_selected_for_both_minimums(self):
        for version in ('17.0', '17.4'):
            with self.subTest(version=version):
                self.run_install(version)

    def test_non_device_build_is_rejected_before_install(self):
        self.run_install('17.4-simulator', 'iPhoneSimulator')

    def test_failed_build_does_not_install_reported_path(self):
        self.run_install('17.4', build_exit=1)

    def run_prebuilt(self, edition, package=False, sign_exit=0):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'scripts').mkdir()
            shutil.copy2(ROOT / 'scripts/install-device.sh', root / 'scripts/install-device.sh')
            app = root / 'input with spaces/HaloPad.app'
            (app / 'data').mkdir(parents=True)
            if edition in ('pc', 'combined'):
                (app / 'data/core-identity.json').write_text('fixture')
            if edition in ('xbox', 'combined', 'incomplete'):
                (app / 'data/xbox').mkdir()
                for name in ('build.json', 'halo_guest.elf', 'brokers.txt'):
                    if edition != 'incomplete' or name != 'halo_guest.elf':
                        (app / 'data/xbox' / name).write_text('fixture')
            (root / 'profile').touch()
            py = root / '.venv/bin/python'
            py.parent.mkdir(parents=True)
            py.write_text(f'''#!{sys.executable}
import os, sys
from pathlib import Path
name = Path(sys.argv[1]).name
if name == 'sign-app.py':
    Path(os.environ['TEST_SIGNED']).write_text(sys.argv[2])
    sys.exit(int(os.environ['TEST_SIGN_EXIT']))
if name != 'device_profile.py':
    sys.exit('unexpected build or package step: ' + name)
''')
            py.chmod(0o755)
            xcrun = py.parent / 'xcrun'
            xcrun.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_INSTALL"\n')
            xcrun.chmod(0o755)
            arguments = []
            if package:
                path = root / 'matching.halopad.zip'
                path.write_text('fixture')
                arguments = ['--package', str(path)]
            env = dict(os.environ, PATH=f'{py.parent}:{os.environ["PATH"]}',
                       TEST_SIGNED=str(root / 'signed'), TEST_SIGN_EXIT=str(sign_exit),
                       TEST_INSTALL=str(root / 'installed'), TMPDIR=str(root))
            result = subprocess.run(['/bin/bash', str(root / 'scripts/install-device.sh'),
                                     '--identity', 'fixture', '--profile', str(root / 'profile'),
                                     '--device', 'fixture', '--app', str(app), *arguments],
                                    env=env, capture_output=True, text=True)
            success = (edition == 'xbox' or package) and not sign_exit
            if success:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                staged = Path((root / 'signed').read_text())
                self.assertNotEqual(staged, app)
                installed = (root / 'installed').read_text()
                self.assertIn('device install app --device fixture ' + str(staged), installed)
                self.assertEqual('device copy to' in installed, package)
                self.assertIn('Choose Prepared Package' if package else 'Add Your Xbox Disc', result.stdout)
                self.assertEqual(sorted(p.relative_to(app) for p in app.rglob('*')),
                                 sorted(p.relative_to(staged) for p in staged.rglob('*')))
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / 'installed').exists())

    def test_xbox_only_installs_without_pc_package(self):
        self.run_prebuilt('xbox')

    def test_pc_and_combined_still_need_matching_package(self):
        for edition in ('pc', 'combined'):
            with self.subTest(edition=edition):
                self.run_prebuilt(edition)
                self.run_prebuilt(edition, package=True)

    def test_incomplete_xbox_app_cannot_skip_package(self):
        self.run_prebuilt('incomplete')

    def test_failed_xbox_signing_does_not_install(self):
        self.run_prebuilt('xbox', sign_exit=1)


if __name__ == '__main__':
    unittest.main()
