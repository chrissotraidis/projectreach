"""Reviewed upstream renderer selection must not relabel historic builds."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
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
REV294 = '337b05cfdf203e7c3e3d8af0b1b37894c0b5b057'
REV343 = 'fc9deb0b10eaae1d62caedb0710968b4e77e6e16'


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

    def test_build294_preserves_gles_recipes_and_separates_new_browser_identity(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '0'}), \
             patch.object(guest, '_latest_source', side_effect=AssertionError('must use reviewed inputs')):
            old = guest.identity('render-camera-v1', REV273)
            new = guest.identity('render-camera-v1', REV294)
            old_network = guest.identity('network-policy-v1', REV273)
            new_network = guest.identity('network-policy-v1', REV294)
        self.assertEqual(new['upstream_renderer_sha256'],
                         '1be243e7ec92cce823051e217fba2c6ef1a90dcd4f58e6eecdeb156f480c5ba9')
        self.assertEqual(new['upstream_camera_sha256'], old['upstream_camera_sha256'])
        self.assertEqual(new['recipe_sha256'], old['recipe_sha256'])
        self.assertNotEqual(new_network['recipe_sha256'], old_network['recipe_sha256'])
        self.assertNotIn('reviewed', new_network)
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

    def test_build343_pins_changed_sources_and_keeps_the_prior_recipe(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '0'}), \
             patch.object(guest, '_latest_source', side_effect=AssertionError('must use reviewed inputs')):
            old = guest.identity('network-policy-v1', REV294)
            new = guest.identity('network-policy-v1', REV343)
        self.assertEqual(old['recipe_sha256'],
                         'af8ed3dda17acf5167c3cd8a243dda32ad4e8d589ffb6d04f15acbf384193a2b')
        self.assertEqual(new['upstream_renderer_sha256'], guest.border_sampling.GLES_343_RENDERER_SHA256)
        self.assertEqual(new['upstream_camera_sha256'],
                         'c132ab5846cc0154ea9ae5656a15437d484aef6e5dec04eb7d8c76eb1ff9f9dc')
        self.assertEqual(guest.border_sampling.shader_hash(new['upstream_renderer_sha256']),
                         '75e20e1caaa2c2206e40a11d8ddf2c6cd400d5d49dd5180dc57aefd5822a9e2b')
        self.assertNotEqual(new['recipe_sha256'], old['recipe_sha256'])
        self.assertNotIn('reviewed', new)

    def test_exact343_renderer_preserves_quality_and_new_engine_bookkeeping(self):
        checkout = pathlib.Path(os.environ.get('HALOPAD_TEST_ENGINE', guest.ENGINE_CHECKOUT))
        sources = {}
        for path in (guest.RENDERER, guest.border_sampling.SHADER, guest.CAMERA_SOURCE):
            result = subprocess.run(['git', '-C', str(checkout), 'show', f'{REV343}:{path}'],
                                    capture_output=True)
            if result.returncode:
                self.skipTest('exact OpenCE343 source unavailable; set HALOPAD_TEST_ENGINE')
            sources[path] = result.stdout
        with patch.dict(os.environ, {'XBOX_REV': REV343, 'HALOPAD_XBOX_LATEST': '0'}):
            renderer = guest.adapted_source(sources[guest.RENDERER], 'render-camera-v1')
            shader = guest.border_sampling.adapt_shader(sources[guest.border_sampling.SHADER],
                                                        guest.border_sampling.GLES_343_RENDERER_SHA256)
            camera = guest.adapted_camera(sources[guest.CAMERA_SOURCE])
        # New visibility sequence numbers, pooled/static geometry, depth and
        # first-person interpolation stay upstream's; our narrow edits survive.
        for preserved in (b'device.visibility_counted[index] = device.query_tests[index];',
                          b'web_chunks_begin_frame();', b'static_buffers_collect();'):
            self.assertIn(preserved, renderer)
        self.assertIn(b'xgpu_reversed_depth ? "1.0 - " : ""', shader)
        self.assertIn(b'FIRST_PERSON_HALF_TURN_COSINE', camera)
        self.assertIn(guest.CAMERA_REPLACE, camera)
        self.assertIn(guest.COUNT_244_REPLACE, renderer)
        self.assertIn(guest.WATER_RESTORE, renderer)
        self.assertIn(guest.PRESENT_244_REPLACE, renderer)

        # Compile the actual adapted function, not a synthetic copy. Explicit
        # native-picker values must win over every saved upstream resolution.
        choose = re.search(rb'static void screen_mode_choose\(long \*width, float scale\[2\]\)\n\{.*?\n\}',
                           renderer, re.S).group().decode()
        harness = r'''
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#define HALO_ANDROID 1
#define SCREEN_HEIGHT 480
static float screen_supersampling, selected_part;
static int maximum_target_size = 16384, drawable_calls;
static long config_integer(const char *key) { (void)key; return 0; }
static float resolution_scaling_part(void) { return selected_part; }
static void platform_video_drawable_size(int *w, int *h) {
    drawable_calls++; *w = 1920; *h = 1080;
}
''' + choose + r'''
int main(void) {
    long width;
    float scale[2];
    unsetenv("HALO_DISPLAY_WIDTH");
    for (int mode = 1; mode <= 2; mode++) {
        setenv("HALO_TEST_RENDER_SCALE", mode == 2 ? "2" : "1", 1);
        for (int setting = 0; setting <= 4; setting++) {
            selected_part = setting * 0.25f;
            screen_mode_choose(&width, scale);
            assert(width == 640 && scale[0] == mode && scale[1] == mode);
            assert(screen_supersampling == mode && drawable_calls == 0);
        }
    }
    unsetenv("HALO_TEST_RENDER_SCALE");
    selected_part = 0.0f;
    screen_mode_choose(&width, scale);
    assert(scale[0] == 1.0f && scale[1] == 1.0f && drawable_calls == 0);
    selected_part = 1.0f;
    screen_mode_choose(&width, scale);
    assert(scale[0] == 2.25f && scale[1] == 2.25f && drawable_calls == 1);
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            binary = pathlib.Path(tmp) / 'screen-quality'
            compiled = subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Werror',
                                       '-fsanitize=address,undefined', '-o', str(binary)],
                                      input=harness, text=True, capture_output=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            subprocess.run([str(binary)], check=True, capture_output=True)

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
