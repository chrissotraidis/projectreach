"""Exercise the metadata failure with Apple's real signer, without game inputs."""
import importlib.util
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('signing_builder', ROOT / 'scripts/build-ios-app.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class BuiltAppSigningTests(unittest.TestCase):
    def test_cleanup_failure_stops_before_signing(self):
        with patch.object(builder.subprocess, 'run',
                          side_effect=subprocess.CalledProcessError(1, 'xattr')) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                builder.sign_built_app(pathlib.Path('generated/HaloPad.app'))
        self.assertEqual(run.call_count, 1)

    @unittest.skipUnless(sys.platform == 'darwin', 'requires Apple codesign and xattr')
    def test_dirty_bundle_signs_and_round_trips_without_changing_source(self):
        with tempfile.TemporaryDirectory(prefix='halopad signing ') as folder:
            root = pathlib.Path(folder)
            source = root / 'source.txt'
            source.write_text('Harmless resource fixture.\n')
            subprocess.run(['xattr', '-wx', 'com.apple.FinderInfo',
                            (b'TEXTttxt' + bytes(24)).hex(), str(source)], check=True)
            app = root / 'HaloPad.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            resources = app / 'Contents/Resources'
            resources.mkdir()
            # Use a system Mach-O as inert fixture code; never launch it.
            exe = app / 'Contents/MacOS/HaloPad'
            shutil.copyfile('/usr/bin/true', exe)
            exe.chmod(0o755)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'dev.halopad.signing-test',
                'CFBundleExecutable': 'HaloPad', 'CFBundlePackageType': 'APPL'}))
            resource = resources / source.name
            shutil.copyfile(source, resource)
            # Model metadata added by Finder/sync after the resource is copied.
            subprocess.run(['xattr', '-wx', 'com.apple.FinderInfo',
                            (b'TEXTttxt' + bytes(24)).hex(), str(resource)], check=True)
            subprocess.run(['xattr', '-w', 'com.apple.ResourceFork', 'fixture', str(resource)], check=True)
            source.chmod(0o444)
            resource.chmod(0o444)
            failed = subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(app)],
                                    capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('resource fork, Finder information', failed.stderr)

            entitlements = root / 'entitlements.plist'
            entitlements.write_bytes(plistlib.dumps(builder.MAC_ENTITLEMENTS))
            builder.sign_built_app(app, entitlements=entitlements)
            self.assertEqual(resource.read_bytes(), source.read_bytes())
            self.assertEqual(source.stat().st_mode & 0o777, 0o444)
            self.assertIn('com.apple.FinderInfo', subprocess.check_output(['xattr', str(source)], text=True))
            signed_entitlements = subprocess.check_output(
                ['codesign', '--display', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL)
            self.assertEqual(plistlib.loads(signed_entitlements), builder.MAC_ENTITLEMENTS)

            archive = root / 'app.zip'
            subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent',
                            str(app), str(archive)], check=True)
            unpacked = root / 'unpacked'
            subprocess.run(['ditto', '-x', '-k', str(archive), str(unpacked)], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict',
                            str(unpacked / 'HaloPad.app')], check=True)
