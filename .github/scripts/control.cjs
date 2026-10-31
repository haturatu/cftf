'use strict';

const LABEL = 'terraform-apply';
const APPROVAL = 'terraform/apply-approved';
const DEPLOYMENT = 'terraform/deploy';
const CHECK = 'Terraform checks';
const SHA = /^[0-9a-f]{40}$/;

function eligible(pr, repository) {
  return !pr.draft && pr.base.ref === 'master' &&
    pr.base.repo.full_name === repository && pr.head.repo?.full_name === repository &&
    SHA.test(pr.head.sha) && pr.labels.some(label => label.name === LABEL);
}

function currentApproval(statuses, actor) {
  const latest = statuses.find(status => status.context === APPROVAL);
  return latest?.state === 'success' && latest.creator?.login === 'github-actions[bot]' &&
    latest.description === `Approved for deployment by ${actor}`;
}

function checksPassed(runs) {
  const latest = runs.filter(run => run.name === CHECK && run.app?.slug === 'github-actions')
    .sort((a, b) => b.id - a.id)[0];
  return latest?.status === 'completed' && latest.conclusion === 'success';
}

function reviewsPermit(reviews) {
  const latest = new Map();
  for (const review of [...reviews].sort((a, b) => a.id - b.id)) {
    if (review.state !== 'COMMENTED' && review.state !== 'PENDING') latest.set(review.user.login, review.state);
  }
  return ![...latest.values()].includes('CHANGES_REQUESTED');
}

async function main({github, context, core}) {
  try {
    await control({github, context, core});
  } catch {
    // Public logs intentionally omit API responses, tokens, and private workflow details.
    core.setFailed('Deployment request failed. Review repository configuration privately.');
  }
}

async function control({github, context, core}) {
  const {owner, repo} = context.repo;
  const repository = `${owner}/${repo}`;
  if (repository !== 'haturatu/cftf') throw new Error('Unexpected repository');
  const allowed = JSON.parse(process.env.ALLOWED_APPLIERS || '["haturatu"]');
  if (!Array.isArray(allowed) || allowed.some(actor => typeof actor !== 'string')) throw new Error('Invalid allowlist');
  const api = github.rest;
  const permission = async actor => {
    if (!allowed.includes(actor)) return false;
    const {data} = await api.repos.getCollaboratorPermissionLevel({owner, repo, username: actor});
    return ['admin', 'maintain', 'write'].includes(data.permission);
  };
  const status = (sha, state, description, contextName = APPROVAL) =>
    api.repos.createCommitStatus({owner, repo, sha, state, context: contextName, description});
  const event = context.payload;
  const eventPr = event.pull_request;
  if (context.eventName === 'pull_request_target' && eventPr) {
    if (event.action === 'synchronize') {
      if (eventPr.labels.some(label => label.name === LABEL)) {
        await api.issues.removeLabel({owner, repo, issue_number: eventPr.number, name: LABEL});
      }
      await status(eventPr.head.sha, 'failure', 'Relabel the current commit to authorize deployment.');
      core.info('Approval invalidated after a commit update.');
      return;
    }
    if (event.action === 'unlabeled' && event.label?.name === LABEL) {
      await status(eventPr.head.sha, 'failure', 'Deployment approval removed.');
      return;
    }
    if (event.action === 'labeled') {
      if (event.label?.name !== LABEL || !eligible(eventPr, repository) || !await permission(event.sender.login)) {
        core.info('No authorized deployment request.');
        return;
      }
      await status(eventPr.head.sha, 'success', `Approved for deployment by ${event.sender.login}`);
    }
  }
  let numbers;
  if (context.eventName === 'workflow_dispatch') {
    const input = core.getInput('pr');
    // workflow_dispatch inputs are event payload fields, not action inputs.
    const number = event.inputs?.pr || input;
    if (!/^[1-9][0-9]*$/.test(number || '') || !await permission(context.actor)) throw new Error('Invalid retry');
    numbers = [Number(number)];
  } else if (eventPr) {
    numbers = [eventPr.number];
  } else {
    const prs = await github.paginate(api.pulls.list, {owner, repo, state: 'open', base: 'master', per_page: 100});
    numbers = prs.filter(pr => eligible(pr, repository)).map(pr => pr.number);
  }
  for (const pull_number of numbers) {
    const {data: pr} = await api.pulls.get({owner, repo, pull_number});
    if (!eligible(pr, repository) || (!pr.merged && pr.state !== 'open')) continue;
    const events = await github.paginate(api.issues.listEvents, {owner, repo, issue_number: pull_number, per_page: 100});
    const lastLabel = events.filter(item => ['labeled', 'unlabeled'].includes(item.event) && item.label?.name === LABEL).at(-1);
    if (lastLabel?.event !== 'labeled' || !await permission(lastLabel.actor.login)) continue;
    const statuses = await github.paginate(api.repos.listCommitStatusesForRef, {owner, repo, ref: pr.head.sha, per_page: 100});
    if (!currentApproval(statuses, lastLabel.actor.login)) continue;
    const checks = await github.paginate(api.checks.listForRef, {owner, repo, ref: pr.head.sha, per_page: 100});
    if (!checksPassed(checks)) continue;
    const reviews = await github.paginate(api.pulls.listReviews, {owner, repo, pull_number, per_page: 100});
    if (!reviewsPermit(reviews)) continue;
    let mergeSha = pr.merge_commit_sha;
    if (!pr.merged) {
      const {data: merged} = await api.pulls.merge({owner, repo, pull_number, sha: pr.head.sha, merge_method: 'squash'});
      if (!merged.merged || !SHA.test(merged.sha)) throw new Error('Merge rejected');
      mergeSha = merged.sha;
    }
    if (!SHA.test(mergeSha || '')) throw new Error('Invalid merged commit');
    const {data: master} = await api.git.getRef({owner, repo, ref: 'heads/master'});
    if (master.object.sha !== mergeSha) {
      await status(mergeSha, 'success', 'Superseded by a newer merged commit.', DEPLOYMENT);
      continue;
    }
    await status(mergeSha, 'pending', 'Private deployment requested.', DEPLOYMENT);
    const response = await fetch('https://api.github.com/repos/haturatu/cftf-deploy/actions/workflows/apply.yml/dispatches', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.DISPATCH_TOKEN}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ref: 'master', inputs: {pr: String(pull_number), sha: mergeSha}})
    });
    if (response.status !== 204) {
      await status(mergeSha, 'failure', 'Private deployment request failed.', DEPLOYMENT);
      throw new Error('Dispatch rejected');
    }
    core.info('Checked code merged and private deployment requested.');
    // Re-evaluate other pending requests against the new base on a later event.
    return;
  }
  core.info('No checked, current deployment approval is ready.');
}

module.exports = {main, eligible, currentApproval, checksPassed, reviewsPermit};
