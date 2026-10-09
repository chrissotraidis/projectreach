"""Exercise atomic feed commits, interruption recovery and delivery preflight."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/xbox'))
import app_channel as channel
import publish_ipa as publisher


def feeds(build='20', engine='build-155'):
    record={'schema':1,'bundle_id':'dev.halopad.HaloPad','version':'0.3.8','build':build,
            'engine':{'release':engine,'revision':'a'*40},
            'artifacts':{'ios':{'url':f'https://github.com/chrissotraidis/projectreach/releases/download/halopad-0.3.8-{build}/HaloPad.ipa'}}}
    feed={'sourceURL':channel.BASE+'/altstore.json','apps':[{'bundleIdentifier':'dev.halopad.HaloPad',
        'versions':[{'version':'0.3.8','buildVersion':build,'downloadURL':record['artifacts']['ios']['url']}]}]}
    return {'halopad-update.json':json.dumps(record)+'\n','altstore.json':json.dumps(feed)+'\n'}


class GitAPI:
    """Git object operations backed by an actual disposable bare repository."""
    def __init__(self, root):
        self.root=root
        subprocess.run(['git','init','--bare','-q',str(root)],check=True)
        self.fail_ref=False
        self.lose_response=False
        self.writes=[]

    def git(self,*args,input=None,strip=True):
        value=subprocess.check_output(['git','--git-dir',str(self.root),*args],input=input,text=True)
        return value.strip() if strip else value

    def api(self,path,method='GET',body=None,pages=False):
        route=path.removeprefix(channel.API+'/')
        if method!='GET': self.writes.append((route,copy.deepcopy(body)))
        if route.startswith('matching-refs/'):
            ref='refs/heads/'+channel.BRANCH
            sha=self.git('for-each-ref','--format=%(objectname)',ref)
            return [{'ref':ref,'object':{'sha':sha}}] if sha else []
        if route.startswith('commits/'):
            return {'tree':{'sha':self.git('rev-parse',route.split('/')[1]+'^{tree}')}}
        if route.startswith('trees/'):
            entries=[]
            for line in self.git('ls-tree',route.split('/')[1]).splitlines():
                mode,typ,sha,path=line.split()
                entries.append({'path':path,'mode':mode,'type':typ,'sha':sha})
            return {'tree':entries,'truncated':False}
        if route.startswith('blobs/'):
            return {'encoding':'base64','content':base64.b64encode(self.git('cat-file','blob',route.split('/')[1],strip=False).encode()).decode()}
        if route=='trees':
            lines=[]
            for item in body['tree']:
                sha=self.git('hash-object','-w','--stdin',input=item['content'])
                lines.append(f'{item["mode"]} {item["type"]} {sha}\t{item["path"]}')
            return {'sha':self.git('mktree',input='\n'.join(lines)+'\n')}
        if route=='commits':
            args=['-c','user.name=Test','-c','user.email=test@example.invalid','commit-tree',body['tree']]
            for parent in body['parents']:args+=['-p',parent]
            return {'sha':self.git(*args,input=body['message'])}
        if route.startswith('refs'):
            if self.fail_ref: raise subprocess.CalledProcessError(1,['gh','api'])
            ref='refs/heads/'+channel.BRANCH
            if method=='PATCH':
                assert body['force'] is False
                current=self.git('rev-parse',ref)
                subprocess.run(['git','--git-dir',str(self.root),'merge-base','--is-ancestor',current,body['sha']],check=True)
            else:
                assert body['ref']==ref
                assert not self.git('for-each-ref','--format=%(objectname)',ref)
            self.git('update-ref',ref,body['sha'])
            if self.lose_response: raise subprocess.CalledProcessError(1,['gh','api'])
            return {}
        raise AssertionError((path,method,body))


class ChannelTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory();self.addCleanup(tmp.cleanup)
        self.root=Path(tmp.name);self.out=self.root/'out';self.out.mkdir()
        self.store=GitAPI(self.root/'git')
        p=patch.object(channel.draft,'api',side_effect=self.store.api);p.start();self.addCleanup(p.stop)
        self.write(feeds())

    def write(self,files):
        for name,text in files.items(): (self.out/name).write_text(text)

    def test_two_feeds_advance_together_and_retry_is_read_only(self):
        first=channel.advance(self.out)
        self.assertEqual(channel.snapshot(),(first,feeds()))
        self.assertEqual(set(self.store.git('ls-tree','--name-only',first).splitlines()),set(channel.FILES))
        count=len(self.store.writes)
        self.assertEqual(channel.advance(self.out),first)
        self.assertEqual(len(self.store.writes),count)
        self.write(feeds('21','build-157'))
        second=channel.advance(self.out)
        self.assertEqual(self.store.git('rev-parse',second+'^'),first)
        self.assertEqual(channel.snapshot(),(second,feeds('21','build-157')))

    def test_interruption_preserves_old_feeds_then_retry_completes(self):
        first=channel.advance(self.out);self.write(feeds('21','build-157'))
        self.store.fail_ref=True
        with self.assertRaises(subprocess.CalledProcessError):channel.advance(self.out)
        self.assertEqual(channel.snapshot(),(first,feeds()))
        self.store.fail_ref=False
        channel.advance(self.out)
        self.assertEqual(channel.snapshot()[1],feeds('21','build-157'))

    def test_lost_success_response_retries_without_mutation(self):
        self.store.lose_response=True
        with self.assertRaises(subprocess.CalledProcessError):channel.advance(self.out)
        count=len(self.store.writes)
        self.store.lose_response=False
        channel.advance(self.out)
        self.assertEqual(len(self.store.writes),count)

    def test_older_engine_or_same_version_changed_content_cannot_advance(self):
        first=channel.advance(self.out)
        for files in (feeds('21','build-150'),feeds('19'),feeds('20','build-157')):
            self.write(files)
            with self.subTest(files=files),self.assertRaises(ValueError):channel.advance(self.out)
            self.assertEqual(channel.snapshot(),(first,feeds()))

    def test_competing_writer_is_not_overwritten(self):
        channel.advance(self.out)
        real_api=self.store.api
        def race(path,method='GET',body=None,pages=False):
            if '/refs/heads/' in path and method=='PATCH':
                current=self.store.git('rev-parse','refs/heads/'+channel.BRANCH)
                tree=self.store.git('rev-parse',current+'^{tree}')
                other=self.store.git('-c','user.name=Test','-c','user.email=test@example.invalid',
                                     'commit-tree',tree,'-p',current,input='Other writer')
                self.store.git('update-ref','refs/heads/'+channel.BRANCH,other)
                self.other=other
            return real_api(path,method,body,pages)
        self.write(feeds('21','build-157'))
        with patch.object(channel.draft,'api',side_effect=race),self.assertRaises(subprocess.CalledProcessError):
            channel.advance(self.out)
        self.assertEqual(channel.snapshot()[0],self.other)


class CompletionTests(unittest.TestCase):
    def setUp(self):
        self.contents={name:value.encode() for name,value in feeds().items()}
        self.contents.update({'HaloPad.ipa':b'ipa','HaloPad-Mac.zip':b'mac','icon.png':b'icon'})
        self.contents['SHA256SUMS']=''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name,data in sorted(self.contents.items())).encode()
        self.release={'tag_name':'halopad-0.3.8-20','target_commitish':'a'*40,'draft':True,'prerelease':False,
            'assets':[{'name':n,'state':'uploaded','digest':'sha256:'+hashlib.sha256(b).hexdigest()} for n,b in self.contents.items()]}
        p=patch.object(publisher.draft,'api',side_effect=lambda *a,**kw:[self.release]);p.start();self.addCleanup(p.stop)
        p=patch.object(publisher.draft,'asset_bytes',side_effect=lambda a:self.contents[a['name']]);p.start();self.addCleanup(p.stop)

    def done(self,publish=False):
        return publisher.completed('halopad-candidate-0.3.8-20','a'*40,publish=publish)

    def test_complete_draft_skips_private_redelivery_but_not_public_promotion(self):
        self.assertTrue(self.done());self.assertFalse(self.done(True))

    def test_missing_or_corrupt_asset_resumes_delivery(self):
        self.release['assets'].pop();self.assertFalse(self.done())

    def test_published_package_resumes_missing_or_stale_feed(self):
        self.release['draft']=False
        for previous in ({},feeds('19')):
            with patch.object(publisher.app_channel,'snapshot',return_value=('head',previous)):
                self.assertFalse(self.done(True))
        for previous in (feeds(),feeds('21','build-157')):
            with patch.object(publisher.app_channel,'snapshot',return_value=('head',previous)):
                self.assertTrue(self.done(True))


if __name__=='__main__':unittest.main()
