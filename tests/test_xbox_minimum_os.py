"""The packaged app and final link must require the Xbox synchronization APIs."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('minimum_os_builder', ROOT / 'scripts/build-ios-app.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class MinimumOSTests(unittest.TestCase):
    def test_final_compile_target_depends_on_actual_xbox_inclusion(self):
        for flag, base in (('--mac', builder.MAC_TARGET), ('--iphoneos', builder.DEVICE_TARGET),
                           (None, builder.TARGET)):
            for xbox in (False, True):
                with self.subTest(flag=flag, xbox=xbox), tempfile.TemporaryDirectory() as folder:
                    root = Path(folder)
                    with patch.object(builder, 'ROOT', root), \
                            patch.object(builder, 'xbox_parts', return_value=['xbox-library'] if xbox else []), \
                            patch.object(builder.run_core, 'build', return_value=(root / 'exe', None)) as compile_, \
                            patch.object(builder, 'package', return_value=root / 'HaloPad.app'), \
                            patch.object(builder.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '/sdk\n')), \
                            patch.dict(os.environ, {}, clear=False), \
                            patch.object(sys, 'argv', ['builder', '--work', str(root), *([flag] if flag else [])]):
                        self.assertEqual(builder.main(), 0)
                    expected = base.replace('ios17.0', 'ios17.4') if xbox else base
                    self.assertEqual(compile_.call_args.args[1], expected)

    def test_real_package_plist_and_icon_minimum_match_included_engine(self):
        for target in (builder.TARGET, builder.DEVICE_TARGET, builder.MAC_TARGET):
            for xbox in (False, True):
                with self.subTest(target=target, xbox=xbox), tempfile.TemporaryDirectory() as folder:
                    root = Path(folder)
                    def write(name, content=b'fixture'):
                        path = root / name
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(content)
                        return path
                    exe = write('exe')
                    image = write('analysis/image.bin')
                    (image.parent / 'modules').mkdir()
                    (root / 'ref/inputs/reference-machine').mkdir(parents=True)
                    write('config/runtime/registry-machine.txt')
                    write('config/profiles/custom-en-1.0.10.0621.json', json.dumps(
                        {'original_root': 'original', 'modules': {}}).encode())
                    write('original/MANIFEST.json', b'{}')
                    write('config/xbox-engine.lock.json', b'{"revision":"fixture"}')
                    write('port/ios/assets/ChooserBackground.png', b'background fixture')
                    write('xbox/halo_guest.elf')
                    write('xbox/brokers.txt')
                    write('xbox/build.json', b'{"revision":"fixture","guest_adaptation":{"name":"none"}}')
                    out = root / 'output'; out.mkdir()
                    def run(argv, **kwargs):
                        if 'actool' in argv:
                            Path(argv[argv.index('--output-partial-info-plist') + 1]).write_bytes(plistlib.dumps({}))
                        return subprocess.CompletedProcess(argv, 0)
                    with patch.object(builder, 'ROOT', root), patch.object(builder, 'XBOX_OUT', root / 'xbox'), \
                            patch.object(builder.run_core, 'IMAGE', image), \
                            patch.object(builder, 'xbox_parts', return_value=['xbox-library'] if xbox else []), \
                            patch.object(builder, 'xbox_build_folder', return_value=root / 'xbox'), \
                            patch.object(builder, 'xbox_release_tag', return_value='build-132'), \
                            patch.object(builder, 'create_identity', return_value={}), \
                            patch.object(builder.subprocess, 'run', side_effect=run) as commands:
                        app = builder.package(exe, out, root, target)
                    mac = 'macabi' in target
                    resources = app / 'Contents/Resources' if mac else app
                    self.assertEqual((resources / 'ChooserBackground.png').exists(), xbox)
                    if xbox:
                        self.assertEqual((resources / 'ChooserBackground.png').read_bytes(), b'background fixture')
                    info = plistlib.loads((app / 'Contents/Info.plist' if mac else app / 'Info.plist').read_bytes())
                    self.assertEqual(info['DTPlatformName'], 'macosx' if mac else ('iphonesimulator' if 'simulator' in target else 'iphoneos'))
                    expected = ('14.4' if xbox else '14.0') if mac else ('17.4' if xbox else '17.0')
                    self.assertEqual(info['LSMinimumSystemVersion' if mac else 'MinimumOSVersion'], expected)
                    icon = next(call.args[0] for call in commands.call_args_list if 'actool' in call.args[0])
                    self.assertEqual(icon[icon.index('--minimum-deployment-target') + 1], expected)


if __name__ == '__main__':
    unittest.main()
