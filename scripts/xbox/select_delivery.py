#!/usr/bin/env python3
"""Skip delivery when the producing run deliberately skipped its engine build."""
import json
import os
from pathlib import Path
import re
import subprocess

import draft_release
import publish_ipa


def select(event_name, event, tag, out, *, resume_retained=False, publish=False):
    commit = ''
    if event_name == 'workflow_run':
        run = event['workflow_run']
        run_id, attempt, number = (str(run[key]) for key in ('id', 'run_attempt', 'run_number'))
        commit = run['head_sha']
        if not all(re.fullmatch(r'[1-9][0-9]*', value) for value in (run_id, attempt, number)):
            raise ValueError('invalid producing run identity')
        if not re.fullmatch(r'[0-9a-f]{40}', commit):
            raise ValueError('invalid producing commit')
        pages = json.loads(subprocess.check_output([
            'gh', 'api', f'repos/{draft_release.REPO}/actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100',
            '--paginate', '--slurp'], text=True, timeout=60))
        builds = [job for page in pages for job in page['jobs'] if job['name'] == 'build']
        if len(builds) != 1 or builds[0]['status'] != 'completed':
            raise ValueError('expected exactly one completed producing build job')
        if builds[0]['conclusion'] == 'skipped':
            if not resume_retained:
                return {'ready': 'false', 'tag': '', 'commit': commit}
            selectors = [job for page in pages for job in page['jobs'] if job['name'] == 'select']
            if len(selectors) != 1 or selectors[0]['status'] != 'completed':
                raise ValueError('expected one completed candidate selection job')
            if selectors[0]['conclusion'] == 'skipped':
                return {'ready': 'false', 'tag': '', 'commit': commit}  # Upstream checks are disabled.
            if selectors[0]['conclusion'] != 'success':
                raise ValueError('candidate selection did not succeed')
            subprocess.run(['gh', 'run', 'download', run_id, '--repo', draft_release.REPO,
                            '--name', f'halopad-selection-{number}-{attempt}', '--dir', str(out)],
                           check=True, timeout=120)
            selection = json.loads((out / 'selection.json').read_text())
            reason = selection.get('reason')
            if reason in ('previous-build-failure', 'current-engine', 'same-network-version'):
                if (selection.get('build') is not False or selection.get('candidate') != ''
                        or selection.get('commit') != ''):
                    raise ValueError('invalid no-candidate selection')
                if reason != 'previous-build-failure':
                    record = selection.get('record')
                    if (not isinstance(record, dict)
                            or not isinstance(record.get('revision'), str)
                            or not re.fullmatch(r'[0-9a-f]{40}', record['revision'])
                            or not isinstance(record.get('release'), str)
                            or not re.fullmatch(r'build-[0-9]+', record['release'])):
                        raise ValueError('invalid unchanged-engine record')
                    network = selection.get('network')
                    if network is not None or reason == 'same-network-version':
                        if (not isinstance(network, dict) or set(network) != {'current', 'upstream'}
                                or any(type(value) is not int or not 1 <= value <= 65535
                                       for value in network.values())
                                or network['current'] != network['upstream']):
                            raise ValueError('invalid unchanged-network selection')
                return {'ready': 'false', 'tag': '', 'commit': commit}
            tag, commit = selection['candidate'], selection['commit']
            if selection['build'] is not False or not re.fullmatch(r'[0-9a-f]{40}', commit):
                raise ValueError('invalid retained-candidate selection')
        else:
            if builds[0]['conclusion'] != 'success':
                raise ValueError('producing build did not succeed')
            subprocess.run(['gh', 'run', 'download', run_id, '--repo', draft_release.REPO,
                            '--name', f'halopad-build-report-{number}', '--dir', str(out)],
                           check=True, timeout=120)
            tag = json.loads((out / 'private-handoff.json').read_text())['tag']
    elif event_name != 'workflow_dispatch':
        raise ValueError('unsupported delivery event')
    if not isinstance(tag, str) or not re.fullmatch(r'halopad-candidate-[0-9.]+-[0-9]+', tag):
        raise ValueError('invalid candidate tag')
    if resume_retained and commit and publish_ipa.completed(tag, commit, publish=publish):
        return {'ready': 'false', 'tag': tag, 'commit': commit}
    return {'ready': 'true', 'tag': tag, 'commit': commit}


def main():
    result = select(os.environ['GITHUB_EVENT_NAME'],
                    json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()),
                    os.environ.get('CANDIDATE_TAG', ''), Path('generated/producer-report'),
                    resume_retained=os.environ.get('RESUME_RETAINED') == 'true',
                    publish=os.environ.get('PUBLISH_IPA') == 'true')
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
        for key, value in result.items():
            stream.write(f'{key}={value}\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
