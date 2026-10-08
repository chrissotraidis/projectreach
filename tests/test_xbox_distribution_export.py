"""Export success cannot replace profile/capability checks or Apple acceptance."""
import copy
import datetime
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import export_archive as export


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026,10,8,tzinfo=datetime.timezone.utc)
        self.ent = {'application-identifier':'TEAM.dev.halopad.HaloPad',
            'com.apple.developer.team-identifier':'TEAM', 'get-task-allow':False,
            'beta-reports-active':True, **{key:True for key in export.REQUIRED}}
        self.profile = {'TeamIdentifier':['TEAM'],'Entitlements':copy.deepcopy(self.ent),
            'ExpirationDate':datetime.datetime(2027,1,1)}

    def check(self):
        export.validate_distribution(self.profile,self.ent,'TEAM',self.now)

    def test_store_profile_with_both_signed_memory_capabilities(self):
        self.check()

    def test_profile_and_signature_must_each_grant_memory(self):
        for side in ('profile','signature'):
            for key in export.REQUIRED:
                with self.subTest(side=side,key=key):
                    mapping=self.profile['Entitlements'] if side=='profile' else self.ent
                    del mapping[key]
                    with self.assertRaisesRegex(ValueError,'both retain'):self.check()
                    mapping[key]=True

    def test_development_adhoc_enterprise_and_debug_signature_rejected(self):
        for kind in ('development','adhoc','enterprise','not_store','missing_signed_beta','debug_signature'):
            profile,ent=copy.deepcopy(self.profile),copy.deepcopy(self.ent)
            if kind=='development':self.profile['Entitlements']['get-task-allow']=True
            elif kind=='adhoc':self.profile['ProvisionedDevices']=['DEVICE']
            elif kind=='enterprise':self.profile['ProvisionsAllDevices']=True
            elif kind=='not_store':del self.profile['Entitlements']['beta-reports-active']
            elif kind=='missing_signed_beta':del self.ent['beta-reports-active']
            else:self.ent['get-task-allow']=True
            with self.subTest(kind=kind),self.assertRaisesRegex(ValueError,'App Store'):self.check()
            self.profile,self.ent=profile,ent

    def test_wrong_identity_and_expired_profile_rejected(self):
        self.ent['application-identifier']='TEAM.dev.halopad.Other'
        with self.assertRaisesRegex(ValueError,'App ID'):self.check()
        self.ent['application-identifier']='TEAM.dev.halopad.HaloPad'
        self.profile['ExpirationDate']=datetime.datetime(2026,10,7)
        with self.assertRaisesRegex(ValueError,'expired'):self.check()

    def test_export_directory_must_have_exactly_one_ipa(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            with patch.object(export.candidate,'audit') as audit:
                with self.assertRaisesRegex(ValueError,'exactly one'):export.verify_export({},root,'TEAM')
                (root/'a.ipa').touch();(root/'b.ipa').touch()
                with self.assertRaisesRegex(ValueError,'exactly one'):export.verify_export({},root,'TEAM')
                audit.assert_not_called()

    def test_verified_export_records_exact_bytes_without_claiming_delivery(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);ipa=root/'HaloPad.ipa';ipa.write_bytes(b'export fixture')
            checked={'sha256':export.candidate.digest(ipa),'path':str(ipa)}
            result={'engine':{},'version':'0.3.8','build':'18'}
            with patch.object(export.candidate,'audit',return_value=checked), \
                 patch.object(export.extract_ipa,'extract',return_value=root/'HaloPad.app'), \
                 patch.object(export.subprocess,'run'), \
                 patch.object(export.subprocess,'check_output',return_value=plistlib.dumps(self.ent)), \
                 patch.object(export,'decode',return_value=self.profile):
                proof=export.verify_export(result,root,'TEAM')
            self.assertEqual(json.loads((root/'export-proof.json').read_text()),proof)
            self.assertEqual(proof['artifact']['sha256'],export.candidate.digest(ipa))
            self.assertFalse(proof['uploaded'])
            self.assertFalse(proof['apple_acceptance'])
            self.assertFalse(proof['consumer_upgrade'])


if __name__=='__main__':unittest.main()
