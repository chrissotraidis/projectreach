"""Exercise ANGLE launcher wiring without fetching, mounting or compiling."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ('C', 'CXX', 'OBJCXX')
STOP_BEFORE_BUILD = 73


class AngleCompilerCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='halopad-angle-cache-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        script_dir = self.root / 'scripts/xbox'
        script_dir.mkdir(parents=True)
        self.script = script_dir / 'build-ios.sh'
        shutil.copyfile(ROOT / 'scripts/xbox/build-ios.sh', self.script)
        (script_dir / 'build_lock.py').write_text('raise SystemExit(0)\n')
        self.executable(script_dir / 'prepare.sh', '#!/bin/sh\n: > "$TEST_PREPARE_MARKER"\n')
        (self.root / 'config').mkdir()
        revision = 'a' * 40
        (self.root / 'config/xbox-angle.lock.json').write_text(json.dumps({'revision': revision}))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.executable(self.bin / 'git', '#!' + sys.executable + '\nimport sys\n'
                        'if "rev-parse" in sys.argv: print(' + repr(revision) + ')\n'
                        'elif "status" not in sys.argv: raise SystemExit(90)\n')
        self.executable(self.bin / 'xcrun', '#!/bin/sh\n'
                        '[ "$3" = --show-sdk-path ] || exit 91\nprintf "/fixture/SDK\\n"\n')
        self.executable(self.bin / 'cmake', '#!' + sys.executable + '\nimport json, os, sys\n'
                        'with open(os.environ["TEST_CMAKE_LOG"], "a") as stream:\n'
                        '    stream.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                        'if "--build" in sys.argv: raise SystemExit(' + str(STOP_BEFORE_BUILD) + ')\n')
        self.cache = self.root / 'compiler cache'
        self.executable(self.cache, '#!/bin/sh\nexit 92\n')
        self.log = self.root / 'cmake.jsonl'
        self.marker = self.root / 'prepared'

    @staticmethod
    def executable(path, text):
        path.write_text(text)
        path.chmod(0o755)

    def run_script(self, sdk, launcher=None):
        self.log.unlink(missing_ok=True)
        self.marker.unlink(missing_ok=True)
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ.get('PATH', ''),
                   HALOPAD_XBOX_RENDERER='angle-metal', HALOPAD_XBOX_GUEST_ADAPTATION='network-policy-v1',
                   XBOX_ANGLE_SOURCE=str(self.root / 'angle'), TEST_CMAKE_LOG=str(self.log),
                   TEST_PREPARE_MARKER=str(self.marker))
        env.pop('HALOPAD_ANGLE_CCACHE', None)
        if launcher is not None:
            env['HALOPAD_ANGLE_CCACHE'] = str(launcher)
        # Explicit empty arguments must also override ambient CMake defaults.
        for language in LANGUAGES:
            env['CMAKE_' + language + '_COMPILER_LAUNCHER'] = '/stale/launcher'
        options = {'mac': ['--mac'], 'ios': ['--device'], 'simulator': []}[sdk]
        result = subprocess.run(['/bin/sh', str(self.script), *options], env=env,
                                capture_output=True, text=True)
        commands = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, commands

    def check_launchers(self, commands, expected):
        self.assertEqual(len(commands), 2)
        configure, build = commands
        self.assertEqual(build[0], '--build')
        for language in LANGUAGES:
            prefix = '-DCMAKE_' + language + '_COMPILER_LAUNCHER='
            self.assertEqual([arg for arg in configure if arg.startswith(prefix)], [prefix + expected])
        self.assertFalse(any('LAUNCHER' in arg for arg in build))

    def test_opt_in_sets_all_three_launchers_for_each_sdk(self):
        for sdk in ('mac', 'ios', 'simulator'):
            with self.subTest(sdk=sdk):
                result, commands = self.run_script(sdk, self.cache)
                self.assertEqual(result.returncode, STOP_BEFORE_BUILD, result.stderr)
                self.check_launchers(commands, str(self.cache))

    def test_unset_or_empty_explicitly_clears_previous_launcher(self):
        for sdk in ('mac', 'ios', 'simulator'):
            for value in (None, ''):
                with self.subTest(sdk=sdk, value=value):
                    result, _ = self.run_script(sdk, self.cache)
                    self.assertEqual(result.returncode, STOP_BEFORE_BUILD, result.stderr)
                    result, commands = self.run_script(sdk, value)
                    self.assertEqual(result.returncode, STOP_BEFORE_BUILD, result.stderr)
                    self.check_launchers(commands, '')

    def test_opt_in_changes_no_other_cmake_configuration(self):
        for sdk in ('mac', 'ios', 'simulator'):
            with self.subTest(sdk=sdk):
                _, cached = self.run_script(sdk, self.cache)
                _, plain = self.run_script(sdk)
                without_launchers = lambda command: [arg for arg in command if '_COMPILER_LAUNCHER=' not in arg]
                self.assertEqual(without_launchers(cached[0]), without_launchers(plain[0]))

    def test_invalid_executable_fails_before_prepare_or_cmake(self):
        non_executable = self.root / 'not-executable'
        non_executable.write_text('not executable')
        for path in (self.root / 'missing', self.root, non_executable, 'relative-ccache'):
            with self.subTest(path=path):
                result, commands = self.run_script('mac', path)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('HALOPAD_ANGLE_CCACHE', result.stderr)
                self.assertEqual(commands, [])
                self.assertFalse(self.marker.exists())

    def test_cmake_list_or_generator_expression_is_not_an_executable_path(self):
        for name in ('ccache;other', 'ccache$<1:other>'):
            with self.subTest(name=name):
                path = self.root / name
                self.executable(path, '#!/bin/sh\nexit 0\n')
                result, commands = self.run_script('ios', path)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('literal executable path', result.stderr)
                self.assertEqual(commands, [])
                self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
