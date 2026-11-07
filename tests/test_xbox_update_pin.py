"""Execute the update script with inert build/device/Git boundaries and real save copies.

This verifies shell safety/control flow, not upstream compilation or device acceptance.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/xbox/update-pin.sh'


class UpdatePinTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='halopad-update-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.work = self.root / 'ref/xbox-build'
        self.bin = self.root / 'bin'
        self.lock = self.root / 'config/xbox-engine.lock.json'
        self.calls = self.root / 'calls.txt'
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        UPDATE_FIXTURE_ROOT=str(self.root), UPDATE_FIXTURE_CALLS=str(self.calls))
        self.write('config/xbox-engine.lock.json', json.dumps({'revision': 'old-pin'}))
        self.write('engine-state.txt', 'old-pin\n')
        shutil.copyfile(SCRIPT, self.write('scripts/xbox/update-pin.sh', ''))
        self.write('ref/xbox-build/data/save/profile New001.bin', 'synthetic Mac save\n')
        self.write('ref/xbox-build/save-ios/profile.bin', 'synthetic iOS save\n')
        self.write('sim-container/Documents/Halo Xbox/save/profile.bin', 'synthetic Simulator save\n')
        self.write('scripts/xbox/prepare.sh', '#!/bin/sh\nexit 0\n', True)
        for name in ('build-mac.sh', 'build-ios.sh'):
            self.write('scripts/xbox/' + name, '''#!/bin/sh
echo "build $XBOX_REV" >> "$UPDATE_FIXTURE_CALLS"
if [ "${UPDATE_FIXTURE_BUILD_FAIL:-}" = 1 ] && [ "$XBOX_REV" = new-pin ]; then exit 9; fi
''', True)
        for name in ('scripts/xbox/smoke-mac.py', 'scripts/xbox/smoke-simulator.py', 'scripts/build-ios-app.py'):
            self.write(name, '''import json, os, pathlib, sys
with open(os.environ["UPDATE_FIXTURE_CALLS"], "a") as f: f.write("gate\\n")
path = pathlib.Path(os.environ["UPDATE_FIXTURE_ROOT"]) / (pathlib.Path(sys.argv[0]).name + '.argv.json')
path.write_text(json.dumps(sys.argv[1:]))
''')
        self.bin.mkdir(exist_ok=True)
        (self.root / '.venv/bin').mkdir(parents=True)
        # /usr/bin/python3 is an Xcode dispatch shim: naming it "python" asks
        # current Xcode for a removed tool. Link the running interpreter itself.
        (self.root / '.venv/bin/python').symlink_to(pathlib.Path(sys.executable).resolve())
        self.write('bin/git', '''#!/bin/sh
[ "$1" = -C ] && shift 2
case "$1" in
fetch|log|diff) exit 0 ;;
rev-parse) echo new-pin ;;
checkout) echo "$3" > "$UPDATE_FIXTURE_ROOT/engine-state.txt" ;;
*) exit 80 ;;
esac
''', True)
        self.write('bin/date', '#!/bin/sh\necho 20000101-010203\n', True)
        self.write('bin/xcrun', '''#!/bin/sh
[ "$1" = simctl ] || exit 81
case "$2" in
boot|bootstatus|terminate) exit 0 ;;
get_app_container)
  [ "${UPDATE_FIXTURE_CONTAINER_FAIL:-}" = 1 ] && exit 82
  [ "${UPDATE_FIXTURE_CONTAINER_EMPTY:-}" = 1 ] && exit 0
  echo "$UPDATE_FIXTURE_ROOT/sim-container" ;;
*) exit 83 ;;
esac
''', True)
        self.write('bin/shasum', '''#!/bin/sh
[ "${UPDATE_FIXTURE_CHECKSUM_FAIL:-}" = 1 ] && exit 84
exec /usr/bin/shasum "$@"
''', True)
        self.write('bin/ditto', '''#!/bin/sh
/usr/bin/ditto "$@" || exit $?
if [ "${UPDATE_FIXTURE_COPY_CORRUPT:-}" = 1 ]; then
  printf 'corrupted synthetic copy\n' > "$2/profile New001.bin"
fi
''', True)

    def write(self, name, contents, executable=False):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        if executable:
            path.chmod(0o755)
        return path

    def run_update(self, *args, **flags):
        return subprocess.run(['sh', str(self.root / 'scripts/xbox/update-pin.sh'), *args],
                              env=dict(self.env, **flags), capture_output=True, text=True, timeout=20)

    def events(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def assert_old_pin(self):
        self.assertEqual(json.loads(self.lock.read_text())['revision'], 'old-pin')
        self.assertEqual((self.root / 'engine-state.txt').read_text().strip(), 'old-pin')

    def test_checksum_failure_stops_before_candidate_build(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept', UPDATE_FIXTURE_CHECKSUM_FAIL='1')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()

    def test_corrupt_save_copy_stops_before_candidate_build(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept', UPDATE_FIXTURE_COPY_CORRUPT='1')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()
        self.assertEqual((self.work / 'data/save/profile New001.bin').read_text(), 'synthetic Mac save\n')

    def test_unknown_simulator_container_refuses_update(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept', UPDATE_FIXTURE_CONTAINER_FAIL='1')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()

    def test_empty_simulator_container_refuses_update(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept', UPDATE_FIXTURE_CONTAINER_EMPTY='1')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()

    def test_same_second_attempts_keep_distinct_backups(self):
        for _ in range(2):
            result = self.run_update('--simulator', 'fixture-sim')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_old_pin()
        backups = [p for p in (self.work / 'save-backups').iterdir() if p.is_dir()]
        self.assertEqual(len(backups), 2)
        for folder in backups:
            self.assertEqual((folder / 'mac-data-save/profile New001.bin').read_text(), 'synthetic Mac save\n')
            self.assertEqual((folder / 'simulator-save/profile.bin').read_text(), 'synthetic Simulator save\n')
            self.assertTrue(pathlib.Path(str(folder) + '.sha256').read_text().strip())

    def test_failed_candidate_returns_to_the_pin(self):
        result = self.run_update('--simulator', 'fixture-sim', UPDATE_FIXTURE_BUILD_FAIL='1')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.events(), ['build new-pin', 'build old-pin'])
        self.assert_old_pin()

    def test_absent_mac_saves_and_empty_simulator_saves_are_valid(self):
        # Redirect the routine to a separate empty work tree, preserving fixtures.
        empty = self.root / 'empty-state'
        empty.mkdir()
        for name in ('data/save', 'save-ios'):
            (self.work / name).rename(empty / name.replace('/', '-'))
        sim_save = self.root / 'sim-container/Documents/Halo Xbox/save'
        sim_save.rename(empty / 'simulator-save')
        sim_save.mkdir()
        result = self.run_update('--simulator', 'fixture-sim', '--accept')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        backup = next(p for p in (self.work / 'save-backups').iterdir() if p.is_dir())
        self.assertTrue((backup / 'simulator-save').is_dir())
        self.assertEqual(pathlib.Path(str(backup) + '.sha256').read_text(), '')

    def test_accept_requires_explicit_simulator(self):
        result = self.run_update('--accept')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()

    def test_adapted_guest_cannot_promote_upstream_pin(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept',
                                 HALOPAD_XBOX_GUEST_ADAPTATION='render-scale-v1')
        self.assertEqual(result.returncode, 2)
        self.assertIn('unadapted guest', result.stderr)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()

    def test_service_record_guest_cannot_promote_upstream_pin(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept',
                                 HALOPAD_SERVICE_RECORD='1')
        self.assertEqual(result.returncode, 2)
        self.assertIn('unadapted guest', result.stderr)
        self.assertEqual(self.events(), [])
        self.assert_old_pin()

    def test_accept_advances_only_after_all_inert_gates(self):
        result = self.run_update('--simulator', 'fixture-sim', '--accept')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events(), ['build new-pin', 'gate', 'build new-pin', 'gate', 'gate'])
        self.assertEqual(json.loads(self.lock.read_text())['revision'], 'new-pin')
        self.assertEqual((self.root / 'engine-state.txt').read_text().strip(), 'new-pin')

    def test_update_preserves_normal_pc_entry_and_device_state(self):
        result = self.run_update('--simulator', 'fixture-sim')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args = json.loads((self.root / 'build-ios-app.py.argv.json').read_text())
        self.assertNotIn('--scene', args, 'Xbox updates must not replace the PC entry point')
        self.assertIn('--device-data', args, 'Do not redirect the PC edition to development state')
        self.assertEqual(args[args.index('--device') + 1], 'fixture-sim')
        self.assert_old_pin()


if __name__ == '__main__':
    unittest.main()
