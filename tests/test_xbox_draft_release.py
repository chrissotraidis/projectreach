"""Private handoff retries must preserve exact artifacts and never publish."""
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import draft_release as draft


class DraftReleaseTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.result = {'status':'built-awaiting-acceptance', 'version':'0.3.8', 'build':'17',
            'source':{'commit':'a'*40, 'tree_sha256':'b'*64}, 'engine':{'revision':'c'*40,'release':'build-154'},
            'run':'/private/build/path', 'artifacts':{},
            'acceptance':{'gameplay':False,'consumer_upgrade':False,'publication':False}}
        for platform, name in draft.PACKAGES.items():
            path = self.root/name; path.write_bytes(platform.encode())
            self.result['artifacts'][platform] = {'path':str(path),'sha256':draft.candidate.digest(path),
                'size':path.stat().st_size,'network_version':24,'minimum_os':'17.4'}
        self.release = None
        self.remote = None
        self.calls = []
        p=patch.object(draft,'api',side_effect=self.api);p.start();self.addCleanup(p.stop)
        p=patch.object(draft,'asset_bytes',side_effect=lambda asset:self.remote);p.start();self.addCleanup(p.stop)
        p=patch.object(draft.subprocess,'run',side_effect=self.upload);p.start();self.addCleanup(p.stop)
        p=patch.object(draft.candidate,'source_identity',return_value=self.result['source']);p.start();self.addCleanup(p.stop)
        p=patch.object(draft.candidate,'audit',side_effect=lambda path,platform,*args: self.result['artifacts'][platform]);p.start();self.addCleanup(p.stop)

    def api(self,path,method='GET',body=None,pages=False):
        self.calls.append((path,method,body))
        if pages: return [copy.deepcopy(self.release)] if self.release else []
        if method=='POST':
            self.assertTrue(body['draft']);self.assertTrue(body['prerelease'])
            self.release={**body,'id':123,'assets':[]}
        return copy.deepcopy(self.release)

    def upload(self,args,**kwargs):
        self.assertEqual(args[:3],['gh','release','upload'])
        self.assertNotIn('--clobber',args)
        self.remote=Path(args[4]).read_bytes()
        self.release['assets']=[{'id':456,'name':draft.ASSET}]

    def retain(self,name='retain'):
        return draft.retain(self.result,self.root/name)

    def test_round_trip_and_idempotent_retry_preserve_identity(self):
        result=self.retain(); original=self.remote
        self.assertFalse(result['published'])
        self.retain('retry');self.assertEqual(self.remote,original)
        self.assertEqual(sum(method=='POST' for _,method,_ in self.calls),1)
        restored=draft.retrieve(result['tag'],self.root/'restored')
        self.assertEqual(restored['acceptance'],self.result['acceptance'])
        self.assertNotIn('run',restored)
        for platform in draft.PACKAGES:
            self.assertEqual(draft.candidate.digest(Path(restored['artifacts'][platform]['path'])),self.result['artifacts'][platform]['sha256'])
        self.assertTrue(all(method in ('GET','POST') for _,method,_ in self.calls))

    def test_published_or_changed_draft_is_not_modified(self):
        self.retain(); original=self.remote
        self.release['draft']=False
        with self.assertRaisesRegex(ValueError,'published'):self.retain('public')
        self.release['draft']=True;self.remote=b'different'
        with self.assertRaisesRegex(ValueError,'differs'):self.retain('different')
        self.assertEqual(self.remote,b'different')
        self.assertNotEqual(self.remote,original)

    def test_wrong_source_or_failed_candidate_stops_before_remote_actions(self):
        self.result['status']='failed'
        with self.assertRaises(ValueError):self.retain()
        self.result['status']='built-awaiting-acceptance'
        with patch.object(draft.candidate,'source_identity',return_value={'commit':'d'*40,'tree_sha256':'b'*64}):
            with self.assertRaisesRegex(ValueError,'checkout differs'):self.retain()
        self.assertEqual(self.calls,[])

    def test_tampered_package_is_rejected(self):
        with patch.object(draft.candidate,'audit',return_value={**self.result['artifacts']['ios'],'sha256':'0'*64}):
            with self.assertRaisesRegex(ValueError,'changed'):self.retain()
        self.assertEqual(self.calls,[])

    def test_download_rejects_unsafe_or_duplicate_archive_members(self):
        tag=self.retain()['tag']
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as archive:archive.writestr('../escape','no')
        self.remote=stream.getvalue()
        with self.assertRaisesRegex(ValueError,'archive members'):draft.retrieve(tag,self.root/'unsafe')
        self.assertFalse((self.root/'escape').exists())

    def test_downloaded_identity_must_match_draft(self):
        tag=self.retain()['tag']
        self.release['target_commitish']='d'*40
        with self.assertRaisesRegex(ValueError,'identity differs'):draft.retrieve(tag,self.root/'identity')
        self.assertFalse((self.root/'identity/result.json').exists())

    def test_partial_upload_can_retry_without_overwriting(self):
        with patch.object(draft.subprocess,'run',side_effect=OSError('connection lost')):
            with self.assertRaises(OSError):self.retain()
        self.assertEqual(self.release['assets'],[])
        self.retain('retry')
        self.assertEqual(sum(method=='POST' for _,method,_ in self.calls),1)

    def test_bad_readback_is_not_reported_as_retained(self):
        with patch.object(draft,'asset_bytes',return_value=b'bad readback'):
            with self.assertRaisesRegex(ValueError,'readback differs'):self.retain()


if __name__=='__main__':unittest.main()
