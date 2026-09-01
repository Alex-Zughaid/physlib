// Shared helpers for the review claim workflows.
//
// A claim is a promise to review a PR within a window: a reviewer comments
// `claim` (optionally with a window) and the bot records that promise, reminds
// them as the deadline approaches and releases the claim if it goes stale.
//
// The whole state of a claim lives in one bot-maintained comment per PR, in a
// hidden marker holding a JSON record.  That comment is edited in place rather
// than reposted, so a PR accumulates at most one claim status comment however
// many times the claim is extended, and there is nothing to keep in sync
// anywhere else.
//
// Used by `.github/workflows/review_claim.yml` (commands) and
// `.github/workflows/review_claim_expiry.yml` (reminders and expiry).

const CLAIM_LABEL = 'review-claimed';
const MARKER_PREFIX = '<!-- review-claim ';
const MARKER_SUFFIX = ' -->';

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

// A review claim is a short promise, so the windows are much tighter than the
// roadmap intentions this is modelled on.
const DEFAULT_WINDOW_MS = 2 * DAY_MS;
const MAX_WINDOW_MS = 14 * DAY_MS;
const MIN_WINDOW_MS = 1 * HOUR_MS;

// Reminders are @-mentions sent this many hours before the deadline.  A
// reminder is skipped when it is not shorter than the window itself, so a
// 24 hour claim is never warned about 24 hours before it ends.  Ascending, so
// that the smallest applicable reminder wins if a scheduled run is skipped.
const REMINDERS_HOURS = [24, 48];

const UNITS = {
  hour: HOUR_MS, hours: HOUR_MS,
  day: DAY_MS, days: DAY_MS,
  week: 7 * DAY_MS, weeks: 7 * DAY_MS,
};

/** Format a timestamp the way the bot's comments always spell one out. */
const formatUTC = when => new Date(when).toISOString().replace('T', ' ').slice(0, 16) + ' UTC';

/** Spell a duration back to the claimant, so they can check what was understood. */
function describeWindow(ms) {
  const round = value => Number(value.toFixed(1)).toString();
  if (ms % DAY_MS === 0 && ms >= DAY_MS) {
    const days = ms / DAY_MS;
    return days % 7 === 0
      ? `${round(days / 7)} week${days === 7 ? '' : 's'}`
      : `${round(days)} day${days === 1 ? '' : 's'}`;
  }
  const hours = ms / HOUR_MS;
  return `${round(hours)} hour${hours === 1 ? '' : 's'}`;
}

/**
 * Parse the argument of a `claim` command into a deadline.
 *
 * Accepts an empty argument (the default window), `<n> hours|days|weeks`, or an
 * absolute `YYYY-MM-DD` date, which is read as the end of that day UTC.  Over-long
 * windows are clamped rather than rejected, and the caller is told via `clamped`.
 */
function parseWindow(argument, now) {
  const trimmed = (argument || '').trim().toLowerCase();

  let until;
  if (trimmed === '') {
    until = now + DEFAULT_WINDOW_MS;
  } else if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    until = Date.parse(`${trimmed}T23:59:59Z`);
    if (Number.isNaN(until)) return { error: `\`${trimmed}\` is not a real date.` };
  } else {
    const match = trimmed.match(/^(\d+)\s*(hour|hours|day|days|week|weeks)$/);
    if (!match) {
      return {
        error: `I could not read \`${trimmed}\` as a window. Use \`claim\`, ` +
          '`claim 5 days` (or hours/weeks), or `claim 2026-08-01`.',
      };
    }
    until = now + Number(match[1]) * UNITS[match[2]];
  }

  if (until - now < MIN_WINDOW_MS) {
    return { error: 'That window is already over. Pick a deadline in the future.' };
  }
  const clamped = until - now > MAX_WINDOW_MS;
  if (clamped) until = now + MAX_WINDOW_MS;
  return { until, clamped };
}

/**
 * Read a command out of a comment body.
 *
 * As elsewhere in this repository, a command is a whole line: the bot reacts to
 * a line whose entire content, up to whitespace, is the command, so that a
 * comment merely discussing claims does not trigger one.  The last command in a
 * comment wins.
 */
