#!/usr/bin/env node

/* eslint-disable no-console -- CLI script output is its contract. */

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const MAX_LOG_PREVIEW_CHARS = 400;
const REVIEW_OUTCOME_FILE = '.review-outcome';
const USAGE = `Usage: submit-review.mjs <owner> <repo> <pr_number> <comments_file>

Each comment must have: path (string), line (number), side ('RIGHT' or 'LEFT'), body (string), severity ('critical' or 'warning')`;

const [owner, repo, prNumber, commentsFile] = process.argv.slice(2);

main();

function main() {
  validateArgs();

  if (!existsSync(commentsFile)) {
    submitMissingFileReview();
    return;
  }

  const comments = readComments();
  const reviewSummary = readReviewSummary();
  const headSha = getHeadSha();

  console.log(`Submitting review for PR #${prNumber} (commit: ${headSha.slice(0, 7)})`);

  if (reviewSummary && reviewSummary.summary?.totalReviewedRules === 0) {
    submitReview(
      headSha,
      'COMMENT',
      '⚠️ **Review did not complete** — 0 rules were evaluated. The review agent may have failed to follow the CLI workflow. Check the CI run logs.',
    );
    writeOutcome('ERROR');
    console.log('Posted incomplete-review warning. Exiting.');
    process.exit(1);
  }

  if (comments.length === 0) {
    submitReview(headSha, 'APPROVE', reviewSummary?.body ?? 'Code review passed. No issues found.');
    writeOutcome('APPROVE');
    console.log('Review submitted: APPROVED (no issues found).');
    return;
  }

  const { cleaned, dropped } = sanitizeComments(comments, getDiff());
  printDroppedComments(dropped);

  if (cleaned.length === 0) {
    submitInconclusiveReview(headSha, dropped, reviewSummary);
    return;
  }

  submitInlineReview(headSha, cleaned, dropped, reviewSummary);
}

function readReviewSummary() {
  const reportFile = join(dirname(commentsFile), 'review-report.json');
  if (!existsSync(reportFile)) {
    return null;
  }

  try {
    const parsed = JSON.parse(readFileSync(reportFile, 'utf8'));
    return typeof parsed?.githubReview?.body === 'string' ? parsed.githubReview : null;
  } catch {
    return null;
  }
}

function validateArgs() {
  if (!owner || !repo || !prNumber || !commentsFile) {
    console.log(USAGE);
    process.exit(1);
  }

  if (!/^\d+$/.test(prNumber)) {
    console.log(`Error: pr_number must be a number, got: '${prNumber}'`);
    process.exit(1);
  }
}

function submitMissingFileReview() {
  console.log(`Warning: Comments file not found: ${commentsFile}`);
  console.log(
    'Submitting a neutral comment to indicate the review agent could not write its findings.',
  );

  submitReview(
    getHeadSha(),
    'COMMENT',
    'Review agent error: could not write review-comments.json. Check the CI run logs for findings reported via stdout.',
  );

  writeOutcome('ERROR');
  console.log('Posted error comment on PR. Exiting with non-zero to fail the CI step.');
  process.exit(1);
}

function readComments() {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(commentsFile, 'utf8'));
  } catch {
    console.log('Error: File does not contain valid JSON.');
    console.log(`File size: ${readFileSync(commentsFile, 'utf8').length} bytes`);
    process.exit(1);
  }

  if (!Array.isArray(parsed)) {
    console.log(`Error: JSON must be an array, got: ${typeof parsed}`);
    process.exit(1);
  }

  validateComments(parsed);
  return parsed;
}

function validateComments(comments) {
  const missingRequired = comments.filter(hasMissingRequiredField);
  if (missingRequired.length > 0) {
    console.log(
      `Error: ${missingRequired.length} comment(s) are missing required fields (path, line, side, body, severity).`,
    );
    console.log(JSON.stringify(missingRequired, null, 2));
    process.exit(1);
  }

  const invalidSeverity = comments.filter(
    ({ severity }) => severity !== 'critical' && severity !== 'warning',
  );
  if (invalidSeverity.length > 0) {
    console.log(
      `Error: ${invalidSeverity.length} comment(s) have invalid severity (must be 'critical' or 'warning').`,
    );
    console.log(JSON.stringify(invalidSeverity, null, 2));
    process.exit(1);
  }
}

function hasMissingRequiredField(comment) {
  return ['path', 'line', 'side', 'body', 'severity'].some((field) => comment[field] == null);
}

function getHeadSha() {
  const result = runGh([
    'pr',
    'view',
    prNumber,
    '--repo',
    `${owner}/${repo}`,
    '--json',
    'headRefOid',
    '--jq',
    '.headRefOid',
  ]);
  const headSha = result.stdout.trim();

  if (!headSha) {
    console.log(`Error: Could not get HEAD SHA for PR #${prNumber} in ${owner}/${repo}`);
    process.exit(1);
  }

  return headSha;
}

function getDiff() {
  return runGh(['pr', 'diff', prNumber, '--repo', `${owner}/${repo}`]).stdout;
}

