#!/usr/bin/env python3
"""Export and submit one retained candidate to a configured TestFlight group.

No engine build, GitHub binary publication, tester creation or device control.
Delivery is opt-in; Apple review and installation remain separate evidence.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

import candidate
import export_archive


def settings(env):
    channel = env.get('HALOPAD_TESTFLIGHT_CHANNEL')
    if channel not in ('internal', 'external'):
        raise ValueError('TestFlight delivery is disabled; choose internal or external explicitly')
    groups = json.loads(env.get('HALOPAD_TESTFLIGHT_GROUPS', 'null'))
    if (not isinstance(groups, list) or not groups
            or any(not isinstance(g, str) or not g.strip() for g in groups)):
        raise ValueError('HALOPAD_TESTFLIGHT_GROUPS must name at least one existing group as a JSON array')
    encryption = env.get('HALOPAD_USES_NON_EXEMPT_ENCRYPTION')
    if encryption not in ('true', 'false'):
        raise ValueError('configure the reviewed encryption declaration; no default is assumed')
    key = Path(env.get('HALOPAD_API_KEY_PATH', ''))
    auth = export_archive.api_auth(key, env.get('HALOPAD_API_KEY_ID'), env.get('HALOPAD_API_ISSUER'))
    return {'channel': channel, 'groups': groups, 'uses_non_exempt_encryption': encryption == 'true',
            'auth': auth}


def deliver(result, out, profile, identity, env, *, resume=False):
    config = settings(env)  # Reject incomplete setup before signing or contacting Apple.
    proof = export_archive.export(result, out, profile, identity, config['auth'])
    artifact = proof['artifact']
    if candidate.digest(Path(artifact['path'])) != artifact['sha256']:
        raise ValueError('exported IPA changed before TestFlight submission')
    request = {k: config[k] for k in ('channel', 'groups', 'uses_non_exempt_encryption')}
    request.update(ipa=artifact['path'], sha256=artifact['sha256'], version=result['version'],
                   build=result['build'], engine=result['engine'], resume=resume)
    request_path = out / 'testflight-request.json'
    candidate.write_json(request_path, request)
    child_env = {**env, 'BUNDLE_GEMFILE': str(candidate.ROOT / 'tools/testflight/Gemfile'),
                 'HALOPAD_TESTFLIGHT_REQUEST': str(request_path),
                 'FASTLANE_SKIP_UPDATE_CHECK': '1', 'FASTLANE_OPT_OUT_USAGE': '1'}
    # The Ruby entry point checks the same bytes again and selects this exact
    # app version/build. It never falls back to the newest uploaded build.
    subprocess.run(['bundle', 'exec', 'ruby', str(candidate.ROOT / 'tools/testflight/deliver.rb')],
                   env=child_env, cwd=candidate.ROOT, check=True, timeout=3600)
    receipt = {**request, 'submission_command_succeeded': True,
               'apple_review_approved': False, 'consumer_upgrade': False}
    candidate.write_json(out / 'testflight-submission.json', receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--resume-uploaded', action='store_true',
                        help='explicitly resume distribution of this exact version/build already in App Store Connect')
    args = parser.parse_args()
    try:
        out = args.out.resolve()
        if not out.is_relative_to(candidate.ROOT / 'generated'):
            raise ValueError('TestFlight artifacts must stay under ignored generated/')
        deliver(json.loads(args.candidate.read_text()), out, args.profile.resolve(), args.identity,
                dict(os.environ), resume=args.resume_uploaded)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'TestFlight submission stopped: {error}\n')
    print('Submission command completed. Apple review and a consumer upgrade are not yet verified.')


if __name__ == '__main__':
    main()
