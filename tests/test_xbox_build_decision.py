"""Execute the workflow's actual decision script without a runner or device."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
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


if __name__ == '__main__':
    unittest.main()
