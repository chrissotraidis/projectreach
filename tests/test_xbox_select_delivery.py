"""Unchanged builds do not allocate a signing runner or hide broken handoffs."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import select_delivery


class SelectionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.out = Path(temp.name)
        self.event = {'workflow_run': {'id': 123, 'run_attempt': 2, 'run_number': 14, 'head_sha': 'a' * 40}}
        self.tag = 'halopad-candidate-0.3.8-1014'

    def select(self):
        return select_delivery.select('workflow_run', self.event, '', self.out)

    def jobs(self, conclusion='success', status='completed'):
        return json.dumps([{'jobs': [{'name': 'delivery-tests', 'status': 'completed', 'conclusion': 'success'},
                                               {'name':'select','status':'completed','conclusion':'success'}]},
                           {'jobs': [{'name': 'build', 'status': status, 'conclusion': conclusion}]}])

    def test_skipped_build_needs_no_artifact_or_download(self):
        with patch.object(select_delivery.subprocess, 'check_output', return_value=self.jobs('skipped')) as api, \
                patch.object(select_delivery.subprocess, 'run') as download:
            self.assertEqual(self.select(), {'ready': 'false', 'tag': '', 'commit': 'a' * 40})
        download.assert_not_called()
        self.assertIn('/attempts/2/jobs?', api.call_args.args[0][2])

    def test_success_selects_report_tag_and_exact_producer_commit(self):
        (self.out / 'private-handoff.json').write_text(json.dumps({'tag': self.tag}))
        with patch.object(select_delivery.subprocess, 'check_output', return_value=self.jobs()), \
                patch.object(select_delivery.subprocess, 'run') as download:
            self.assertEqual(self.select(), {'ready': 'true', 'tag': self.tag, 'commit': 'a' * 40})
        self.assertIn('halopad-build-report-14', download.call_args.args[0])

    def test_retained_build_resumes_incomplete_delivery_without_rebuilding(self):
        (self.out/'selection.json').write_text(json.dumps({'build':False,'candidate':self.tag,'commit':'b'*40}))
        for done in (False, True):
            with self.subTest(done=done), \
                    patch.object(select_delivery.subprocess,'check_output',return_value=self.jobs('skipped')), \
                    patch.object(select_delivery.subprocess,'run') as download, \
                    patch.object(select_delivery.publish_ipa,'completed',return_value=done) as completion:
                result=select_delivery.select('workflow_run',self.event,'',self.out,resume_retained=True,publish=True)
                self.assertEqual(result,{'ready':str(not done).lower(),'tag':self.tag,'commit':'b'*40})
                self.assertIn('halopad-selection-14-2',download.call_args.args[0])
                completion.assert_called_once_with(self.tag,'b'*40,publish=True)

    def test_disabled_upstream_schedule_does_not_require_a_selection_report(self):
        jobs=json.loads(self.jobs('skipped'))
        jobs[0]['jobs'][1]['conclusion']='skipped'
        with patch.object(select_delivery.subprocess,'check_output',return_value=json.dumps(jobs)), \
                patch.object(select_delivery.subprocess,'run') as download, \
                patch.object(select_delivery.publish_ipa,'completed') as completion:
            result=select_delivery.select('workflow_run',self.event,'',self.out,resume_retained=True)
            self.assertEqual(result['ready'],'false')
            download.assert_not_called();completion.assert_not_called()

    def test_missing_or_invalid_retry_selection_stops(self):
        with patch.object(select_delivery.subprocess,'check_output',return_value=self.jobs('skipped')), \
                patch.object(select_delivery.subprocess,'run'), self.assertRaises(FileNotFoundError):
            select_delivery.select('workflow_run',self.event,'',self.out,resume_retained=True)
        (self.out/'selection.json').write_text(json.dumps({'build':True,'candidate':self.tag,'commit':'b'*40}))
        with patch.object(select_delivery.subprocess,'check_output',return_value=self.jobs('skipped')), \
                patch.object(select_delivery.subprocess,'run'), self.assertRaises(ValueError):
            select_delivery.select('workflow_run',self.event,'',self.out,resume_retained=True)

    def test_failed_incomplete_missing_or_ambiguous_build_cannot_deliver(self):
        data = json.loads(self.jobs())
        data[-1]['jobs'] *= 2
        for response in (self.jobs('failure'), self.jobs('cancelled'), self.jobs(None, 'in_progress'),
                         '[{"jobs": []}]', json.dumps(data)):
            with self.subTest(response=response), \
                    patch.object(select_delivery.subprocess, 'check_output', return_value=response), \
                    patch.object(select_delivery.subprocess, 'run') as download, self.assertRaises(ValueError):
                self.select()
            download.assert_not_called()

    def test_success_without_handoff_is_an_error_not_an_unchanged_skip(self):
        with patch.object(select_delivery.subprocess, 'check_output', return_value=self.jobs()), \
                patch.object(select_delivery.subprocess, 'run'), self.assertRaises(FileNotFoundError):
            self.select()

    def test_api_and_download_failures_are_not_silent_skips(self):
        with patch.object(select_delivery.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(1, 'gh')), \
                self.assertRaises(subprocess.CalledProcessError):
            self.select()
        with patch.object(select_delivery.subprocess, 'check_output', return_value=self.jobs()), \
                patch.object(select_delivery.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'gh')), \
                self.assertRaises(subprocess.CalledProcessError):
            self.select()

    def test_manual_retry_validates_tag_without_producer_lookup(self):
        with patch.object(select_delivery.subprocess, 'check_output') as api:
            self.assertEqual(select_delivery.select('workflow_dispatch', {}, self.tag, self.out),
                             {'ready': 'true', 'tag': self.tag, 'commit': ''})
            for tag in ('', '--latest', self.tag + '\nready=true', None):
                with self.subTest(tag=tag), self.assertRaises(ValueError):
                    select_delivery.select('workflow_dispatch', {}, tag, self.out)
        api.assert_not_called()


if __name__ == '__main__':
    unittest.main()
