#!/usr/bin/env python3
"""Skip delivery when the producing run deliberately skipped its engine build."""
import json
import os
from pathlib import Path
import re
import subprocess

import draft_release


def select(event_name, event, tag, out):
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
            return {'ready': 'false', 'tag': '', 'commit': commit}
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
    return {'ready': 'true', 'tag': tag, 'commit': commit}


def main():
    result = select(os.environ['GITHUB_EVENT_NAME'],
                    json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text()),
                    os.environ.get('CANDIDATE_TAG', ''), Path('generated/producer-report'))
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
        for key, value in result.items():
            stream.write(f'{key}={value}\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
