"""A stale or rejected Xbox candidate must not silently enter an app build."""
import hashlib
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('ios_builder', ROOT / 'scripts/build-ios-app.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
PIN = json.loads((ROOT / 'config/xbox-engine.lock.json').read_text())['revision']


class XboxManifestTests(unittest.TestCase):
    def test_requested_xbox_cannot_silently_make_a_pc_only_app(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch.dict(os.environ, {'HALOPAD_XBOX': 'on', 'HALOPAD_XBOX_GUEST_ADAPTATION': 'none'}), \
                patch.object(builder, 'xbox_build_folder', return_value=pathlib.Path(folder)), \
                self.assertRaisesRegex(ValueError, 'refusing a PC-only app'):
            builder.xbox_parts(builder.MAC_TARGET)

    def test_resolved_release_survives_deleted_upstream_tag(self):
        with patch.dict(os.environ, {'XBOX_REV': '2' * 40, 'HALOPAD_XBOX_RELEASE': 'build-129'}), \
                patch.object(builder.subprocess, 'run', side_effect=AssertionError('must not re-resolve')):
            self.assertEqual(builder.xbox_release_tag('2' * 40), 'build-129')

    def test_resolved_release_cannot_relabel_a_different_revision(self):
        with patch.dict(os.environ, {'XBOX_REV': '2' * 40, 'HALOPAD_XBOX_RELEASE': 'build-129'}):
            expected = json.loads((ROOT / 'config/xbox-engine.lock.json').read_text())['release']
            self.assertEqual(builder.xbox_release_tag(PIN), expected)

    def test_presentation_requires_matching_backend_and_simulator(self):
        self.test_counted_candidate_requires_matching_guest_backend_and_simulator('render-present-v1')

    def test_input_requires_matching_backend_and_simulator(self):
        self.test_counted_candidate_requires_matching_guest_backend_and_simulator('shared-input-v1')

    def test_border_requires_matching_backend_and_simulator(self):
        self.test_counted_candidate_requires_matching_guest_backend_and_simulator('render-border-v1')

    def test_water_requires_matching_backend_and_simulator(self):
        self.test_counted_candidate_requires_matching_guest_backend_and_simulator('render-water-v1')

    def test_counted_candidate_requires_matching_guest_backend_and_simulator(self, adaptation='render-visibility-v1'):
        self.angle_fixture()
        self.lib = self.out / 'iphonesimulator-angle-counted/libhalopad-xbox.a'
        self.lib.parent.mkdir()
        self.lib.write_bytes(b'fixture library, not game code')
        self.manifest['guest_adaptation'] = builder.xbox_runtime_manifest.guest_adaptation.identity(adaptation)
        identity = {'name': 'counted-visibility-v1', 'recipe_sha256': 'fixture recipe'}
        metadata = self.out / 'angle-counted-simulator/counted-visibility-v1/identity.json'
        metadata.parent.mkdir(parents=True)
        metadata.write_text(json.dumps(identity))
        self.save_manifest()
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': adaptation}):
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                builder.xbox_parts(builder.TARGET)
            self.manifest['visibility_backend'] = identity
            self.save_manifest()
            self.assertIn(self.lib, builder.xbox_parts(builder.TARGET))
            # A device build needs its own counted library; the Simulator one never substitutes.
            with self.assertRaisesRegex(ValueError, 'library is missing'):
                builder.xbox_parts(builder.DEVICE_TARGET)
            with patch.dict(os.environ, {'HALOPAD_XBOX_RENDERER': 'apple-gles'}):
                with self.assertRaisesRegex(ValueError, 'ANGLE renderer'):
                    builder.xbox_parts(builder.TARGET)
            metadata.write_text(json.dumps({'name': 'counted-visibility-v1', 'recipe_sha256': 'different'}))
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                builder.xbox_parts(builder.TARGET)

    def test_counted_backend_rejected_for_plain_guest(self):
        self.manifest['visibility_backend'] = {'name': 'counted-visibility-v1'}
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'explicit guest'):
            builder.xbox_parts(builder.TARGET)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.out = pathlib.Path(self.temp.name)
        self.lib = self.out / 'iphonesimulator/libhalopad-xbox.a'
        self.lib.parent.mkdir()
        self.lib.write_bytes(b'fixture library, not game code')
        self.guest = self.out / 'halo_guest.elf'
        self.guest.write_bytes(b'fixture guest, not game code')
        self.manifest = {
            'revision': PIN,
            'sdk': 'iphonesimulator',
            'guest_sha256': hashlib.sha256(self.guest.read_bytes()).hexdigest(),
            'guest_adaptation': {'name': 'none'},
            'library_sha256': hashlib.sha256(self.lib.read_bytes()).hexdigest(),
            'runtime_sources': builder.xbox_runtime_manifest.sources(),
        }
        self.save_manifest()
        self.addCleanup(patch.stopall)
        patch.object(builder, 'XBOX_OUT', self.out).start()
        patch.dict(os.environ, {}, clear=True).start()

    def save_manifest(self):
        (self.lib.parent / 'build.json').write_text(json.dumps(self.manifest))

    def test_pc_only_without_local_library(self):
        self.assertEqual(builder.xbox_parts(builder.DEVICE_TARGET), [])

    def test_exact_pin(self):
        self.assertIn(self.lib, builder.xbox_parts(builder.TARGET))

    def test_adaptation_requires_explicit_opt_in(self):
        self.manifest['guest_adaptation'] = builder.xbox_runtime_manifest.guest_adaptation.identity('render-scale-v1')
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'adaptation differs'):
            builder.xbox_parts(builder.TARGET)
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-scale-v1'}):
            self.assertIn(self.lib, builder.xbox_parts(builder.TARGET))

    def test_missing_adaptation_identity_rejected(self):
        self.manifest.pop('guest_adaptation')
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'adaptation differs'):
            builder.xbox_parts(builder.TARGET)

    def test_quality_candidate_cannot_masquerade_as_scale_only(self):
        self.manifest['guest_adaptation'] = builder.xbox_runtime_manifest.guest_adaptation.identity('render-quality-v1')
        self.save_manifest()
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-scale-v1'}):
            with self.assertRaisesRegex(ValueError, 'adaptation differs'):
                builder.xbox_parts(builder.TARGET)
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-quality-v1'}):
            self.assertIn(self.lib, builder.xbox_parts(builder.TARGET))

    def test_requested_adaptation_rejects_plain_guest(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-scale-v1'}):
            with self.assertRaisesRegex(ValueError, 'adaptation differs'):
                builder.xbox_parts(builder.TARGET)

    def test_adaptation_recipe_change_rejected(self):
        self.manifest['guest_adaptation'] = builder.xbox_runtime_manifest.guest_adaptation.identity('render-scale-v1')
        self.manifest['guest_adaptation']['recipe_sha256'] = 'old recipe'
        self.save_manifest()
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-scale-v1'}):
            with self.assertRaisesRegex(ValueError, 'adaptation differs'):
                builder.xbox_parts(builder.TARGET)

    def test_unknown_adaptation_rejected_before_pc_only_fallback(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'unknown'}):
            with self.assertRaisesRegex(ValueError, 'Unknown'):
                builder.xbox_parts(builder.DEVICE_TARGET)

    def test_missing_adapted_library_rejected(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-scale-v1'}):
            with self.assertRaisesRegex(ValueError, 'Adapted Xbox library is missing'):
                builder.xbox_parts(builder.DEVICE_TARGET)

    def test_rejected_revision(self):
        self.manifest['revision'] = 'candidate'
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'revision differs'):
            builder.xbox_parts(builder.TARGET)

    def test_explicit_candidate_override(self):
        self.manifest['revision'] = 'candidate'
        self.save_manifest()
        with patch.dict(os.environ, {'XBOX_REV': 'candidate'}):
            self.assertIn(self.lib, builder.xbox_parts(builder.TARGET))

    def test_mismatched_guest(self):
        self.guest.write_bytes(b'different guest')
        with self.assertRaisesRegex(ValueError, 'Stale Xbox build'):
            builder.xbox_parts(builder.TARGET)

    def test_mismatched_library(self):
        self.lib.write_bytes(b'different library')
        with self.assertRaisesRegex(ValueError, 'Stale Xbox build'):
            builder.xbox_parts(builder.TARGET)

    def test_unrecorded_local_sources_requires_rebuild(self):
        self.manifest.pop('runtime_sources')
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'local sources'):
            builder.xbox_parts(builder.TARGET)

    def test_changed_disc_extractor_requires_rebuild(self):
        self.manifest['runtime_sources']['port/xbox/xg_xiso.c'] = 'old source'
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'local sources'):
            builder.xbox_parts(builder.TARGET)

    def test_legacy_library_requires_rebuild(self):
        (self.lib.parent / 'build.json').unlink()
        with self.assertRaisesRegex(ValueError, 'no build manifest'):
            builder.xbox_parts(builder.TARGET)

    def angle_fixture(self, sdk='iphonesimulator'):
        self.lib = self.out / (sdk + '-angle') / 'libhalopad-xbox.a'
        self.lib.parent.mkdir()
        self.lib.write_bytes(b'fixture library, not game code')
        self.manifest['renderer'] = 'angle-metal'
        self.manifest['sdk'] = sdk
        self.manifest['angle_feature_overrides'] = ['hasTextureSwizzle'] if sdk == 'iphonesimulator' else []
        self.manifest['angle_source'] = json.loads((ROOT / 'config/xbox-angle.lock.json').read_text())
        self.save_manifest()
        patch.dict(os.environ, {'HALOPAD_XBOX_RENDERER': 'angle-metal'}).start()

    def test_angle_links_only_requested_renderer(self):
        self.angle_fixture()
        parts = builder.xbox_parts(builder.TARGET)
        self.assertIn(self.lib, parts)
        self.assertIn('Metal', parts)
        self.assertNotIn('OpenGLES', parts)

    def test_angle_device_requires_device_archive(self):
        self.angle_fixture()
        with self.assertRaisesRegex(ValueError, 'library is missing'):
            builder.xbox_parts(builder.DEVICE_TARGET)

    def test_device_build_never_uses_simulator_launch(self):
        result = subprocess.run(['sh', str(ROOT / 'scripts/xbox/build-ios.sh'),
                                 '--device', '--launch', 'unused'],
                                env=dict(os.environ, HALOPAD_XBOX_RENDERER='angle-metal'),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('device builds are not installed', result.stderr)

    def test_angle_device_links_only_device_archive(self):
        self.angle_fixture('iphoneos')
        parts = builder.xbox_parts(builder.DEVICE_TARGET)
        self.assertIn(self.lib, parts)
        self.assertIn('Metal', parts)
        self.assertNotIn('OpenGLES', parts)

    def test_retagged_angle_archive_is_rejected(self):
        self.angle_fixture('iphoneos')
        self.manifest['sdk'] = 'iphonesimulator'
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'SDK differs'):
            builder.xbox_parts(builder.DEVICE_TARGET)

    def test_physical_angle_refuses_simulator_feature_override(self):
        self.angle_fixture('iphoneos')
        self.manifest['angle_feature_overrides'] = ['hasTextureSwizzle']
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'feature overrides differ'):
            builder.xbox_parts(builder.DEVICE_TARGET)

    def test_simulator_angle_requires_tested_feature_override(self):
        self.angle_fixture()
        self.manifest['angle_feature_overrides'] = []
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'feature overrides differ'):
            builder.xbox_parts(builder.TARGET)

    def test_sdk_identity_is_required(self):
        self.manifest.pop('sdk')
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'SDK differs'):
            builder.xbox_parts(builder.TARGET)

    def test_unknown_renderer_rejected(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_RENDERER': 'unknown'}):
            with self.assertRaisesRegex(ValueError, 'Unknown'):
                builder.xbox_parts(builder.TARGET)

    def test_missing_angle_does_not_silently_build_pc_only(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_RENDERER': 'angle-metal'}):
            with self.assertRaisesRegex(ValueError, 'library is missing'):
                builder.xbox_parts(builder.TARGET)

    def test_wrong_angle_source_rejected(self):
        self.angle_fixture()
        self.manifest['angle_source']['revision'] = 'different'
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'source differs'):
            builder.xbox_parts(builder.TARGET)

    def test_wrong_renderer_manifest_rejected(self):
        self.angle_fixture()
        self.manifest['renderer'] = 'apple-gles'
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, 'renderer differs'):
            builder.xbox_parts(builder.TARGET)


if __name__ == '__main__':
    unittest.main()
