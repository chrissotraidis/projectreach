"""Run the real Bash 3.2 builder with inert tools: update failures must not ship a fallback."""
import hashlib
import os
import pathlib
import signal
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class BuilderUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name).resolve()
        self.work = 'generated/srw/custom-en-1.0.10.0621/run-cached'
        source = (ROOT / 'scripts/builder/build.sh').read_text().replace(
            '150e430dc54ffb265cbe96605ef8909c9ba0065fa11bdbf170bfd88391cf98ba',
            hashlib.sha256(b'fixture').hexdigest()).replace('/opt/homebrew/opt/llvm/bin/clang', 'clang')
        self.write('scripts/builder/build.sh', source)
        self.write('input/HaloCESetup.exe', 'fixture')
        self.write('input/product-key.txt', 'inert fixture')
        self.write('ref/inputs/custom-original/haloce.exe', 'fixture')
        self.write('config/profiles/custom-en-1.0.10.0621.json',
                   '{"accepted_sha256":"' + hashlib.sha256(b'fixture').hexdigest() + '"}')
        self.write(self.work + '/.builder', '')
        self.write(self.work + '/haloce.ll', 'translation')
        self.write('bin/unused', '#!/bin/sh\nexit 0\n')
        for tool in ('xcodebuild', '7zz', 'wine', 'winetricks', 'lld-link', 'clang', 'cmake', 'ninja', 'ld.lld', 'git', 'curl', 'hdiutil'):
            (self.root / 'bin' / tool).symlink_to('unused')
        self.write('.venv/bin/python', '#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' "$@"\n')
        # The inert backends below do not translate a game. Satisfy only the
        # builder's dependency probe, without installing packages in a test.
        for module in ('pefile', 'capstone', 'SCons'):
            self.write(f'probe_modules/{module}.py', '')
        self.write('scripts/extract-reference-components.py', '')
        self.write('scripts/product-id.sh', '#!/bin/sh\ncat >/dev/null\n')
        self.write('scripts/bootstrap-sources.sh', '#!/bin/sh\necho unexpected-translation >&2\nexit 90\n')
        self.write('scripts/builder/pc_cache.py',
                   f'import sys\nif sys.argv[1] == "lookup": print({self.work!r})\n')
        self.write('scripts/xbox/release.py', '''import json, os, sys
if os.environ.get('FAIL_RESOLVE'): sys.exit(17)
pinned = '--pinned' in sys.argv
print(json.dumps({'revision': ('1' if pinned else '2') * 40,
                  'release': 'build-125' if pinned else 'build-129',
                  'channel': 'pinned' if pinned else 'latest'}))
''')
        self.write('scripts/xbox/build-ios.sh', '''#!/bin/sh
printf '%s %s %s\n' "$XBOX_REV" "$HALOPAD_XBOX_LATEST" "$1" >> calls
[ -z "$FAIL_ENGINE" ] || exit 19
''')
        self.write('scripts/build-ios-app.py', f'''import pathlib
p = pathlib.Path({self.work!r}) / 'app/HaloPad.app'
p.mkdir(parents=True)
(p / 'fixture').write_text('new app')
print('built', p)
''')
        self.write('scripts/prepare-game-data.py', '''import os, pathlib, sys
if os.environ.get('FAIL_PACKAGE'): sys.exit(23)
pathlib.Path(sys.argv[sys.argv.index('--output') + 1]).write_text('new game package')
''')
        self.write('bin/ditto', '#!/bin/sh\nfor last; do :; done\nprintf "new archive" > "$last"\n')
        self.write('result.zip', 'old archive')
        self.write('result.zip.data/Halo-CE.halopad.zip', 'old game package')

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        path.chmod(0o700)

    def run_builder(self, mac=True, selected=None, **env):
        environment = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                           PYTHONPATH=str(self.root / 'probe_modules'),
                           FAIL_ENGINE='', HALOPAD_XBOX_PINNED='0')
        environment.update(env)
        return subprocess.run(['/bin/bash', str(self.root / 'scripts/builder/build.sh'),
                               str(selected or self.root / 'input'), '--xbox', *(['--mac'] if mac else []),
                               '--zip', str(self.root / 'result.zip')], cwd=self.root,
                              env=environment, text=True, capture_output=True, timeout=30)

    def assert_old_outputs(self):
        self.assertEqual((self.root / 'result.zip').read_text(), 'old archive')
        self.assertEqual((self.root / 'result.zip.data/Halo-CE.halopad.zip').read_text(), 'old game package')

    def test_latest_reuses_pc_and_retains_cached_run(self):
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'calls').read_text(), '2' * 40 + ' 1 --mac\n')
        self.assertTrue((self.root / self.work / 'haloce.ll').is_file())
        self.assertIn('reusing verified Custom Edition', result.stdout)
        self.assertIn('Xbox engine packaged: build-129', result.stdout)
        self.assertEqual((self.root / 'result.zip').read_text(), 'new archive')

    def test_resolution_failure_stops_before_engine_or_output_changes(self):
        result = self.run_builder(FAIL_RESOLVE='1')
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        self.assertFalse((self.root / 'calls').exists())
        self.assert_old_outputs()

    def test_engine_failure_never_builds_or_reports_a_fallback(self):
        result = self.run_builder(FAIL_ENGINE='1')
        self.assertEqual(result.returncode, 19, result.stdout + result.stderr)
        self.assertEqual(len((self.root / 'calls').read_text().splitlines()), 1)
        self.assertNotIn('Done.', result.stdout)
        self.assertFalse((self.root / self.work / 'app').exists())
        self.assert_old_outputs()

    def test_packaging_failure_keeps_old_downloads(self):
        result = self.run_builder(FAIL_PACKAGE='1')
        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self.assert_old_outputs()
        self.assertFalse(list(self.root.glob('.halopad-package.*')))

    def test_app_publish_failure_restores_previous_game_package(self):
        self.write('bin/mv', '''#!/bin/sh
case "$*" in *app.zip*) exit 29 ;; esac
exec /bin/mv "$@"
''')
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Done.', result.stdout)
        self.assert_old_outputs()
        self.assertFalse(list(self.root.glob('.halopad-package.*')))

    def test_output_directory_is_rejected_without_publishing(self):
        (self.root / 'result.zip').unlink()
        (self.root / 'result.zip').mkdir()
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(list((self.root / 'result.zip').iterdir()), [])
        self.assertEqual((self.root / 'result.zip.data/Halo-CE.halopad.zip').read_text(), 'old game package')

    def test_first_app_publish_failure_leaves_no_partial_game_package(self):
        (self.root / 'result.zip').unlink()
        (self.root / 'result.zip.data/Halo-CE.halopad.zip').unlink()
        self.write('bin/mv', '''#!/bin/sh
case "$*" in *app.zip*) exit 29 ;; esac
exec /bin/mv "$@"
''')
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'result.zip').exists())
        self.assertFalse((self.root / 'result.zip.data/Halo-CE.halopad.zip').exists())

    def test_failed_restore_preserves_backup_and_reports_its_location(self):
        self.write('bin/mv', '''#!/bin/sh
case "$*" in *app.zip*|'-f '*previous-game.zip*) exit 29 ;; esac
exec /bin/mv "$@"
''')
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Could not restore the previous game package', result.stderr)
        backups = list(self.root.glob('.halopad-package.*/previous-game.zip'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'old game package')
        self.assertIn(str(backups[0].parent), result.stderr)
        self.assertEqual((self.root / 'result.zip').read_text(), 'old archive')

    def test_interruption_after_backup_move_restores_previous_outputs(self):
        self.write('bin/mv', '''#!/bin/sh
/bin/mv "$@" || exit $?
case "$*" in *previous-game.zip) kill -TERM "$PPID" ;; esac
''')
        result = self.run_builder()
        self.assertIn(result.returncode, (-signal.SIGTERM, 128 + signal.SIGTERM))
        self.assert_old_outputs()
        self.assertFalse(list(self.root.glob('.halopad-package.*')))

    def test_interruption_after_app_move_keeps_both_completed_outputs(self):
        self.write('bin/mv', '''#!/bin/sh
/bin/mv "$@" || exit $?
case "$*" in *app.zip*) kill -TERM "$PPID" ;; esac
''')
        result = self.run_builder()
        self.assertIn(result.returncode, (-signal.SIGTERM, 128 + signal.SIGTERM))
        self.assertEqual((self.root / 'result.zip').read_text(), 'new archive')
        self.assertEqual((self.root / 'result.zip.data/Halo-CE.halopad.zip').read_text(), 'new game package')
        self.assertFalse(list(self.root.glob('.halopad-package.*')))

    def test_explicit_pin_overrides_inherited_latest_revision(self):
        result = self.run_builder(HALOPAD_XBOX_PINNED='1', XBOX_REV='3' * 40, HALOPAD_XBOX_LATEST='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'calls').read_text(), '1' * 40 + ' 0 --mac\n')
        self.assertIn('may not join current OpenCE games', result.stdout)

    def test_device_target_still_packages_an_ipa(self):
        result = self.run_builder(mac=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'calls').read_text(), '2' * 40 + ' 1 --device\n')
        self.assertEqual((self.root / 'result.zip').read_bytes()[:2], b'PK')

    def test_selected_patch_explains_which_file_to_choose_before_network_lookup(self):
        (self.root / 'input/HaloCESetup.exe').unlink()
        self.write('input/haloce-patch-1.0.10.exe', 'patch fixture')
        result = self.run_builder(selected=self.root / 'input/haloce-patch-1.0.10.exe', FAIL_RESOLVE='1')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('patch is a different file', result.stderr)
        self.assertIn('select HaloCESetup.exe', result.stderr)
        self.assertFalse((self.root / 'calls').exists())
        self.assert_old_outputs()

    def test_original_with_wrong_hash_is_not_accepted_just_by_filename(self):
        self.write('input/HaloCESetup.exe', 'unsupported original fixture')
        result = self.run_builder()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('supported checksum', result.stderr)
        self.assert_old_outputs()

    def test_cache_miss_runs_normal_translation_and_keeps_the_new_work(self):
        self.write('scripts/builder/pc_cache.py', '')
        self.write('scripts/bootstrap-sources.sh', '#!/bin/sh\nexit 0\n')
        self.write('scripts/build-lifter.sh', '#!/bin/sh\necho "BUILT: fixture-tool"\n')
        fresh = 'generated/srw/custom-en-1.0.10.0621/run-fresh'
        self.write('scripts/srw-pipeline.sh', f'''#!/bin/sh
echo "$3" >> translations
mkdir -p {fresh}
echo fixture > {fresh}/haloce.ll
''')
        self.write('scripts/va-model.py', '')
        # The real selection should point packaging at this new run.
        self.write('scripts/build-ios-app.py', '''import pathlib, sys
p = pathlib.Path(sys.argv[sys.argv.index('--work') + 1]) / 'app/HaloPad.app'
p.mkdir(parents=True)
print('built', p)
''')
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'translations').read_text().splitlines(),
                         ['haloce', 'keystone', 'ksimeui', 'controls', 'msxml4'])
        self.assertTrue((self.root / fresh / '.builder').exists())
        self.assertTrue((self.root / fresh / 'app/HaloPad.app').is_dir())


if __name__ == '__main__':
    unittest.main()
