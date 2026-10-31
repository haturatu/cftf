"""Offline tests for approval, merge ordering, and scoped dispatch."""

import copy
import json
import os
import subprocess
import unittest
from unittest.mock import patch

from control import (APPROVAL, CHECK, DEPLOYMENT, PREFIX, Controller, GitHub,
                     checks_passed, current_approval, eligible, reviews_permit)

HEAD = 'a' * 40
MERGED = 'b' * 40


def pull_request():
    return {'number': 1, 'draft': False, 'state': 'open', 'merged': False,
            'base': {'ref': 'master', 'repo': {'full_name': 'haturatu/cftf'}},
            'head': {'sha': HEAD, 'repo': {'full_name': 'haturatu/cftf'}},
            'labels': [{'name': 'terraform-apply'}]}


class FakeAPI:
    def __init__(self):
        self.pr = pull_request()
        self.calls = []
        self.master = MERGED
        self.dispatch_fails = False
        self.events = [{'event': 'labeled', 'label': {'name': 'terraform-apply'}, 'actor': {'login': 'haturatu'}}]
        self.statuses = [{'context': APPROVAL, 'state': 'success', 'creator': {'login': 'github-actions[bot]'},
                          'description': 'Approved for deployment by haturatu'}]
        self.checks = [{'id': 1, 'name': CHECK, 'app': {'slug': 'github-actions'}, 'status': 'completed', 'conclusion': 'success'}]
        self.reviews = []

    def request(self, endpoint, *, method='GET', data=None, token=None):
        self.calls.append((endpoint, method, data, token))
        if endpoint.endswith('/permission'):
            return {'permission': 'admin'}
        if endpoint == PREFIX + '/pulls/1':
            return copy.deepcopy(self.pr)
        if endpoint.endswith('/merge'):
            if data != {'sha': self.pr['head']['sha'], 'merge_method': 'squash'}:
                raise AssertionError('Merge must pin the approved head.')
            return {'merged': True, 'sha': MERGED}
        if endpoint.endswith('/git/ref/heads/master'):
            return {'object': {'sha': self.master}}
        if '/statuses/' in endpoint:
            return {}
        if method == 'DELETE':
            return None
        if endpoint.endswith('/dispatches'):
            if self.dispatch_fails:
                raise RuntimeError('Simulated dispatch failure.')
            return None
        raise AssertionError(endpoint)

    def pages(self, endpoint, field=None):
        if '/pulls?' in endpoint:
            return [copy.deepcopy(self.pr)]
        if '/events?' in endpoint:
            return self.events
        if '/statuses?' in endpoint:
            return self.statuses if HEAD in endpoint else []
        if '/check-runs?' in endpoint:
            return self.checks
        if '/reviews?' in endpoint:
            return self.reviews
        raise AssertionError(endpoint)


