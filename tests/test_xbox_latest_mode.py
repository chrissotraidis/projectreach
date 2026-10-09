"""The builder's attempt at OpenCE's newest release (HALOPAD_XBOX_LATEST=1)."""
import hashlib
import os
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import border_sampling  # noqa: E402
import guest_adaptation as guest  # noqa: E402
import profile_input  # noqa: E402

UNREVIEWED = '0' * 40


class LatestModeTests(unittest.TestCase):
    def test_off_by_default_unreviewed_rejected(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop('HALOPAD_XBOX_LATEST', None)
            with self.assertRaises(ValueError):
                guest.identity('render-camera-v1', UNREVIEWED)
            with self.assertRaises(ValueError):
                border_sampling.adapt_shader(b'changed')

    def test_latest_takes_the_checkout_hashes_and_is_marked(self):
        source = b'new revision, unchanged legacy sampler layout\n'
        with mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}), \
                mock.patch.object(guest, '_latest_source', return_value=source):
            identity = guest.identity('render-camera-v1', UNREVIEWED)
        self.assertEqual(identity['upstream_renderer_sha256'], hashlib.sha256(source).hexdigest())
        self.assertEqual(identity['upstream_camera_sha256'], hashlib.sha256(source).hexdigest())
        self.assertIs(identity['reviewed'], False)
        # the recipe (what HaloPad changes) is the same as for a reviewed build
        reviewed = guest.identity('render-camera-v1', '13c14df95c63156429e96a9694bb9cecd0379228')
        self.assertEqual(identity['recipe_sha256'], reviewed['recipe_sha256'])

    def test_unrelated_edit_keeps_cached_sampler_recipe_and_placement(self):
        # Synthetic cache with the field meanings the adapter requires. A new
        # whole-file hash must not send this layout through the legacy patch.
        source = guest.ANCHOR + b'''
static void configure_sampler(int stage, BOOL mipmapped, BOOL hires)
{
\tinputs[0] = hires ? D3DTEXF_LINEAR : state[D3DTSS_MINFILTER];
\tinputs[1] = hires ? D3DTEXF_LINEAR : mipmapped ? state[D3DTSS_MIPFILTER] : D3DTEXF_NONE;
\tinputs[8] = state[D3DTSS_MAXANISOTROPY];
\tinputs[10] = hires;
\tif (!configured_sampler[stage] || memcmp(configured[stage], inputs, sizeof(inputs)))
\t\tconfigured_sampler[stage] = sampler_get(stage, inputs);
}
''' + guest.FILTER_ANCHOR
        recipes = []
        for original in (source, source + b'/* unrelated upstream edit */\n'):
            with mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1', 'XBOX_REV': UNREVIEWED}), \
                    mock.patch.object(guest, '_latest_source', return_value=original):
                identity = guest.identity('render-quality-v1')
                recipes.append(identity['recipe_sha256'])
                self.assertIs(identity['reviewed'], False)
                modified = guest.adapted_source(original, 'render-quality-v1')
                self.assertIn(guest.CACHED_FILTER_ANCHOR + guest.CACHED_FILTER_INSERT, modified)
                self.assertNotIn(guest.FILTER_INSERT, modified)
        self.assertEqual(*recipes)
        for changed in (
            source.replace(b'inputs[8]', b'inputs[7]'),
            source.replace(guest.CACHED_FILTER_ANCHOR, b''),
            source + guest.CACHED_FILTER_ANCHOR,
            source.replace(guest.CACHED_FILTER_ANCHOR, b'') + guest.CACHED_FILTER_ANCHOR,
        ):
            with self.subTest(changed=changed), \
                    mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}), \
                    mock.patch.object(guest, '_latest_source', return_value=changed):
                with self.assertRaisesRegex(ValueError, 'sampler cache layout'):
                    guest.filtering_recipe(hashlib.sha256(changed).hexdigest(), UNREVIEWED)

    def test_latest_filtering_rejects_missing_or_mismatched_source(self):
        for source in (None, b'wrong revision'):
            with mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}), \
                    mock.patch.object(guest, '_latest_source', return_value=source):
                with self.assertRaisesRegex(ValueError, 'differs from its identity'):
                    guest.filtering_recipe('f' * 64, UNREVIEWED)

    def test_latest_still_requires_every_anchor(self):
        with mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}):
            with self.assertRaises(ValueError):
                border_sampling.adapt_shader(b'no anchors here')
            with self.assertRaises(ValueError):
                profile_input.adapt(profile_input.INPUT, b'no anchors here')


if __name__ == '__main__':
    unittest.main()
