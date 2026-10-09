"""An unchanged retained engine should consume no new build or app version."""
import copy
import json
from pathlib import Path
import subprocess
import sys
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


if __name__=='__main__':unittest.main()
