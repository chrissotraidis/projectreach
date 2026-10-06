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


if __name__ == '__main__':
    unittest.main()