class ControllerTests(unittest.TestCase):
    def run_controller(self, api, event=None, event_name='workflow_run'):
        return Controller(api, event or {}, event_name, 'haturatu', ['haturatu'], 'test-dispatch-token').run()

    def assert_not_dispatched(self, api):
        self.assertFalse(any(endpoint.endswith(('/merge', '/dispatches')) for endpoint, *_ in api.calls))

    def test_eligibility_requires_label_and_same_repository(self):
        self.assertTrue(eligible(pull_request()))
        for field, value in [('draft', True), ('labels', [])]:
            pr = pull_request(); pr[field] = value
            self.assertFalse(eligible(pr))
        pr = pull_request(); pr['head']['repo']['full_name'] = 'outside/fork'
        self.assertFalse(eligible(pr))

    def test_only_latest_approval_from_trusted_actor_is_current(self):
        approved = FakeAPI().statuses[0]
        self.assertTrue(current_approval([approved], 'haturatu'))
        self.assertFalse(current_approval([dict(approved, state='failure'), approved], 'haturatu'))
        self.assertFalse(current_approval([dict(approved, creator={'login': 'outside'})], 'haturatu'))
        self.assertFalse(current_approval([], 'haturatu'))

    def test_latest_failed_check_overrides_old_success(self):
        passed = FakeAPI().checks[0]
        self.assertTrue(checks_passed([passed]))
        self.assertFalse(checks_passed([passed, dict(passed, id=2, conclusion='failure')]))
        self.assertFalse(checks_passed([dict(passed, app={'slug': 'outside'})]))

    def test_changes_requested_remain_blocking_until_resolved(self):
        requested = {'id': 1, 'user': {'login': 'reviewer'}, 'state': 'CHANGES_REQUESTED'}
        self.assertFalse(reviews_permit([requested]))
        self.assertFalse(reviews_permit([requested, dict(requested, id=2, state='COMMENTED')]))
        self.assertTrue(reviews_permit([requested, dict(requested, id=3, state='APPROVED')]))

    def test_dispatch_occurs_after_merge_and_uses_merged_sha(self):
        api = FakeAPI()
        self.run_controller(api)
        operations = [call for call in api.calls if call[0].endswith(('/merge', '/dispatches'))]
        self.assertEqual([call[1] for call in operations], ['PUT', 'POST'])
        self.assertEqual(operations[0][2]['sha'], HEAD)
        self.assertEqual(operations[1][2], {'ref': 'master', 'inputs': {'pr': '1', 'sha': MERGED}})
        self.assertEqual(operations[1][3], 'test-dispatch-token')

    def test_failed_checks_prevent_merge_and_dispatch(self):
        api = FakeAPI(); api.checks[0]['conclusion'] = 'failure'
        self.run_controller(api)
        self.assert_not_dispatched(api)

    def test_changed_head_invalidates_previous_approval(self):
        api = FakeAPI(); api.pr['head']['sha'] = 'c' * 40
        self.run_controller(api)
        self.assert_not_dispatched(api)

    def test_unauthorized_label_actor_is_rejected(self):
        api = FakeAPI(); api.events[0]['actor']['login'] = 'outside'
        self.run_controller(api)
        self.assert_not_dispatched(api)

    def test_push_removes_label_and_invalidates_approval(self):
        api = FakeAPI()
        self.run_controller(api, {'action': 'synchronize', 'pull_request': api.pr}, 'pull_request_target')
        self.assertTrue(any(call[1] == 'DELETE' for call in api.calls))
        self.assertTrue(any(call[2] and call[2].get('context') == APPROVAL and call[2].get('state') == 'failure'
                            for call in api.calls))
        self.assert_not_dispatched(api)

    def test_older_merged_commit_is_superseded(self):
        api = FakeAPI(); api.master = 'c' * 40
        self.run_controller(api)
        self.assertFalse(any(call[0].endswith('/dispatches') for call in api.calls))

    def test_dispatch_failure_publishes_fixed_failure_status(self):
        api = FakeAPI(); api.dispatch_fails = True
        with self.assertRaises(RuntimeError): self.run_controller(api)
        self.assertTrue(any(call[2] and call[2].get('context') == DEPLOYMENT and call[2].get('state') == 'failure'
                            for call in api.calls))


class ClientTests(unittest.TestCase):
    def test_dispatch_token_is_scoped_to_one_subprocess(self):
        result = subprocess.CompletedProcess([], 0, '', '')
        with patch.dict(os.environ, {'GH_TOKEN': 'test-public-token', 'GH_DEBUG': 'api'}), \
                patch('control.subprocess.run', return_value=result) as run:
            GitHub().request('repos/haturatu/cftf-deploy/actions/workflows/apply.yml/dispatches',
                             method='POST', data={'ref': 'master'}, token='test-dispatch-token')
            self.assertEqual(run.call_args.kwargs['env']['GH_TOKEN'], 'test-dispatch-token')
            self.assertNotIn('GH_DEBUG', run.call_args.kwargs['env'])
            self.assertEqual(os.environ['GH_TOKEN'], 'test-public-token')
            self.assertEqual(json.loads(run.call_args.kwargs['input']), {'ref': 'master'})

    def test_pagination_preserves_all_check_runs(self):
        with patch.object(GitHub, 'request', return_value=[{'check_runs': [1]}, {'check_runs': [2]}]):
            self.assertEqual(GitHub().pages('checks', 'check_runs'), [1, 2])

    def test_api_errors_do_not_expose_cli_diagnostics(self):
        result = subprocess.CompletedProcess([], 1, '', 'private diagnostic')
        with patch('control.subprocess.run', return_value=result):
            with self.assertRaisesRegex(RuntimeError, '^GitHub API request failed\.$'):
                GitHub().request('repos/haturatu/cftf')


if __name__ == '__main__':
    unittest.main()
