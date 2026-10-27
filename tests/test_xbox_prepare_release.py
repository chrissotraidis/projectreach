"""Recipe-only staging rejects version drift, dirty source and unsafe outputs."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import prepare_release as prep


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        for name in ('padmint.json', 'config/xbox-release.json',
                     '.github/workflows/halopad-build.yml', '.github/workflows/halopad-player-build.yml'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((ROOT / name).read_bytes())
        (self.root / '.gitignore').write_text('generated/\n')
        self.run_git('init', '-q')
        self.commit()
        self.version = json.loads((self.root / 'padmint.json').read_text())['targets']['ios']['command'][4]

    def run_git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.DEVNULL)

    def commit(self):
        self.run_git('add', '.')
        self.run_git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                     'commit', '-qm', 'fixture')

    def change(self, name, transform):
        path = self.root / name
        path.write_text(transform(path.read_text()))
        self.commit()

    def test_read_only_report_does_not_stage_or_claim_acceptance(self):
        result = prep.prepare(self.root, self.version)
        self.assertFalse((self.root / 'generated').exists())
        self.assertFalse(result['published'])
        self.assertTrue(all(x == 'not_checked' for x in result['acceptance'].values()))
        self.assertEqual(result['source']['commit'], self.run_git('rev-parse', 'HEAD').decode().strip())
        self.assertEqual(len(result['player_check_commands']['pre'][0]), 6)
        self.assertEqual(len(result['player_check_commands']['post'][0]), 5)

    def test_stages_exact_recipe_and_only_whitelisted_public_assets(self):
        out = self.root / 'generated/release-test'
        result = prep.prepare(self.root, self.version, out=out)
        name = 'HaloPad-v' + self.version + '-padmint.json'
        self.assertEqual({p.name for p in (out / 'public-assets').iterdir()}, {name, 'SHA256SUMS'})
        recipe = (self.root / 'padmint.json').read_bytes()
        self.assertEqual((out / 'public-assets' / name).read_bytes(), recipe)
        self.assertEqual((out / 'public-assets/SHA256SUMS').read_text(),
                         hashlib.sha256(recipe).hexdigest() + '  ' + name + '\n')
        self.assertEqual(json.loads((out / 'preparation.json').read_text()), result)
        self.assertFalse(self.run_git('status', '--porcelain').strip())

    def test_dirty_and_untracked_source_rejected_before_staging(self):
        for name in ('padmint.json', 'extra.txt'):
            with self.subTest(name=name):
                path = self.root / name
                original = path.read_bytes() if path.exists() else None
                path.write_text('changed')
                with self.assertRaisesRegex(ValueError, 'clean'):
                    prep.prepare(self.root, self.version, out=self.root / 'generated/fail')
                if original is None:
                    path.unlink()
                else:
                    path.write_bytes(original)
        self.assertFalse((self.root / 'generated').exists())

    def test_read_only_check_allows_dirty_development_tree(self):
        (self.root / 'development.txt').write_text('in progress')
        report = prep.prepare(self.root, self.version)
        self.assertFalse(report['source']['clean'])
        self.assertFalse((self.root / 'generated').exists())

    def test_wrong_source_commit_rejected(self):
        with self.assertRaisesRegex(ValueError, '--source'):
            prep.prepare(self.root, self.version, expected='0' * 40)

    def test_existing_and_outside_outputs_preserved(self):
        for out in (self.root, self.root / 'public', self.root / 'generated'):
            with self.subTest(out=out), self.assertRaises(ValueError):
                prep.prepare(self.root, self.version, out=out)
        out = self.root / 'generated/existing'
        out.mkdir(parents=True)
        (out / 'keep').write_text('keep')
        with self.assertRaisesRegex(ValueError, 'exists'):
            prep.prepare(self.root, self.version, out=out)
        self.assertEqual((out / 'keep').read_text(), 'keep')

    def test_symlink_output_cannot_escape_generated(self):
        (self.root / 'generated').mkdir()
        (self.root / 'generated/escape').symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'beneath'):
            prep.prepare(self.root, self.version, out=self.root / 'generated/escape/new')

    def test_recipe_target_version_drift_rejected(self):
        self.change('padmint.json', lambda s: s.replace('"--app-version", "' + self.version,
                                                       '"--app-version", "9.9.9', 1))
        with self.assertRaisesRegex(ValueError, 'recipe version'):
            prep.prepare(self.root, self.version)

    def test_comments_cannot_hide_real_workflow_version_drift(self):
        def change(text):
            return '# --app-version ' + self.version + '\n' + text.replace(
                '--app-version ' + self.version, '--app-version 9.9.9', 1)
        self.change('.github/workflows/halopad-build.yml', change)
        with self.assertRaisesRegex(ValueError, 'workflow version'):
            prep.prepare(self.root, self.version)

    def test_single_line_preparation_step_version_is_checked(self):
        name = '.github/workflows/halopad-build.yml'
        # Use a standalone fixture step regardless of the real workflow's layout.
        text = (self.root / name).read_text()
        text = '\n'.join(line for line in text.splitlines()
                         if 'python3 scripts/xbox/prepare_release.py' not in line)
        self.change(name, lambda _: text + '\n      - run: python3 scripts/xbox/prepare_release.py --version 9.9.9\n')
        with self.assertRaisesRegex(ValueError, 'preparation version'):
            prep.prepare(self.root, self.version)

    def test_cache_key_and_staging_tag_drift_rejected(self):
        path = self.root / '.github/workflows/halopad-build.yml'
        original = path.read_text()
        for old, new in [('halopad-failure-v1-' + self.version, 'halopad-failure-v1-9.9.9'),
                         ('--tag "halopad-' + self.version, '--tag "halopad-9.9.9')]:
            with self.subTest(old=old):
                self.change(str(path.relative_to(self.root)), lambda s: original.replace(old, new))
                with self.assertRaises(ValueError):
                    prep.prepare(self.root, self.version)

    def test_player_field_and_actual_arguments_checked(self):
        name = '.github/workflows/halopad-player-build.yml'
        original = (self.root / name).read_text()
        for text in (original.replace('APP_VERSION: ' + self.version, 'APP_VERSION: 9.9.9'),
                     original.replace('--app-version "$APP_VERSION"', '--app-version "9.9.9"', 1)):
            with self.subTest(text=text):
                self.change(name, lambda _: text)
                with self.assertRaises(ValueError):
                    prep.prepare(self.root, self.version)

    def test_player_step_env_and_shell_assignment_cannot_shadow_version(self):
        name = '.github/workflows/halopad-player-build.yml'
        original = (self.root / name).read_text()
        for text in (original.replace('        run: |',
                                      '        env:\n          APP_VERSION: 9.9.9\n        run: |', 1),
                     original.replace('        run: |',
                                      '        env: {APP_VERSION: 9.9.9}\n        run: |', 1),
                     original.replace('        run: |',
                                      '        run: |\n          APP_VERSION=9.9.9', 1),
                     original.replace('        run: |',
                                      '        run: |\n          export APP_VERSION=9.9.9', 1)):
            with self.subTest(text=text):
                self.change(name, lambda _: text)
                with self.assertRaisesRegex(ValueError, 'APP_VERSION'):
                    prep.prepare(self.root, self.version)

    def test_commented_version_bindings_do_not_count(self):
        self.change('.github/workflows/halopad-player-build.yml', lambda text:
                    '# APP_VERSION: 9.9.9\n# export APP_VERSION=9.9.9\n' + text)
        prep.prepare(self.root, self.version)

    def test_engine_record_format_is_validated_without_claiming_review(self):
        for revision in ('main', 'A' * 40):
            self.change('config/xbox-release.json', lambda _: json.dumps(
                {'revision': revision, 'release': 'build-999'}))
            with self.assertRaises(ValueError):
                prep.prepare(self.root, self.version)
        self.change('config/xbox-release.json', lambda _: json.dumps(
            {'revision': 'a' * 40, 'release': 'build-999'}))
        report = prep.prepare(self.root, self.version)
        self.assertEqual(report['acceptance']['upstream_and_adaptation_review'], 'not_checked')

    def test_public_binary_opt_in_is_rejected(self):
        self.change('padmint.json', lambda s: s.replace('"public_binaries": false', '"public_binaries": true'))
        with self.assertRaisesRegex(ValueError, 'prohibit'):
            prep.prepare(self.root, self.version)


if __name__ == '__main__':
    unittest.main()
