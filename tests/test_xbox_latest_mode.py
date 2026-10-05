"""The builder's attempt at OpenCE's newest release (HALOPAD_XBOX_LATEST=1)."""
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
        with mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}), \
                mock.patch.object(guest, '_latest_hash', lambda revision, path: 'f' * 64):
            identity = guest.identity('render-camera-v1', UNREVIEWED)
        self.assertEqual(identity['upstream_renderer_sha256'], 'f' * 64)
        self.assertEqual(identity['upstream_camera_sha256'], 'f' * 64)
        self.assertIs(identity['reviewed'], False)
        # the recipe (what HaloPad changes) is the same as for a reviewed build
        reviewed = guest.identity('render-camera-v1', '13c14df95c63156429e96a9694bb9cecd0379228')
        self.assertEqual(identity['recipe_sha256'], reviewed['recipe_sha256'])

    def test_latest_still_requires_every_anchor(self):
        with mock.patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '1'}):
            with self.assertRaises(ValueError):
                border_sampling.adapt_shader(b'no anchors here')
            with self.assertRaises(ValueError):
                profile_input.adapt(profile_input.INPUT, b'no anchors here')


if __name__ == '__main__':
    unittest.main()
