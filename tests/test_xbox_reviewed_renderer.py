"""Reviewed upstream renderer selection must not relabel historic builds."""
import hashlib
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import guest_adaptation as guest

REV74 = '80d30410c8db28f4008b92f4e012a1b046ece14e'
REV85 = 'c3adcfe5bf917922d732f2551341b1ad00977867'
REV73 = 'd1c7243cb20eab4488efa1266e259b1f4d5240f6'
REV66 = 'f2ba71d9af4c6fc65d7419cc22e8f4899b16da88'
REV206 = '8102e711c353068d22d62efe6bf67ebc8a90a22e'
REV208 = 'f90d95552797039383049c1f8f79a35ddbe98b2d'
REV244 = '6ec42856d73e258e5a8c7e9cd19161f46d89d0e4'
REV273 = '7fb941b0b205edb1f7ecbb0aa6c2d7f5b884732d'


class ReviewedRendererTests(unittest.TestCase):
    def test_historical_identity_and_new_input_are_distinct(self):
        old = guest.identity('render-present-v1', REV66)
        self.assertEqual(old, guest.identity('render-present-v1', REV73))
        self.assertEqual(old['upstream_renderer_sha256'],
                         '5c8c132048b1efaa57d322b9c8a0ef65df07c1755df653c0f1a178ce96831cc6')
        self.assertEqual(old['recipe_sha256'],
                         '0b2ccebc00d023a9b665c979393dc6f51e582d8f0be2f0f15cc171102d94e3f8')
        new = guest.identity('render-present-v1', REV74)
        self.assertNotEqual(new['upstream_renderer_sha256'], old['upstream_renderer_sha256'])
        self.assertEqual(new['recipe_sha256'], old['recipe_sha256'])
        self.assertEqual(guest.identity('none', REV74), {'name': 'none'})

    def test_build85_has_its_own_reviewed_renderer_and_same_recipe(self):
        rev74 = guest.identity('render-present-v1', REV74)
        rev85 = guest.identity('render-present-v1', REV85)
        self.assertEqual(rev74['upstream_renderer_sha256'],
                         'ad03056fbbce7162e044622fdd17ee0b307706c26844ca5605aed803bdb77ab8')
        self.assertEqual(rev85['upstream_renderer_sha256'],
                         'ff150104be97062027b6a65939218bff1b10e202f1b65e4a5a7504c12b5dd99d')
        self.assertEqual(rev85['recipe_sha256'], rev74['recipe_sha256'])

    def test_build206_pins_new_renderer_camera_and_recipe_without_latest_mode(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '0'}):
            reviewed = guest.identity('render-camera-v1', REV206)
        self.assertEqual(reviewed['upstream_renderer_sha256'], guest.border_sampling.GLES_RENDERER_SHA256)
        self.assertEqual(reviewed['upstream_camera_sha256'],
                         'c65fa8916f7a40e8c77f7fa4a56138b8402a9ca13e7bb068e09660174ec4d16a')
        self.assertNotEqual(reviewed['recipe_sha256'], guest.identity('render-camera-v1', REV85)['recipe_sha256'])
        self.assertNotIn('reviewed', reviewed)  # No unreviewed-release marker.
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}):
            self.assertEqual(reviewed, guest.identity('render-camera-v1', REV206))

    def test_build208_reuses_unchanged_adaptation_without_latest_mode(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '0'}), \
             patch.object(guest, '_latest_source', side_effect=AssertionError('must use reviewed inputs')):
            for name in ('render-camera-v1', 'network-policy-v1'):
                self.assertEqual(guest.identity(name, REV208), guest.identity(name, REV206))
                self.assertNotIn('reviewed', guest.identity(name, REV208))

    def test_build273_pins_its_shader_without_relabeling_build244(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '0'}), \
             patch.object(guest, '_latest_source', side_effect=AssertionError('must use reviewed inputs')):
            old = guest.identity('network-policy-v1', REV244)
            new = guest.identity('network-policy-v1', REV273)
        self.assertEqual(old['recipe_sha256'],
                         '2c9d2b3b064db3831b3897152fe95bd76cd10eca1547bcb095ecf705dbd15137')
        self.assertEqual(new['upstream_renderer_sha256'],
                         'ab6721446effb99ad96e4b90782f217142fb2994d6fac341770ff004d17db080')
        self.assertEqual(guest.border_sampling.shader_hash(new['upstream_renderer_sha256']),
                         '2a5d0ccb8786b85f596934d062f1d4200b3d0866542bbb127a54f47bad06c0cc')
        self.assertEqual(new['upstream_camera_sha256'], old['upstream_camera_sha256'])
        self.assertNotEqual(new['recipe_sha256'], old['recipe_sha256'])
        self.assertNotIn('reviewed', new)
        # Both revisions require the newer layout, including the render-target
        # filtering exclusion and the newer-server count in the network policy.
        for recipe in (guest.scale_recipe, guest.filtering_recipe,
                       guest.counting_recipe, guest.presentation_recipe):
            self.assertEqual(recipe(new['upstream_renderer_sha256']),
                             recipe(old['upstream_renderer_sha256']))

    def test_environment_and_default_pin_select_same_identity(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {}, clear=True):
            lock = pathlib.Path(tmp) / 'lock.json'
            lock.write_text(json.dumps({'revision': REV74}))
            with patch.object(guest, 'ENGINE_LOCK', lock):
                self.assertEqual(guest.identity('render-present-v1'), guest.identity('render-present-v1', REV74))
                with patch.dict(os.environ, {'XBOX_REV': REV73}):
                    self.assertEqual(guest.identity('render-present-v1'), guest.identity('render-present-v1', REV73))

    def test_revision_hash_and_transaction_identity_cannot_be_interchanged(self):
        original = b'/* synthetic reviewed74 */\n' + guest.ANCHOR
        digest = hashlib.sha256(original).hexdigest()
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(guest.REVIEWED_RENDERERS, {REV74: digest}), \
             patch.dict(os.environ, {'XBOX_REV': REV74}):
            root = pathlib.Path(tmp)
            path = root / guest.RENDERER
            path.parent.mkdir(parents=True)
            path.write_bytes(original)
            identity = guest.identity('render-scale-v1')
            self.assertIn(guest.INSERT, guest.adapted_source(original))
            with guest.renderer_adaptation(root, identity):
                self.assertIn(guest.INSERT, path.read_bytes())
            self.assertEqual(path.read_bytes(), original)
            for revision in (REV73, 'unknown-future-revision'):
                with patch.dict(os.environ, {'XBOX_REV': revision}):
                    with self.assertRaisesRegex(ValueError, 'input changed'):
                        guest.adapted_source(original)
                    with self.assertRaisesRegex(ValueError, 'identity differs'):
                        with guest.renderer_adaptation(root, identity):
                            self.fail('must reject before mutation')
            path.write_bytes(original + b'concurrent upstream edit')
            with self.assertRaisesRegex(ValueError, 'input changed'):
                with guest.renderer_adaptation(root, identity):
                    self.fail('unreviewed bytes')
            self.assertEqual(path.read_bytes(), original + b'concurrent upstream edit')


if __name__ == '__main__':
    unittest.main()