function parseCommand(body) {
  const lines = (body || '').replace(/\r/g, '').split('\n');
  let command = null;
  for (const line of lines) {
    const trimmed = line.trim();
    const claim = trimmed.match(/^claim\b(.*)$/i);
    if (claim) command = { name: 'claim', argument: claim[1] };
    else if (/^disclaim$/i.test(trimmed)) command = { name: 'disclaim' };
  }
  return command;
}

/** The status comment among an already-fetched list, or null if there is none. */
function pickStatusComment(comments) {
  return [...comments].reverse()
    .find(comment => comment.body && comment.body.includes(MARKER_PREFIX)) || null;
}

/** The bot's status comment for this PR, or null if it has never claimed one. */
async function findStatusComment(github, { owner, repo, issue_number }) {
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner, repo, issue_number, per_page: 100,
  });
  return pickStatusComment(comments);
}

/** The claim record carried by a status comment, or null if it is unreadable. */
function readClaim(comment) {
  if (!comment || !comment.body) return null;
  const start = comment.body.indexOf(MARKER_PREFIX);
  if (start === -1) return null;
  const end = comment.body.indexOf(MARKER_SUFFIX, start);
  if (end === -1) return null;
  const json = comment.body.slice(start + MARKER_PREFIX.length, end);
  try {
    return JSON.parse(json);
  } catch (error) {
    return null;
  }
}

/** Render the status comment body for a claim record. */
function renderStatus(claim) {
  const marker = MARKER_PREFIX + JSON.stringify(claim) + MARKER_SUFFIX;

  if (claim.state === 'released') {
    return [marker, `Review claim by @${claim.claimant} released. This PR is back in the review queue.`].join('\n');
  }
  if (claim.state === 'completed') {
    return [marker, `Review claim by @${claim.claimant} completed — thanks for the review.`].join('\n');
  }
  if (claim.state === 'expired') {
    return [
      marker,
      `Review claim by @${claim.claimant} expired on ${formatUTC(claim.until)} without a review.`,
      'This PR is back in the review queue.',
    ].join('\n');
  }

  const window = describeWindow(claim.until - claim.claimedAt);
  const reminders = REMINDERS_HOURS
    .filter(hours => hours * HOUR_MS < claim.until - claim.claimedAt)
    .sort((a, b) => b - a);

  return [
    marker,
    `**@${claim.claimant} has claimed this PR for review** until ${formatUTC(claim.until)} (${window}).`,
    '',
    reminders.length
      ? `I will remind them here ${reminders.map(h => `${h}h`).join(' and ')} before that runs out.`
      : 'That window is too short for a reminder, so there will not be one.',
    'If no review lands in time the claim is released automatically and this PR returns to',
    'the review queue.',
    '',
    'Comment `claim` to extend, `claim 5 days` / `claim 2026-08-01` for a specific window, or',
    '`disclaim` to release it early. A claim is cooperative, not a lock: it signals intent so',
    'that others can steer around it, and anyone is still free to review this PR.',
  ].join('\n');
}

/** Create or edit the single status comment carrying the claim record. */
async function writeStatus(github, { owner, repo, issue_number }, claim, existing) {
  const body = renderStatus(claim);
  if (existing) {
    await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body });
    return existing;
  }
  const { data } = await github.rest.issues.createComment({ owner, repo, issue_number, body });
  return data;
}

/**
 * Has the claimant looked at the PR since claiming it?  A submitted review or an
 * inline review comment both count; a plain issue comment deliberately does not.
 */
async function hasReviewedSince(github, { owner, repo, issue_number }, claimant, since) {
  const reviews = await github.paginate(github.rest.pulls.listReviews, {
    owner, repo, pull_number: issue_number, per_page: 100,
  });
  if (reviews.some(review =>
    review.user.login === claimant && Date.parse(review.submitted_at) >= since)) return true;

  const reviewComments = await github.paginate(github.rest.pulls.listReviewComments, {
    owner, repo, pull_number: issue_number, per_page: 100,
  });
  return reviewComments.some(comment =>
    comment.user.login === claimant && Date.parse(comment.created_at) >= since);
}

