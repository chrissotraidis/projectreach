"""Resolve releases without rolling backwards on API/tag failures."""
import importlib.util
import io
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('xbox_release', ROOT / 'scripts/xbox/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
LOCK = {'url': 'https://github.com/OpenCommunityEdition/OpenCE.git',
        'revision': '1' * 40, 'release': 'build-125'}


class ReleaseTests(unittest.TestCase):
    def test_default_cli_uses_bundled_record_without_resolving_upstream(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'bundled.json'
            path.write_text(json.dumps({'revision': 'a' * 40, 'release': 'build-150'}))
            with patch.object(release, 'BUNDLED', path), patch('sys.argv', ['release.py']), \
                    patch.object(release, 'resolve', side_effect=AssertionError('upstream')), \
                    patch('sys.stdout', new_callable=io.StringIO) as output:
                self.assertEqual(release.main(), 0)
                self.assertEqual(json.loads(output.getvalue()),
                                 {'revision': 'a' * 40, 'release': 'build-150', 'channel': 'release'})

    def test_broken_bundled_record_never_falls_forward_to_latest(self):
        with patch.object(release, 'BUNDLED', pathlib.Path('/nonexistent/record')), \
                patch('sys.argv', ['release.py']), patch.object(release, 'resolve') as latest, \
                patch('sys.stderr', new_callable=io.StringIO) as error:
            self.assertEqual(release.main(), 1)
            latest.assert_not_called()
            self.assertIn('no upstream release was substituted', error.getvalue())

    def test_record_replays_exact_commit_without_network_or_git(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'record.json'
            path.write_text(json.dumps({'revision': 'a' * 40, 'release': 'build-144', 'channel': 'latest'}))
            with patch.object(release.urllib.request, 'urlopen', side_effect=AssertionError('network')), \
                    patch.object(release.subprocess, 'run', side_effect=AssertionError('git')):
                self.assertEqual(release.read_record(path),
                                 {'revision': 'a' * 40, 'release': 'build-144', 'channel': 'record'})

    def test_invalid_record_fails_instead_of_resolving_latest(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'record.json'
            for record in ([], {}, {'revision': 'main', 'release': 'build-144'},
                           {'revision': 'a' * 40, 'release': None},
                           {'revision': 'a' * 40, 'release': 'build-144\n'}):
                path.write_text(json.dumps(record))
                with self.subTest(record=record), self.assertRaises(ValueError):
                    release.read_record(path)

    def resolve(self, tag='build-129', refs=None):
        refs = refs if refs is not None else f'{"2" * 40}\trefs/tags/{tag}\n'
        with patch.object(release.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps({'tag_name': tag}).encode())), \
                patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, refs)):
            return release.resolve(LOCK)

    def test_bad_record_cli_does_not_suggest_a_different_engine(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch('sys.argv', ['release.py', '--record', str(pathlib.Path(folder) / 'missing.json')]), \
                    patch('sys.stderr', new_callable=io.StringIO) as error:
                self.assertEqual(release.main(), 1)
                self.assertIn('Correct the record', error.getvalue())
                self.assertNotIn('PINNED', error.getvalue())

    def test_lightweight_tag(self):
        self.assertEqual(self.resolve(), {'revision': '2' * 40, 'release': 'build-129', 'channel': 'latest'})

    def test_annotated_tag_uses_commit_not_tag_object(self):
        refs = f'{"3" * 40}\trefs/tags/build-129\n{"2" * 40}\trefs/tags/build-129^{{}}\n'
        self.assertEqual(self.resolve(refs=refs)['revision'], '2' * 40)

    def test_deleted_tag_is_failure(self):
        with self.assertRaises(ValueError):
            self.resolve(refs='')

    def test_unexpected_tag_is_failure(self):
        for tag in (None, {}, '--upload-pack=bad', 'build-129/other', 'build-nope'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.resolve(tag)

    def test_api_failure_is_not_a_pin_fallback(self):
        with patch.object(release.urllib.request, 'urlopen', side_effect=OSError('offline')), \
                self.assertRaisesRegex(OSError, 'offline'):
            release.resolve(LOCK)

    def test_malformed_release_metadata_is_a_failure(self):
        for body in (b'[]', b'{}', b'not json'):
            with self.subTest(body=body), \
                    patch.object(release.urllib.request, 'urlopen', return_value=io.BytesIO(body)), \
                    self.assertRaises(ValueError):
                release.resolve(LOCK)

    def test_pin_is_explicit_and_works_offline(self):
        with patch.object(release.urllib.request, 'urlopen', side_effect=AssertionError('no network')):
            self.assertEqual(release.resolve(LOCK, True),
                             {'revision': '1' * 40, 'release': 'build-125', 'channel': 'pinned'})


if __name__ == '__main__':
    unittest.main()