function sanitizeComments(comments, diff) {
  const hunksByPath = parseHunks(diff);
  const cleaned = [];
  const dropped = [];

  for (const comment of comments) {
    if (isResolvable(comment, hunksByPath.get(comment.path))) {
      cleaned.push(toGithubComment(comment));
      continue;
    }

    dropped.push({
      ...comment,
      rule: comment.rule ?? null,
      reason: 'Line is outside the PR diff hunks for this file/side.',
    });
  }

  return { cleaned, dropped };
}

function parseHunks(patchText) {
  const hunksByPath = new Map();
  let currentPath = null;
  let oldPath = null;

  for (const line of patchText.split('\n')) {
    if (line.startsWith('--- a/')) {
      oldPath = line.slice('--- a/'.length);
      continue;
    }

    // A deleted file has no `+++ b/` path; its hunks belong to the old path.
    if (line.startsWith('+++ b/') || line === '+++ /dev/null') {
      currentPath = line === '+++ /dev/null' ? oldPath : line.slice('+++ b/'.length);
      oldPath = null;
      if (currentPath) {
        hunksByPath.set(currentPath, hunksByPath.get(currentPath) ?? []);
      }
      continue;
    }

    const match = currentPath ? /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line) : null;
    if (!match) {
      continue;
    }

    hunksByPath.get(currentPath).push({
      oldStart: Number(match[1]),
      oldEnd: Number(match[1]) + Number(match[2] ?? '1') - 1,
      newStart: Number(match[3]),
      newEnd: Number(match[3]) + Number(match[4] ?? '1') - 1,
    });
  }

  return hunksByPath;
}

function isResolvable(comment, hunks) {
  if (!hunks?.length) {
    return false;
  }

  const range = comment.side === 'LEFT' ? ['oldStart', 'oldEnd'] : ['newStart', 'newEnd'];
  return hunks.some((hunk) => comment.line >= hunk[range[0]] && comment.line <= hunk[range[1]]);
}

function toGithubComment(comment) {
  const badge = comment.severity === 'critical' ? '🚨 **Critical**' : '⚠️ **Warning**';
  const ruleTag = comment.rule ? ` · \`${comment.rule}\`` : '';
  const header = `${badge}${ruleTag}\n\n`;
  return {
    path: comment.path,
    line: comment.line,
    side: comment.side,
    body: `${header}${comment.body}`,
    severity: comment.severity,
  };
}

function printDroppedComments(dropped) {
  if (dropped.length === 0) {
    return;
  }

  console.log(`Dropped ${dropped.length} unresolvable comment(s) before posting review.`);
  for (const comment of dropped) {
    console.log(
      `- [${comment.rule ?? 'no-rule'}] ${comment.path}:${comment.line} ${comment.reason}`,
    );
  }
}

/**
 * Renders findings that could not be anchored to a changed line as a markdown
 * section appended to the review body. GitHub rejects inline comments on lines
 * outside the PR diff, so instead of silently discarding these findings we
 * reproduce each one in full — with its exact location, severity, and rule — and
 * flag the review as inconclusive so a human reviews them manually.
 */
function renderDroppedFindings(dropped) {
  const header = [
    '',
    '---',
    '',
    '### ⚠️ Review inconclusive — human review required',
    '',
    `${dropped.length} finding(s) below could **not** be posted as inline comments because their ` +
      "target line is not part of this PR's diff (for example, the line changed in an earlier commit " +
      'but nets to no change versus the base branch, so GitHub rejects an inline comment there). ' +
      'They are reproduced in full so nothing is lost — please review each one manually against the ' +
      'referenced location.',
  ].join('\n');

  const items = dropped.map((comment) => {
    const badge = comment.severity === 'critical' ? '🚨 **Critical**' : '⚠️ **Warning**';
    const ruleTag = comment.rule ? ` · \`${comment.rule}\`` : '';
    const location = `\`${comment.path}\`:${comment.line} (${comment.side} side)`;
    return `\n#### ${badge}${ruleTag} — ${location}\n\n${comment.body}`;
  });

  return `${header}\n${items.join('\n')}`;
}

function submitInconclusiveReview(headSha, dropped, reviewSummary) {
  const base =
    reviewSummary?.body ??
    `Review found ${dropped.length} issue(s), but none target changed lines in the PR diff.`;

  submitReview(headSha, 'COMMENT', `${base}\n${renderDroppedFindings(dropped)}`);
  writeOutcome('INCONCLUSIVE');
  console.log(
    `Review submitted: INCONCLUSIVE (${dropped.length} finding(s) could not be anchored to the PR ` +
      'diff and were reproduced in the review body for human review).',
  );
}

