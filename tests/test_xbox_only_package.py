"""Xbox-only packages never read or include the player's PC translation or key."""
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('xbox_only_app', ROOT / 'scripts/build-ios-app.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class XboxOnlyPackageTests(unittest.TestCase):
    def test_device_and_mac_packages_need_no_pc_inputs(self):
        for target in ('arm64-apple-ios17.4', 'arm64-apple-ios17.4-macabi'):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as folder:
                root = pathlib.Path(folder)
                engine = root / 'engine'
                engine.mkdir()
                (engine / 'halo_guest.elf').write_bytes(b'inert guest fixture')
                (engine / 'brokers.txt').write_text('fixture.invalid')
                (engine / 'build.json').write_text(json.dumps({'revision': 'a' * 40,
                    'guest_adaptation': {'name': 'none'}, 'renderer': 'angle-metal'}))
                exe = root / 'executable'
                exe.write_bytes(b'inert executable')
                with patch.object(builder, 'XBOX_OUT', engine), \
                        patch.object(builder, 'xbox_parts', return_value=['fixture-engine']), \
                        patch.object(builder, 'xbox_build_folder', return_value=engine), \
                        patch.object(builder, 'xbox_release_tag', return_value='build-132'), \
                        patch.object(builder, 'compile_icon', return_value={}), \
                        patch.object(builder.run_core, 'IMAGE', root / 'nonexistent-PC-data'), \
                        patch.object(builder, 'create_identity', side_effect=AssertionError('PC identity read')), \
                        patch.object(builder.subprocess, 'run'):
                    app = builder.package(exe, root / 'out', root, target, pc=False)
                resources = app / 'Contents/Resources' if 'macabi' in target else app
                self.assertEqual({str(p.relative_to(resources / 'data')) for p in (resources / 'data').rglob('*') if p.is_file()},
                                 {'xbox/halo_guest.elf', 'xbox/brokers.txt', 'xbox/build.json'})

    def test_xbox_only_cannot_silently_omit_engine_or_include_product_id(self):
        with patch.object(builder, 'xbox_parts', return_value=[]), self.assertRaises(ValueError):
            builder.package(None, None, None, pc=False)
        with patch.object(builder, 'xbox_parts', return_value=['engine']), self.assertRaises(ValueError):
            builder.package(None, None, None, product_id=pathlib.Path('private-key'), pc=False)
