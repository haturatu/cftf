"""Approve one head commit, merge checked code, and dispatch its merged SHA."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys

REPOSITORY = 'haturatu/cftf'
PREFIX = 'repos/' + REPOSITORY
LABEL = 'terraform-apply'
APPROVAL = 'terraform/apply-approved'
DEPLOYMENT = 'terraform/deploy'
CHECK = 'Terraform checks'
SHA = re.compile('[0-9a-f]{40}')


def eligible(pr):
    return (pr.get('draft') is False and pr['base']['ref'] == 'master'
            and pr['base']['repo']['full_name'] == REPOSITORY
            and (pr['head'].get('repo') or {}).get('full_name') == REPOSITORY
            and SHA.fullmatch(pr['head']['sha']) is not None
            and any(label['name'] == LABEL for label in pr['labels']))


def current_approval(statuses, actor):
    latest = next((status for status in statuses if status['context'] == APPROVAL), {})
    return (latest.get('state') == 'success'
            and latest.get('creator', {}).get('login') == 'github-actions[bot]'
            and latest.get('description') == f'Approved for deployment by {actor}')


def checks_passed(runs):
    matches = [run for run in runs if run['name'] == CHECK
               and run.get('app', {}).get('slug') == 'github-actions']
    latest = max(matches, key=lambda run: run['id'], default={})
    return latest.get('status') == 'completed' and latest.get('conclusion') == 'success'


def reviews_permit(reviews):
    latest = {}
    for review in sorted(reviews, key=lambda review: review['id']):
        if review['state'] not in ('COMMENTED', 'PENDING'):
            latest[review['user']['login']] = review['state']
    return 'CHANGES_REQUESTED' not in latest.values()


class GitHub:
    """Capture API output; never expose GitHub CLI diagnostics in public logs."""

    def request(self, endpoint, *, method='GET', data=None, token=None, paginate=False):
        arguments = ['gh', 'api', '--hostname', 'github.com', '--method', method, endpoint]
        if paginate:
            arguments += ['--paginate', '--slurp']
        if data is not None:
            arguments += ['--input', '-']
        environment = dict(os.environ)
        environment.pop('GH_DEBUG', None)
        if token is not None:
            environment['GH_TOKEN'] = token
        result = subprocess.run(arguments, input=json.dumps(data) if data is not None else None,
                                text=True, capture_output=True, env=environment, timeout=60)
        if result.returncode:
            raise RuntimeError('GitHub API request failed.')
        return json.loads(result.stdout) if result.stdout.strip() else None

    def pages(self, endpoint, field=None):
        pages = self.request(endpoint, paginate=True)
        return [entry for page in pages for entry in (page[field] if field else page)]


class Controller:
    def __init__(self, api, event, event_name, actor, allowed, dispatch_token):
        if not isinstance(allowed, list) or any(not isinstance(item, str) for item in allowed):
            raise ValueError('Invalid allowlist.')
        self.api, self.event, self.event_name = api, event, event_name
        self.actor, self.allowed, self.dispatch_token = actor, allowed, dispatch_token

    def permission(self, actor):
        if actor not in self.allowed or not re.fullmatch('[A-Za-z0-9][A-Za-z0-9-]*', actor):
            return False
        response = self.api.request(PREFIX + '/collaborators/' + actor + '/permission')
        return response['permission'] in ('admin', 'maintain', 'write')

    def status(self, sha, state, description, context=APPROVAL):
        self.api.request(PREFIX + '/statuses/' + sha, method='POST', data={
            'state': state, 'context': context, 'description': description,
        })

    def run(self):
        event_pr = self.event.get('pull_request')
        action = self.event.get('action')
        if self.event_name == 'pull_request_target' and event_pr:
            if action == 'synchronize':
                if any(label['name'] == LABEL for label in event_pr['labels']):
                    self.api.request(PREFIX + f'/issues/{event_pr["number"]}/labels/' + LABEL, method='DELETE')
                self.status(event_pr['head']['sha'], 'failure', 'Relabel the current commit to authorize deployment.')
                return 'Approval invalidated after a commit update.'
            label = self.event.get('label', {}).get('name')
            if action == 'unlabeled' and label == LABEL:
                self.status(event_pr['head']['sha'], 'failure', 'Deployment approval removed.')
                return 'Deployment approval removed.'
            if action == 'labeled':
                sender = self.event['sender']['login']
                if label != LABEL or not eligible(event_pr) or not self.permission(sender):
                    return 'No authorized deployment request.'
                self.status(event_pr['head']['sha'], 'success', f'Approved for deployment by {sender}')

        if self.event_name == 'workflow_dispatch':
            number = self.event.get('inputs', {}).get('pr', '')
            if not re.fullmatch('[1-9][0-9]*', number) or not self.permission(self.actor):
                raise ValueError('Invalid retry.')
            numbers = [int(number)]
        elif event_pr:
            numbers = [event_pr['number']]
        else:
            requests = self.api.pages(PREFIX + '/pulls?state=open&base=master&per_page=100')
            numbers = [pr['number'] for pr in requests if eligible(pr)]

        for number in numbers:
            if not re.fullmatch('[1-9][0-9]*', str(number)):
                raise ValueError('Invalid request number.')
            pr = self.api.request(PREFIX + f'/pulls/{number}')
            if not eligible(pr) or (not pr.get('merged') and pr['state'] != 'open'):
                continue
            events = self.api.pages(PREFIX + f'/issues/{number}/events?per_page=100')
            labels = [event for event in events if event.get('event') in ('labeled', 'unlabeled')
                      and event.get('label', {}).get('name') == LABEL]
            if not labels or labels[-1]['event'] != 'labeled':
                continue
            label_actor = labels[-1]['actor']['login']
            if not self.permission(label_actor):
                continue
            head = pr['head']['sha']
            if not current_approval(self.api.pages(PREFIX + f'/commits/{head}/statuses?per_page=100'), label_actor):
                continue
            if not checks_passed(self.api.pages(PREFIX + f'/commits/{head}/check-runs?per_page=100', 'check_runs')):
                continue
            if not reviews_permit(self.api.pages(PREFIX + f'/pulls/{number}/reviews?per_page=100')):
                continue
            sha = pr.get('merge_commit_sha')
            if not pr.get('merged'):
                merged = self.api.request(PREFIX + f'/pulls/{number}/merge', method='PUT',
                                          data={'sha': head, 'merge_method': 'squash'})
                if not merged.get('merged'):
                    raise RuntimeError('Merge rejected.')
                sha = merged['sha']
            if not SHA.fullmatch(sha or ''):
                raise ValueError('Invalid merged commit.')
            master = self.api.request(PREFIX + '/git/ref/heads/master')
            if master['object']['sha'] != sha:
                self.status(sha, 'success', 'Superseded by a newer merged commit.', DEPLOYMENT)
                continue
            self.status(sha, 'pending', 'Private deployment requested.', DEPLOYMENT)
            try:
                self.api.request('repos/haturatu/cftf-deploy/actions/workflows/apply.yml/dispatches', method='POST',
                                 token=self.dispatch_token, data={'ref': 'master', 'inputs': {'pr': str(number), 'sha': sha}})
            except Exception:
                self.status(sha, 'failure', 'Private deployment request failed.', DEPLOYMENT)
                raise
            return 'Checked code merged and private deployment requested.'
        return 'No checked, current deployment approval is ready.'


def main():
    try:
        if os.environ['GITHUB_REPOSITORY'] != REPOSITORY or not os.environ.get('GH_TOKEN'):
            raise ValueError('Unexpected execution context.')
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        controller = Controller(GitHub(), event, os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_ACTOR'],
                                json.loads(os.environ.get('ALLOWED_APPLIERS', '["haturatu"]')),
                                os.environ['DISPATCH_TOKEN'])
        print('INFO: ' + controller.run())
        return 0
    except Exception:
        print('ERROR: Deployment request failed. Review repository configuration privately.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