/**
 * Put the claimant on the PR as both assignee and requested reviewer.
 *
 * Requesting a review is the half that shows up in everyone's review queue, but
 * GitHub refuses it for a non-collaborator and for the PR's own author, and
 * claiming deliberately needs no permissions -- so that half is best-effort.
 */
async function takeClaim(github, core, { owner, repo, issue_number }, claimant) {
  await github.rest.issues.addLabels({ owner, repo, issue_number, labels: [CLAIM_LABEL] })
    .catch(error => core.warning(`#${issue_number}: could not label: ${error.message}`));
  await github.rest.issues.addAssignees({ owner, repo, issue_number, assignees: [claimant] })
    .catch(error => core.warning(`#${issue_number}: could not assign '${claimant}': ${error.message}`));
  await github.rest.pulls.requestReviewers({ owner, repo, pull_number: issue_number, reviewers: [claimant] })
    .catch(error => core.warning(`#${issue_number}: could not request review from '${claimant}': ${error.message}`));
}

/**
 * Drop the claim label and, when a claimant is given, take them back off the PR
 * as reviewer and assignee.  Every step tolerates its target being gone already.
 */
async function releaseClaim(github, core, { owner, repo, issue_number }, claimant) {
  await github.rest.issues.removeLabel({ owner, repo, issue_number, name: CLAIM_LABEL })
    .catch(error => core.warning(`#${issue_number}: could not remove '${CLAIM_LABEL}': ${error.message}`));
  if (!claimant) return;
  await github.rest.issues.removeAssignees({ owner, repo, issue_number, assignees: [claimant] })
    .catch(error => core.warning(`#${issue_number}: could not unassign '${claimant}': ${error.message}`));
  await github.rest.pulls.removeRequestedReviewers({ owner, repo, pull_number: issue_number, reviewers: [claimant] })
    .catch(error => core.warning(`#${issue_number}: could not drop the review request for '${claimant}': ${error.message}`));
}

/**
 * Announce something on Zulip, using the same bot credentials and message API as
 * the workers in Alex-Zughaid/PhysLibBots.
 *
 * A missing or broken Zulip setup must never take a workflow down with it: the
 * GitHub side of an expiry has already happened by the time this is called, so a
 * failure here is warned about and swallowed.
 */
async function notifyZulip(core, content) {
  const { ZULIP_SITE, ZULIP_BOT_EMAIL, ZULIP_BOT_API_KEY, ZULIP_STREAM, ZULIP_TOPIC } = process.env;
  if (!ZULIP_SITE || !ZULIP_BOT_EMAIL || !ZULIP_BOT_API_KEY || !ZULIP_STREAM) {
    core.warning('Zulip is not configured (ZULIP_SITE / ZULIP_BOT_EMAIL / ZULIP_BOT_API_KEY / ZULIP_STREAM), skipping the announcement.');
    return false;
  }

  // `to` takes a stream name or a stream id, so ZULIP_STREAM can be either.
  const body = new URLSearchParams({
    type: 'stream', to: ZULIP_STREAM, topic: ZULIP_TOPIC || 'PR reviews', content,
  });
  const credentials = Buffer.from(`${ZULIP_BOT_EMAIL}:${ZULIP_BOT_API_KEY}`).toString('base64');

  try {
    const response = await fetch(`${ZULIP_SITE.replace(/\/$/, '')}/api/v1/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    });
    if (!response.ok) {
      core.warning(`Zulip API error: ${response.status} ${await response.text()}`);
      return false;
    }
    return true;
  } catch (error) {
    core.warning(`Could not reach Zulip: ${error.message}`);
    return false;
  }
}

module.exports = {
  CLAIM_LABEL, HOUR_MS, DAY_MS, REMINDERS_HOURS,
  DEFAULT_WINDOW_MS, MAX_WINDOW_MS,
  formatUTC, describeWindow, parseWindow, parseCommand,
  pickStatusComment, findStatusComment, readClaim, renderStatus, writeStatus,
  hasReviewedSince, takeClaim, releaseClaim, notifyZulip,
};
