"""A failed asset catalog compile must not throw away a finished HaloPad build (padmint#220)."""
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('icon_fallback_builder', ROOT / 'scripts/build-ios-app.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
real_run = subprocess.run


def actool_aborts(argv, *args, **kwargs):
    if argv[:2] == ['xcrun', 'actool']:
        return subprocess.CompletedProcess(argv, -6, b'', b'actool: CoreSimulator is out of date')
    return real_run(argv, *args, **kwargs)


@unittest.skipUnless(shutil.which('sips') and shutil.which('iconutil'), 'needs macOS sips and iconutil')
class IconFallbackTests(unittest.TestCase):
    def test_mac_app_gets_an_icns_when_actool_aborts(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(builder.subprocess, 'run', actool_aborts):
            res = Path(folder)
            info = builder.compile_icon(res, res, builder.MAC_TARGET, '14.4')
            self.assertEqual(info, {'CFBundleIconFile': 'AppIcon'})
            self.assertGreater((res / 'AppIcon.icns').stat().st_size, 0)
            self.assertFalse((res / 'AppIcon.iconset').exists())
            plistlib.dumps(info)

    def test_iphone_and_ipad_get_png_icons_when_actool_aborts(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(builder.subprocess, 'run', actool_aborts):
            app = Path(folder)
            info = builder.compile_icon(app, app, builder.DEVICE_TARGET, '17.4')
            for name, _size in builder.PLAIN_IOS_ICONS:
                self.assertTrue((app / name).is_file(), name)
            self.assertEqual(info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconFiles'], ['AppIcon60x60'])
            self.assertIn('AppIcon83.5x83.5', info['CFBundleIcons~ipad']['CFBundlePrimaryIcon']['CFBundleIconFiles'])

    def test_a_working_actool_is_still_used(self):
        def actool_works(argv, *args, **kwargs):
            partial = Path(argv[argv.index('--output-partial-info-plist') + 1])
            partial.write_bytes(plistlib.dumps({'CFBundleIconName': 'AppIcon'}))
            return subprocess.CompletedProcess(argv, 0, b'', b'')
        with tempfile.TemporaryDirectory() as folder, patch.object(builder.subprocess, 'run', actool_works):
            out = Path(folder)
            self.assertEqual(builder.compile_icon(out, out, builder.MAC_TARGET, '14.4'), {'CFBundleIconName': 'AppIcon'})


if __name__ == '__main__':
    unittest.main()
