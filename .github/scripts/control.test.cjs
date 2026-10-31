'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {main, eligible, currentApproval, checksPassed, reviewsPermit} = require('./control.cjs');

const repository = 'haturatu/cftf';
const pr = () => ({draft: false, base: {ref: 'master', repo: {full_name: repository}}, head: {sha: 'a'.repeat(40), repo: {full_name: repository}}, labels: [{name: 'terraform-apply'}]});

test('only labeled, non-draft requests from the same repository are eligible', () => {
  assert.equal(eligible(pr(), repository), true);
  for (const change of [{draft: true}, {labels: []}, {head: {sha: 'a'.repeat(40), repo: {full_name: 'outside/fork'}}}]) {
    assert.equal(eligible({...pr(), ...change}, repository), false);
  }
});
test('only the latest approval from the trusted controller authorizes a commit', () => {
  const approved = {context: 'terraform/apply-approved', state: 'success', creator: {login: 'github-actions[bot]'}, description: 'Approved for deployment by haturatu'};
  assert.equal(currentApproval([approved], 'haturatu'), true);
  assert.equal(currentApproval([{...approved, state: 'failure'}, approved], 'haturatu'), false);
  assert.equal(currentApproval([{...approved, creator: {login: 'outsider'}}], 'haturatu'), false);
  assert.equal(currentApproval([], 'haturatu'), false);
});
test('a newer failed or pending check overrides an old success', () => {
  const passed = {id: 1, name: 'Terraform checks', app: {slug: 'github-actions'}, status: 'completed', conclusion: 'success'};
  assert.equal(checksPassed([passed]), true);
  assert.equal(checksPassed([passed, {...passed, id: 2, conclusion: 'failure'}]), false);
  assert.equal(checksPassed([{...passed, app: {slug: 'other'}}]), false);
});
test('unresolved requested changes prevent merging', () => {
  const blocked = {id: 1, user: {login: 'reviewer'}, state: 'CHANGES_REQUESTED'};
  assert.equal(reviewsPermit([blocked]), false);
  assert.equal(reviewsPermit([blocked, {id: 2, user: {login: 'reviewer'}, state: 'COMMENTED'}]), false);
  assert.equal(reviewsPermit([blocked, {id: 3, user: {login: 'reviewer'}, state: 'APPROVED'}]), true);
});

async function simulate(checkConclusion) {
  const head = 'a'.repeat(40);
  const merged = 'b'.repeat(40);
  const request = {...pr(), number: 1, state: 'open', merged: false};
  const calls = [];
  const list = () => {};
  const events = () => {};
  const statuses = () => {};
  const checks = () => {};
  const reviews = () => {};
  const data = new Map([
    [list, [request]],
    [events, [{event: 'labeled', label: {name: 'terraform-apply'}, actor: {login: 'haturatu'}}]],
    [statuses, [{context: 'terraform/apply-approved', state: 'success', creator: {login: 'github-actions[bot]'}, description: 'Approved for deployment by haturatu'}]],
    [checks, [{id: 1, name: 'Terraform checks', app: {slug: 'github-actions'}, status: 'completed', conclusion: checkConclusion}]],
    [reviews, []]
  ]);
  const github = {
    paginate: async method => data.get(method),
    rest: {
      pulls: {list, get: async () => ({data: request}), listReviews: reviews, merge: async args => {
        assert.equal(args.sha, head); calls.push('merge'); return {data: {merged: true, sha: merged}};
      }},
      repos: {getCollaboratorPermissionLevel: async () => ({data: {permission: 'admin'}}),
        listCommitStatusesForRef: statuses, createCommitStatus: async () => {}},
      issues: {listEvents: events}, checks: {listForRef: checks},
      git: {getRef: async () => ({data: {object: {sha: merged}}})}
    }
  };
  const previous = global.fetch;
  global.fetch = async (url, options) => {
    calls.push('dispatch');
    assert.equal(JSON.parse(options.body).inputs.sha, merged);
    assert.notEqual(JSON.parse(options.body).inputs.sha, head);
    return {status: 204};
  };
  let failed = false;
  try {
    await main({github, context: {repo: {owner: 'haturatu', repo: 'cftf'}, eventName: 'workflow_run', payload: {}},
      core: {info: () => {}, setFailed: () => {failed = true;}}});
  } finally { global.fetch = previous; }
  assert.equal(failed, false);
  return calls;
}

test('private deployment receives only the merged SHA after a checked merge', async () => {
  assert.deepEqual(await simulate('success'), ['merge', 'dispatch']);
});
test('failed public checks prevent both merge and private dispatch', async () => {
  assert.deepEqual(await simulate('failure'), []);
});
