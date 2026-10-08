"""Exercise real processes: manual and scheduled builds share an inherited lock."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuildLockTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.script = self.root / 'scripts/xbox/build_lock.py'
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / 'scripts/xbox/build_lock.py', self.script)
        self.env = {k: v for k, v in os.environ.items() if k != 'HALOPAD_XBOX_BUILD_LOCK_FD'}

    def run_locked(self, *command):
        return subprocess.run([sys.executable, str(self.script), '--', *command],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_nested_shell_builds_share_lock(self):
        result = self.run_locked('/bin/bash', '-c',
            'python3 "$1" --check && python3 "$1" -- /bin/sh -c \'python3 "$1" --check\' test "$1"',
            'test', str(self.script))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_concurrent_build_rejected_then_lock_released(self):
        holder = subprocess.Popen([sys.executable, str(self.script), '--', sys.executable,
            '-c', 'import sys; print("ready", flush=True); sys.stdin.readline()'],
            env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'ready')
            blocked = self.run_locked('/usr/bin/true')
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn('Another HaloPad build', blocked.stderr)
        finally:
            holder.communicate('\n', timeout=10)
        self.assertEqual(self.run_locked('/usr/bin/true').returncode, 0)

    def test_stale_environment_does_not_bypass_lock(self):
        self.env['HALOPAD_XBOX_BUILD_LOCK_FD'] = '99999'
        result = self.run_locked(sys.executable, str(self.script), '--check')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_child_releases_lock_and_keeps_exit_status(self):
        self.assertEqual(self.run_locked('/bin/sh', '-c', 'exit 7').returncode, 7)
        self.assertEqual(self.run_locked('/usr/bin/true').returncode, 0)


if __name__ == '__main__':
    unittest.main()
