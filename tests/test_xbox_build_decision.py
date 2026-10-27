"""Execute the workflow's actual decision script without a runner or device."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]


def decision_script():
    workflow = (ROOT / '.github/workflows/halopad-build.yml').read_text()
    step = workflow.split('      - name: Finalize build decision\n', 1)[1].split('      - name:', 1)[0]
    return textwrap.dedent(step.split('        run: |\n', 1)[1])


class BuildDecisionTests(unittest.TestCase):
    def decide(self, selection, hit):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'selection.json').write_text(json.dumps(selection))
            subprocess.run(['bash', '-e', '-c', decision_script()], cwd=root, check=True,
                           env={**os.environ, 'FAILED_BEFORE':hit,
                                'GITHUB_OUTPUT':str(root/'output'), 'GITHUB_STEP_SUMMARY':str(root/'summary')})
            return (json.loads((root/'selection.json').read_text()), (root/'output').read_text(),
                    (root/'summary').read_text() if (root/'summary').exists() else '')

    def test_failure_hit_skips_and_preserves_resolved_engine(self):
        selected={'build':True,'record':{'release':'build-157','revision':'a'*40},'candidate':'','commit':''}
        result, output, summary = self.decide(selected, 'true')
        self.assertEqual(result,{**selected,'build':False,'reason':'previous-build-failure'})
        self.assertEqual(output,'build=false\n')
        self.assertIn('engine=upstream',summary)

    def test_missing_evicted_or_bypassed_cache_allows_build(self):
        selected={'build':True,'record':{'release':'build-157'},'candidate':'','commit':''}
        for hit in ('', 'false'):
            result, output, summary = self.decide(selected, hit)
            self.assertEqual(result,selected)
            self.assertEqual(output,'build=true\n')
            self.assertFalse(summary)

    def test_retained_success_wins_over_old_failure_and_keeps_delivery_identity(self):
        selected={'build':False,'record':{},'candidate':'halopad-candidate-0.3.8-22','commit':'a'*40}
        result, output, summary = self.decide(selected, 'true')
        self.assertEqual(result,selected)
        self.assertEqual(output,'build=false\n')
        self.assertFalse(summary)

    def test_network_skip_wins_over_old_failure(self):
        selected = {'build': False, 'record': {'release': 'build-295', 'revision': 'a' * 40},
                    'candidate': '', 'commit': '', 'reason': 'same-network-version',
                    'network': {'current': 39, 'upstream': 39}}
        result, output, summary = self.decide(selected, 'true')
        self.assertEqual(result, selected)
        self.assertEqual(output, 'build=false\n')
        self.assertFalse(summary)


class WorkflowRoutingTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/halopad-build.yml').read_text()
        self.selection = self.workflow.split('  select:\n', 1)[1].split('  build:\n', 1)[0]

    def evaluate(self, expression, event, *, engine='', enabled='', repository='chrissotraidis/projectreach'):
        # These workflow expressions use only boolean operators, strings, and
        # property lookups, whose truthiness is identical for this input matrix.
        expression = expression.replace('&&', ' and ').replace('||', ' or ')
        context = {
            'github': SimpleNamespace(repository=repository, event_name=event, ref='refs/heads/main',
                event=SimpleNamespace(workflow_run=SimpleNamespace(conclusion='success', head_branch='main',
                    head_repository=SimpleNamespace(full_name=repository)))),
            'inputs': SimpleNamespace(engine=engine),
            'vars': SimpleNamespace(HALOPAD_CANDIDATES_ENABLED=enabled, HALOPAD_IPA_PUBLISH_ENABLED=enabled),
        }
        return eval(expression, {'__builtins__': {}}, context)

    def test_main_push_is_pinned_and_manual_upstream_remains_explicit(self):
        channel = re.search(r'ENGINE_CHANNEL: \$\{\{ (.*?) \}\}', self.selection)[1]
        for event, engine, expected in (('push', '', 'release'), ('workflow_dispatch', '', 'release'),
                                        ('workflow_dispatch', 'release', 'release'),
                                        ('workflow_dispatch', 'upstream', 'upstream'),
                                        ('schedule', '', 'upstream'), ('repository_dispatch', '', 'upstream')):
            with self.subTest(event=event, engine=engine):
                self.assertEqual(self.evaluate(channel, event, engine=engine), expected)

    def test_private_candidate_opt_in_gates_both_automatic_events(self):
        condition = self.selection.split('    if: ', 1)[1].splitlines()[0]
        for event in ('schedule', 'repository_dispatch'):
            for enabled in ('', 'false', 'true'):
                with self.subTest(event=event, enabled=enabled):
                    self.assertEqual(self.evaluate(condition, event, enabled=enabled), enabled == 'true')
        for event in ('push', 'workflow_dispatch'):
            self.assertTrue(self.evaluate(condition, event))
        self.assertFalse(self.evaluate(condition, 'schedule', enabled='true', repository='someone/fork'))
        self.assertNotIn('HALOPAD_PREVIEW_ENABLED', self.workflow)

    def test_only_automatic_selection_passes_network_and_retained_gates(self):
        automatic = re.search(r'SKIP_RETAINED: \$\{\{ (.*?) \}\}', self.selection)[1]
        step = self.selection.split('      - name: Resolve engine once and skip completed upstream work\n', 1)[1]
        script = textwrap.dedent(step.split('        run: |\n', 1)[1].split('      - name:', 1)[0])
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            checker = root / 'scripts/xbox/check_update.py'
            checker.parent.mkdir(parents=True)
            checker.write_text('import json,sys\nprint(json.dumps(sys.argv[1:]))\n')
            for event in ('push', 'workflow_dispatch', 'schedule', 'repository_dispatch'):
                with self.subTest(event=event):
                    gated = self.evaluate(automatic, event)
                    subprocess.run(['bash', '-e', '-c', script], cwd=root, check=True,
                                   env={**os.environ, 'ENGINE_CHANNEL': 'upstream',
                                        'PATH': str(Path(sys.executable).parent) + os.pathsep + os.environ.get('PATH', ''),
                                        'SKIP_RETAINED': str(gated).lower()})
                    args = json.loads((root/'selection.json').read_text())
                    self.assertEqual('--network-change-only' in args, event in ('schedule', 'repository_dispatch'))
                    self.assertEqual('--skip-retained' in args, event in ('schedule', 'repository_dispatch'))

    def test_delivery_tests_only_run_when_a_build_is_selected(self):
        job = self.workflow.split('  delivery-tests:\n', 1)[1].split('  select:\n', 1)[0]
        self.assertIn('    needs: select\n', job)
        self.assertIn("    if: needs.select.outputs.build == 'true'\n", job)

    def test_automatic_ipa_delivery_is_disabled_without_public_opt_in(self):
        workflow = (ROOT / '.github/workflows/halopad-ipa.yml').read_text()
        condition = workflow.split('    if: >-\n', 1)[1].split('    runs-on:', 1)[0]
        condition = ' '.join(condition.splitlines())
        for enabled in ('', 'false', 'true'):
            with self.subTest(enabled=enabled):
                self.assertEqual(self.evaluate(condition, 'workflow_run', enabled=enabled), enabled == 'true')
                self.assertTrue(self.evaluate(condition, 'workflow_dispatch', enabled=enabled))


if __name__ == '__main__':
    unittest.main()
