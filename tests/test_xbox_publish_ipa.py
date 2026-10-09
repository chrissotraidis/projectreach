"""A direct IPA release becomes public only after exact private asset readback."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import publish_ipa as publish


class PublishTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.result = {'version': '0.3.8', 'build': '20', 'source': {'commit': 'a'*40},
                       'started': '2026-10-08T08:00:00+00:00', 'engine': {'release': 'build-155','revision':'b'*40},
                       'artifacts': {p: {'path': str(self.root/p)} for p in ('ios', 'mac')}}
        p = patch.object(publish.app_channel, 'advance', return_value='c'*40); self.advance = p.start(); self.addCleanup(p.stop)
        self.release = None
        self.old = {'id': 1, 'tag_name': 'v0.3.7', 'draft': False, 'prerelease': False, 'assets': []}
        self.latest = self.old
        self.remote = {}
        self.calls = []
        self.uploaded = []
        self.readback = []
        self.count = 0
        for obj, name, effect in ((publish.draft, 'api', self.api),
                                  (publish.draft, 'asset_bytes', self.download),
                                  (publish.subprocess, 'run', self.upload),
                                  (publish.update_source, 'stage', self.stage)):
            p = patch.object(obj, name, side_effect=effect); p.start(); self.addCleanup(p.stop)
        p = patch.object(publish.candidate, 'audit'); self.audit = p.start(); self.addCleanup(p.stop)

    def stage(self, result, out, tag):
        out.mkdir()
        for name in publish.FILES:
            (out/name).write_text(json.dumps([name, result, tag], sort_keys=True))
        (out/'review.json').write_text('PRIVATE LOCAL PATHS')

    def api(self, path, method='GET', body=None, pages=False):
        self.calls.append((path, method, body))
        if pages: return copy.deepcopy([self.old] + ([self.release] if self.release else []))
        if path.endswith('/latest'): return copy.deepcopy(self.latest)
        if method == 'POST':
            self.assertTrue(body['draft'])
            self.release = {**body, 'id': 2, 'assets': []}
        elif method == 'PATCH':
            self.assertEqual(set(self.readback), set(publish.FILES))
            self.assertEqual(body, {'draft': False, 'prerelease': False, 'make_latest': 'true'})
            self.release.update(body)
            self.latest = self.release
        return copy.deepcopy(self.release)

    def upload(self, args, **kwargs):
        self.assertEqual(args[:3], ['gh', 'release', 'upload'])
        self.assertNotIn('--clobber', args)
        path = Path(args[4]); self.uploaded.append(path.name)
        self.remote[path.name] = path.read_bytes()
        self.release['assets'].append({'id': len(self.remote)+10, 'name': path.name, 'state': 'uploaded'})

    def download(self, asset):
        self.readback.append(asset['name'])
        return self.remote[asset['name']]

    def deliver(self, live=False):
        self.count += 1
        return publish.deliver(self.result, self.root/str(self.count), publish=live)

    def mutations(self):
        return [c for c in self.calls if c[1] != 'GET']

    def test_default_draft_and_retry_do_not_publish_or_upload_private_review(self):
        receipt = self.deliver()
        self.assertFalse(receipt['published'])
        self.assertEqual(set(self.uploaded), set(publish.FILES))
        before = dict(self.remote)
        self.deliver()
        self.assertEqual(self.remote, before)
        self.assertEqual(len(self.uploaded), len(publish.FILES))
        self.assertEqual([c[1] for c in self.mutations()], ['POST'])
        self.assertEqual(self.latest['id'], 1)

    def test_publish_is_last_and_published_retry_is_read_only(self):
        receipt = self.deliver(live=True)
        self.assertTrue(receipt['published'])
        self.assertFalse(receipt['consumer_upgrade'])
        self.assertFalse(receipt['apple_services_used'])
        before = len(self.mutations())
        self.deliver(live=True)
        self.assertEqual(len(self.mutations()), before)
        self.assertEqual(len(self.uploaded), len(publish.FILES))

    def test_bad_upload_readback_cannot_publish(self):
        with patch.object(publish.draft, 'asset_bytes', return_value=b'wrong'):
            with self.assertRaisesRegex(ValueError, 'readback differs'): self.deliver(live=True)
        self.assertTrue(self.release['draft'])
        self.assertEqual(self.latest['id'], 1)
        self.assertFalse(any(c[1]=='PATCH' for c in self.calls))

    def test_partial_upload_retries_without_overwriting_previous_assets(self):
        original = self.upload
        def interrupted(args, **kwargs):
            if Path(args[4]).name == 'altstore.json': raise subprocess.CalledProcessError(1, 'gh')
            return original(args, **kwargs)
        with patch.object(publish.subprocess, 'run', side_effect=interrupted):
            with self.assertRaises(subprocess.CalledProcessError): self.deliver(live=True)
        prior = dict(self.remote)
        self.assertTrue(self.release['draft'])
        self.assertEqual(self.latest['id'], 1)
        self.deliver(live=True)
        for name, data in prior.items(): self.assertEqual(self.remote[name], data)
        self.assertEqual(len(self.uploaded), len(publish.FILES))

    def test_changed_asset_or_source_is_never_overwritten(self):
        self.deliver()
        self.remote['HaloPad.ipa'] = b'changed'
        with self.assertRaisesRegex(ValueError, 'readback differs'): self.deliver(live=True)
        self.assertEqual(self.remote['HaloPad.ipa'], b'changed')
        self.release['target_commitish'] = 'b'*40
        with self.assertRaisesRegex(ValueError, 'identity differs'): self.deliver(live=True)
        self.assertEqual(self.latest['id'], 1)

    def test_older_candidate_cannot_replace_newer_public_version_or_build(self):
        for version, build in (('0.3.9','1'), ('0.3.8','21'), ('0.3.8','20')):
            with self.subTest(version=version, build=build):
                self.old = {**self.old, 'tag_name':f'halopad-{version}-{build}', 'assets': [{'name': 'halopad-update.json'}]}
                self.latest = self.old
                self.remote['halopad-update.json'] = json.dumps({'bundle_id':'dev.halopad.HaloPad',
                                                                'version':version,'build':build,'engine':self.result['engine']}).encode()
                with self.assertRaisesRegex(ValueError, 'not newer'):
                    publish.require_newer(self.result, [self.old])
        self.assertFalse(any(c[1]=='PATCH' for c in self.calls))

    def test_newer_app_cannot_ship_older_or_retagged_engine(self):
        self.old={**self.old,'tag_name':'halopad-0.3.8-19','assets':[{'name':'halopad-update.json'}]}
        record={'bundle_id':'dev.halopad.HaloPad','version':'0.3.8','build':'19',
                'engine':{'release':'build-155','revision':'b'*40}}
        self.remote['halopad-update.json']=json.dumps(record).encode()
        for engine in ({'release':'build-150','revision':'a'*40}, {'release':'build-155','revision':'c'*40}):
            self.result['engine']=engine
            with self.subTest(engine=engine),self.assertRaisesRegex(ValueError,'engine regression'):
                publish.require_newer(self.result,[self.old])
        self.assertFalse(any(c[1]=='PATCH' for c in self.calls))
        self.advance.assert_not_called()

    def test_recipe_latest_does_not_hide_previous_engine_guard(self):
        self.old={**self.old,'tag_name':'halopad-0.3.8-19','assets':[{'name':'halopad-update.json'}]}
        self.latest={'id':99,'tag_name':'v0.3.9','draft':False,'prerelease':False,'assets':[]}
        self.remote['halopad-update.json']=json.dumps({'bundle_id':'dev.halopad.HaloPad','version':'0.3.8',
            'build':'19','engine':{'release':'build-157','revision':'c'*40}}).encode()
        with self.assertRaisesRegex(ValueError,'engine regression'):
            publish.require_newer(self.result,[self.old,self.latest])

    def test_feed_failure_retries_already_published_assets_without_republishing(self):
        self.advance.side_effect=RuntimeError('feed temporarily unavailable')
        with self.assertRaisesRegex(RuntimeError,'feed temporarily'):
            self.deliver(live=True)
        self.assertFalse(self.release['draft'])
        before=len(self.mutations()); before_uploads=len(self.uploaded)
        self.advance.side_effect=None
        receipt=self.deliver(live=True)
        self.assertTrue(receipt['published'])
        self.assertEqual(len(self.mutations()),before)
        self.assertEqual(len(self.uploaded),before_uploads)
        self.assertEqual(receipt['channel_commit'],'c'*40)

    def test_historical_two_component_versions_compare_as_the_same_version(self):
        self.assertEqual(publish.version_key('0.3', '20'), publish.version_key('0.3.0', '20'))
        self.assertLess(publish.version_key('0.3.0', '20'), publish.version_key('0.3', '21'))

    def test_profile_or_notice_audit_failure_precedes_any_remote_action(self):
        self.audit.side_effect = ValueError('private provisioning profile in candidate')
        with self.assertRaises(ValueError): self.deliver(live=True)
        self.assertEqual(self.calls, [])
        self.assertFalse((self.root/'1').exists())
        self.assertEqual(self.audit.call_args.kwargs, {'require_notices': True})

    def test_unexpected_release_assets_are_preserved_and_stop_delivery(self):
        self.deliver()
        self.release['assets'].append({'name':'do-not-delete.txt','id':90})
        with self.assertRaisesRegex(ValueError, 'unexpected assets'): self.deliver(live=True)
        self.assertEqual(self.release['assets'][-1]['name'], 'do-not-delete.txt')
        self.assertFalse(any(c[1]=='PATCH' for c in self.calls))


if __name__ == '__main__':
    unittest.main()
