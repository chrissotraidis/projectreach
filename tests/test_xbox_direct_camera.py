"""The iOS guest's direct first-person camera (render-camera-v1)."""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import guest_adaptation as guest  # noqa: E402

REV85 = 'c3adcfe5bf917922d732f2551341b1ad00977867'
GUARD = (b'static struct observer_result const *render_interpolation_direct_camera(\n'
         b'{\n' + guest.CAMERA_ANCHOR + b'\tdirect camera\n#endif\n}\n')


class DirectCameraTests(unittest.TestCase):
    def test_cumulative_with_every_earlier_fix(self):
        for group in (guest.COUNTED_ADAPTATIONS, guest.WATER_ADAPTATIONS, guest.BORDER_ADAPTATIONS,
                      guest.INPUT_ADAPTATIONS, guest.PRESENT_ADAPTATIONS):
            self.assertIn('render-camera-v1', group)

    def test_distinct_recipe_pins_reviewed_camera_source(self):
        camera = guest.identity('render-camera-v1', REV85)
        present = guest.identity('render-present-v1', REV85)
        self.assertNotEqual(camera['recipe_sha256'], present['recipe_sha256'])
        self.assertEqual(camera['upstream_camera_sha256'], guest.REVIEWED_CAMERA[REV85])
        self.assertNotIn('upstream_camera_sha256', present)

    def test_unreviewed_revision_rejected(self):
        with self.assertRaisesRegex(ValueError, 'reviewed only for builds 85 and 119'):
            guest.identity('render-camera-v1', '80d30410c8db28f4008b92f4e012a1b046ece14e')

    def test_only_the_android_guard_changes(self):
        original = guest.CAMERA_ANCHOR
        self.assertEqual(guest.CAMERA_REPLACE.count(b'#if 0'), 1)
        self.assertEqual(guest.CAMERA_REPLACE.split(b'\n', 1)[1], original.split(b'\n', 1)[1])

    def test_changed_source_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Camera adaptation input changed'):
            guest.adapted_camera(GUARD, REV85)


if __name__ == '__main__':
    unittest.main()
