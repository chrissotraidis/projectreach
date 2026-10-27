"""An unchanged retained engine should consume no new build or app version."""
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import check_update as check


class CheckUpdateTests(unittest.TestCase):
    def setUp(self):
        self.selected={'revision':'a'*40,'release':'build-154'}
        self.record={'schema':1,'archive_sha256':'c'*64,'candidate':{
            'status':'built-awaiting-acceptance','version':'0.3.8','build':'20',
            'source':{'tree_sha256':'b'*64,'commit':'a'*40},'engine':self.selected}}
        self.release={'draft':True,'tag_name':'halopad-candidate-0.3.8-20','target_commitish':'a'*40,'assets':[
            {'name':check.draft.ASSET,'state':'uploaded','digest':'sha256:'+'c'*64},
            {'name':check.draft.RECEIPT,'state':'uploaded','size':1024}]}

    def retained(self, **kwargs):
        with patch.object(check.draft,'asset_bytes',return_value=json.dumps(self.record).encode()):
            return check.retained(kwargs.get('selected',self.selected),kwargs.get('source_hash','b'*64),
                                  kwargs.get('version','0.3.8'),[self.release])

    def test_exact_retained_candidate_skips_and_promotion_does_not_rebuild(self):
        self.assertTrue(self.retained())
        self.release['draft']=False
        self.assertTrue(self.retained())

    def test_engine_source_or_version_change_requires_build(self):
        self.assertFalse(self.retained(selected={**self.selected,'revision':'d'*40}))
        self.assertFalse(self.retained(selected={**self.selected,'release':'build-155'}))
        self.assertFalse(self.retained(source_hash='d'*64))
        self.assertFalse(self.retained(version='0.3.9'))

    def test_partial_or_mismatched_handoff_does_not_skip(self):
        original=copy.deepcopy(self.release)
        for change in ('missing','uploading','checksum','oversized'):
            self.release=copy.deepcopy(original)
            if change=='missing':self.release['assets'].pop()
            elif change=='uploading':self.release['assets'][0]['state']='starter'
            elif change=='checksum':self.release['assets'][0]['digest']='sha256:'+'d'*64
            else:self.release['assets'][1]['size']=65536
            with self.subTest(change=change):self.assertFalse(self.retained())

    def test_failed_or_bad_receipt_does_not_skip(self):
        self.record['candidate']['status']='failed'
        self.assertFalse(self.retained())
        for data in (b'invalid',b'null',b'{}',b'{"candidate":[]}'):
            with self.subTest(data=data),patch.object(check.draft,'asset_bytes',return_value=data):
                self.assertFalse(check.retained(self.selected,'b'*64,'0.3.8',[self.release]))

    def test_access_failure_is_an_error_not_permission_to_build_repeatedly(self):
        with patch.object(check.draft,'asset_bytes',side_effect=subprocess.CalledProcessError(1,'gh')):
            with self.assertRaises(subprocess.CalledProcessError):
                check.retained(self.selected,'b'*64,'0.3.8',[self.release])


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.current = {'revision': 'a' * 40, 'release': 'build-294', 'channel': 'record'}
        self.latest = {'revision': 'b' * 40, 'release': 'build-295', 'channel': 'latest'}
        for obj, name, value in (
                (check.release, 'read_record', self.current),
                (check.release, 'resolve', self.latest),
                (check.candidate, 'product_digest', 'c' * 64),
                (check.draft, 'api', [])):
            mocker = patch.object(obj, name, return_value=value)
            setattr(self, name, mocker.start())
            self.addCleanup(mocker.stop)
        mocker = patch.object(check.network_policy, 'raw', side_effect=[
            b'#define HALO_PORT_NETWORK_VERSION 39\n',
            b'#define HALO_PORT_NETWORK_VERSION 40\n'])
        self.raw = mocker.start()
        self.addCleanup(mocker.stop)

    def automatic(self):
        return check.select('upstream', '0.3.13', skip_retained=True, network_change_only=True)

    def test_identical_commit_needs_no_headers_receipts_or_mac_build(self):
        self.resolve.return_value = self.current
        result = self.automatic()
        self.assertFalse(result['build'])
        self.assertEqual(result['reason'], 'current-engine')
        self.assertEqual(result['baseline'], self.current)
        self.raw.assert_not_called()
        self.api.assert_not_called()

    def test_same_protocol_defers_even_if_build_number_changed(self):
        self.raw.side_effect = [b'#define HALO_PORT_NETWORK_VERSION 39\n'] * 2
        result = self.automatic()
        self.assertFalse(result['build'])
        self.assertEqual(result['reason'], 'same-network-version')
        self.assertEqual(result['network'], {'current': 39, 'upstream': 39})
        self.assertEqual(result['record'], self.latest)
        self.api.assert_not_called()

    def test_new_protocol_prepares_exact_resolved_commit(self):
        result = self.automatic()
        self.assertTrue(result['build'])
        self.assertEqual(result['reason'], 'network-version-change')
        self.assertEqual(result['network'], {'current': 39, 'upstream': 40})
        self.resolve.assert_called_once()
        self.assertEqual([call.args[1] for call in self.raw.call_args_list], ['a' * 40, 'b' * 40])
        self.assertEqual(result['record'], self.latest)
        self.api.assert_called_once()

    def test_completed_protocol_candidate_is_reused(self):
        previous = {'version': '0.3.13', 'build': '1100', 'source': {'commit': 'd' * 40}}
        with patch.object(check, 'retained_candidate', return_value=previous):
            result = self.automatic()
        self.assertFalse(result['build'])
        self.assertEqual(result['reason'], 'retained-candidate')
        self.assertEqual(result['candidate'], 'halopad-candidate-0.3.13-1100')
        self.assertEqual(result['commit'], 'd' * 40)
        self.assertEqual(result['network']['upstream'], 40)

    def test_manual_upstream_can_build_same_protocol_without_gate_or_dedup(self):
        result = check.select('upstream', '0.3.13')
        self.assertTrue(result['build'])
        self.assertEqual(result['record'], self.latest)
        self.raw.assert_not_called()
        self.api.assert_not_called()

    def test_source_validation_builds_pin_without_upstream_lookup(self):
        result = check.select('release', '0.3.13')
        self.assertTrue(result['build'])
        self.assertEqual(result['record'], self.current)
        self.resolve.assert_not_called()
        self.raw.assert_not_called()

    def test_network_gate_cannot_suppress_pinned_source_validation(self):
        with self.assertRaisesRegex(ValueError, 'requires --channel upstream'):
            check.select('release', '0.3.13', network_change_only=True)
        self.resolve.assert_not_called()

    def test_protocol_rollback_is_not_an_automatic_downgrade(self):
        self.raw.side_effect = [b'#define HALO_PORT_NETWORK_VERSION 39\n',
                                b'#define HALO_PORT_NETWORK_VERSION 38\n']
        with self.assertRaisesRegex(ValueError, 'older than'):
            self.automatic()
        self.api.assert_not_called()

    def test_unreadable_or_ambiguous_header_never_defaults_to_a_build(self):
        for response in (b'', b'#define HALO_PORT_NETWORK_VERSION 0\n',
                         b'#define HALO_PORT_NETWORK_VERSION 39\n' * 2):
            self.raw.side_effect = [response]
            with self.subTest(response=response), self.assertRaises(ValueError):
                self.automatic()
        self.raw.side_effect = OSError('offline')
        with self.assertRaises(OSError):
            self.automatic()
        self.api.assert_not_called()

    def test_cli_writes_skip_and_human_summary_without_claiming_acceptance(self):
        self.resolve.return_value = self.current
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'output'
            summary = Path(temp) / 'summary'
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(output), 'GITHUB_STEP_SUMMARY': str(summary)}), \
                    patch('sys.argv', ['check_update.py', '--channel', 'upstream', '--app-version',
                                       '0.3.13', '--skip-retained', '--network-change-only']), \
                    patch('sys.stdout', new_callable=io.StringIO) as stdout:
                check.main()
            self.assertFalse(json.loads(stdout.getvalue())['build'])
            self.assertIn('build=false\n', output.read_text())
            self.assertIn('No Mac build needed', summary.read_text())
            self.assertIn('does not publish', summary.read_text())


if __name__=='__main__':unittest.main()