function submitInlineReview(headSha, cleaned, dropped, reviewSummary) {
  const criticalCount = countBySeverity(cleaned, 'critical');
  const warningCount = countBySeverity(cleaned, 'warning');
  const event = selectReviewEvent(reviewSummary, criticalCount, warningCount);
  const baseBody =
    reviewSummary?.body ??
    (criticalCount > 0
      ? `Found ${criticalCount} critical and ${warningCount} warning issue(s). See inline comments.`
      : `Approved. Left ${warningCount} non-blocking comment(s) for your consideration.`);
  const body = dropped.length > 0 ? `${baseBody}\n${renderDroppedFindings(dropped)}` : baseBody;

  // Findings we could not anchor to the diff mean the review is not a clean pass:
  // downgrade an APPROVE to a neutral COMMENT event + INCONCLUSIVE outcome so a
  // human looks at the dropped findings reproduced in the body. A REQUEST_CHANGES
  // already fails CI, so it is left as-is (the dropped findings ride along in the body).
  const inconclusive = dropped.length > 0 && event === 'APPROVE';
  const finalEvent = inconclusive ? 'COMMENT' : event;

  submitReview(headSha, finalEvent, body, cleaned.map(toPayloadComment));
  writeOutcome(inconclusive ? 'INCONCLUSIVE' : event);
  logInlineReviewResult({ inconclusive, event, criticalCount, warningCount, dropped });
}

function logInlineReviewResult({ inconclusive, event, criticalCount, warningCount, dropped }) {
  const droppedNote = dropped.length > 0 ? `, ${dropped.length} unanchored finding(s) in body` : '';

  if (inconclusive) {
    console.log(
      `Review submitted: INCONCLUSIVE (${warningCount} inline comment(s) posted; ${dropped.length} ` +
        'finding(s) could not be anchored and were reproduced in the review body for human review).',
    );
    return;
  }
  if (event === 'REQUEST_CHANGES') {
    console.log(
      `Review submitted: REQUESTED CHANGES (${criticalCount} critical, ${warningCount} warning${droppedNote}).`,
    );
    return;
  }
  console.log(`Review submitted: APPROVED with ${warningCount} non-blocking comment(s).`);
}

function selectReviewEvent(reviewSummary, criticalCount, warningCount) {
  if (reviewSummary?.event === 'APPROVE' || reviewSummary?.event === 'REQUEST_CHANGES') {
    return reviewSummary.event;
  }

  if (criticalCount > 0) {
    return 'REQUEST_CHANGES';
  }

  return 'APPROVE';
}

function countBySeverity(comments, severity) {
  return comments.filter((comment) => comment.severity === severity).length;
}

function toPayloadComment({ severity: _severity, reviewSummary: _reviewSummary, ...comment }) {
  return comment;
}

function submitReview(headSha, event, body, comments) {
  const payload = { commit_id: headSha, event, body };
  if (comments) {
    payload.comments = comments;
  }

  const tmpDir = mkdtempSync(join(tmpdir(), 'submit-review-'));
  const payloadPath = join(tmpDir, 'payload.json');

  try {
    writeFileSync(payloadPath, JSON.stringify(payload));
    const result = runGh(
      [
        'api',
        `repos/${owner}/${repo}/pulls/${prNumber}/reviews`,
        '--method',
        'POST',
        '--input',
        payloadPath,
      ],
      {
        failMessage: 'GitHub API call failed',
        printPayload: payload,
      },
    );
    return result.stdout;
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
}

function runGh(args, options = {}) {
  const result = spawnSync('gh', args, { encoding: 'utf8' });
  if (result.status === 0) {
    return result;
  }

  if (options.failMessage) {
    console.log(`Error: ${options.failMessage}.`);
    console.log(`Response: ${safeLogPreview(result.stderr || result.stdout)}`);
    if (options.printPayload) {
      console.log('');
      console.log('Common causes:');
      console.log('  - Invalid line number: the line must exist in the PR diff');
      console.log('  - Invalid path: the file must be part of the PR');
      console.log("  - Invalid side: must be 'RIGHT' or 'LEFT'");
      console.log('');
      console.log('Payload sent:');
      console.log(JSON.stringify(toSafePayloadSummary(options.printPayload), null, 2));
    }
  }

  process.exit(1);
}

/**
 * Writes the submitted GitHub review event to .review-outcome so the CI
 * workflow can map it to a commit status without querying the GitHub API.
 * Outcomes: APPROVE | REQUEST_CHANGES | INCONCLUSIVE | COMMENT | ERROR
 */
function writeOutcome(event) {
  try {
    writeFileSync(REVIEW_OUTCOME_FILE, event, 'utf8');
  } catch (err) {
    console.log(`Warning: could not write ${REVIEW_OUTCOME_FILE}: ${err.message}`);
  }
}

function safeLogPreview(value) {
  const redacted = value.replace(/(gh[pousr]_[A-Za-z0-9_]+)/g, '[REDACTED_TOKEN]');
  if (redacted.length <= MAX_LOG_PREVIEW_CHARS) {
    return redacted;
  }

  return `${redacted.slice(0, MAX_LOG_PREVIEW_CHARS)}... [truncated ${redacted.length - MAX_LOG_PREVIEW_CHARS} chars]`;
}

function toSafePayloadSummary(payload) {
  return {
    commit_id: payload.commit_id,
    event: payload.event,
    body_length: payload.body.length,
    comments_count: payload.comments?.length ?? 0,
  };
}
