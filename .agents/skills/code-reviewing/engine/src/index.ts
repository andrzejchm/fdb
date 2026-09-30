import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { fileURLToPath } from 'node:url';

import { classifyFromArgs, renderClassification } from './classify.ts';
import { compileFindings } from './compile.ts';
import {
  createChangedFilesHash,
  createPlanFromArgs,
  createPullRequestPlanFromArgs,
  markRoundComplete,
  renderPlan,
  renderPlanTasksFromArgs,
  renderStoredPrompt,
} from './plan.ts';
import { DOMAIN_ORDER, loadDomainRules, lookupRulesBySlug } from './rules.ts';
import {
  appendFinding,
  appendNote,
  commentsPath,
  ensureSessionDirectories,
  hasSession,
  loadBranchSessions,
  loadFindings,
  loadPlan,
  loadSession,
  planPath,
  readNotes,
  resetSession,
  reportPath,
  saveFindings,
  saveSession,
  sessionKey,
  severitySummary,
} from './session-store.ts';
import type {
  Domain,
  ReviewMetadataMarker,
  ReviewFinding,
  ReviewOutcomeSummary,
  ReviewSession,
  Rule,
  Severity,
  SkipReason,
} from './types.ts';

const SKIP_REASONS = [
  'changed-file-scope',
  'docs-only-change',
  'test-only-change',
  'no-relevant-runtime-surface',
  'other',
] as const satisfies readonly SkipReason[];

function die(message: string): never {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function getArg(args: string[], flag: string): string | null {
  const index = args.indexOf(flag);
  if (index === -1 || index + 1 >= args.length) {
    return null;
  }

  return args[index + 1];
}

function hasArg(args: string[], flag: string): boolean {
  return args.includes(flag);
}

function requireArg(args: string[], flag: string): string {
  const value = getArg(args, flag);
  if (!value) {
    die(`${flag} is required`);
  }
  return value;
}

function readFindingBody(args: string[]): string {
  const sources = [
    hasArg(args, '--body'),
    hasArg(args, '--body-file'),
    hasArg(args, '--body-stdin'),
  ].filter(Boolean).length;

  if (sources !== 1) {
    die('Use exactly one of --body, --body-file, or --body-stdin');
  }

  if (hasArg(args, '--body')) {
    return requireArg(args, '--body');
  }

  if (hasArg(args, '--body-file')) {
    const bodyPath = requireArg(args, '--body-file');
    try {
      return readFileSync(bodyPath, 'utf8');
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      die(`Could not read --body-file "${bodyPath}": ${message}`);
    }
  }

  if (process.stdin.isTTY) {
    die('--body-stdin requires piped stdin');
  }

  return readFileSync(0, 'utf8');
}

function parseDomain(value: string): Domain {
  if ((DOMAIN_ORDER as string[]).includes(value)) {
    return value as Domain;
  }

  die(`Unknown domain "${value}". Valid domains: ${DOMAIN_ORDER.join(', ')}`);
}

function printRule(session: ReviewSession): void {
  if (session.currentIndex >= session.rules.length) {
    const summary = severitySummary(session);
    console.log(
      `DOMAIN COMPLETE. critical ${summary.criticalDone}/${summary.criticalTotal}, warning ${summary.warningDone}/${summary.warningTotal}.`,
    );
    return;
  }

  const summary = severitySummary(session);
  const rule = session.rules[session.currentIndex];
  const position = session.currentIndex + 1;
  console.log(`RULE [${position}/${session.rules.length}] ${rule.slug} (${rule.severity})`);
  console.log(`PHASE: ${summary.phase}`);
  if (session.currentRuleFindings > 0) {
    console.log(
      `FINDINGS ON THIS RULE: ${session.currentRuleFindings}. Record more instances or close the rule with rule-done.`,
    );
  }
  console.log(rule.description);
}

function formatReviewCounts(summary: ReviewOutcomeSummary): string {
  return `passes=${summary.passedCount} skipped=${summary.skippedCount} findings=${summary.findingCount}`;
}

function summarizeReviewOutcomes(sessions: ReviewSession[]): ReviewOutcomeSummary {
  const passedCount = sessions.reduce((total, session) => total + session.passes, 0);
  const skippedCount = sessions.reduce((total, session) => total + session.skipped, 0);
  // findingCount counts finding instances; rules close via rule-done (findingRules).
  const findingCount = sessions.reduce((total, session) => total + session.findings, 0);
  const findingRuleCount = sessions.reduce((total, session) => total + session.findingRules, 0);

  return {
    totalReviewedRules: passedCount + skippedCount + findingRuleCount,
    passedCount,
    skippedCount,
    findingCount,
  };
}

function formatReviewedRulesSentence(summary: ReviewOutcomeSummary): string {
  return `Reviewed ${summary.totalReviewedRules} rule(s): ${summary.passedCount} passed, ${summary.skippedCount} skipped, ${summary.findingCount} findings.`;
}

type DomainReportRow = {
  domain: Domain;
  criticalTotal: number;
  criticalPassed: number;
  criticalSkipped: number;
  criticalFindings: number;
  warningTotal: number;
  warningPassed: number;
  warningSkipped: number;
  warningFindings: number;
  phase: 'critical' | 'warning' | 'complete';
};

export function buildGithubReviewBody(
  summary: ReviewOutcomeSummary,
  domains: DomainReportRow[],
  comments: ReviewFinding[],
  metadata?: ReviewMetadataMarker,
  carriedCriticals = 0,
): string {
  const criticalCount = comments.filter((c) => c.severity === 'critical').length;
  const warningCount = comments.filter((c) => c.severity === 'warning').length;
  const blockingCriticals = criticalCount + carriedCriticals;

  let header: string;
  if (summary.findingCount === 0 && carriedCriticals === 0) {
    header = '## Code Review — ✅ Approved';
  } else if (blockingCriticals > 0) {
    if (criticalCount === 0 && carriedCriticals > 0) {
      // No new criticals this round — only unaddressed prior criticals carried forward.
      // Use distinct text so the header is not contradicted by the table and footer showing 0 criticals.
      header = `## Code Review — 🚨 ${carriedCriticals} unaddressed prior critical(s)`;
    } else {
      header = `## Code Review — 🚨 ${blockingCriticals} critical finding(s)`;
    }
  } else {
    header = `## Code Review — ⚠️ ${warningCount} warning finding(s)`;
  }

  const completeDomains = domains.filter((d) => d.phase === 'complete');

  const tableRows = completeDomains.map((d) => {
    const criticalParts: string[] = [];
    if (d.criticalPassed > 0) criticalParts.push(`${d.criticalPassed}✅`);
    if (d.criticalSkipped > 0) criticalParts.push(`${d.criticalSkipped}⏭️`);
    if (d.criticalFindings > 0) criticalParts.push(`${d.criticalFindings}🚨`);
    const criticalContent = criticalParts.length > 0 ? criticalParts.join(' · ') : '—';
    const criticalCell = `**${criticalContent} / ${d.criticalTotal}**`;

    const warningParts: string[] = [];
    if (d.warningPassed > 0) warningParts.push(`${d.warningPassed}✅`);
    if (d.warningSkipped > 0) warningParts.push(`${d.warningSkipped}⏭️`);
    if (d.warningFindings > 0) warningParts.push(`${d.warningFindings}⚠️`);
    const warningContent = warningParts.length > 0 ? warningParts.join(' · ') : '—';
    const warningCell = `**${warningContent} / ${d.warningTotal}**`;

    return `| ${d.domain} | ${criticalCell} | ${warningCell} |`;
  });

  const tableHeader = '| Domain | Critical | Warning |\n|---|---|---|';
  const table = [tableHeader, ...tableRows].join('\n');

  let footer: string;
  if (summary.findingCount === 0 && carriedCriticals === 0) {
    footer = `**${summary.totalReviewedRules} rules reviewed** — ${summary.passedCount} passed · ${summary.skippedCount} skipped · 0 findings`;
  } else {
    const footerParts = [
      `${summary.passedCount} passed`,
      `${summary.skippedCount} skipped`,
      `${criticalCount} critical`,
      `${warningCount} warning`,
    ];
    if (carriedCriticals > 0) {
      footerParts.push(`${carriedCriticals} unaddressed prior critical(s)`);
    }
    footer = `**${summary.totalReviewedRules} rules reviewed** — ${footerParts.join(' · ')}`;
  }

  const reviewBody = `${header}\n\n${table}\n\n${footer}`;
  if (!metadata) {
    return reviewBody;
  }

  return `<!-- agentkit-code-review:v1 ${JSON.stringify(metadata)} -->\n\n${reviewBody}`;
}

export function selectGithubReviewEvent(
  comments: ReviewFinding[],
  carriedCriticals = 0,
): 'APPROVE' | 'REQUEST_CHANGES' {
  const criticalCount = comments.filter((c) => c.severity === 'critical').length;

  if (criticalCount > 0 || carriedCriticals > 0) {
    return 'REQUEST_CHANGES';
  }

  return 'APPROVE';
}

function formatStatusLine(session: ReviewSession): string {
  const summary = severitySummary(session);
  return `${sessionKey(session.domain, session.shard)}: phase=${summary.phase} critical ${summary.criticalDone}/${summary.criticalTotal}, warning ${summary.warningDone}/${summary.warningTotal}, ${formatReviewCounts(summarizeReviewOutcomes([session]))}`;
}

function ensureDomainNotActive(branch: string, domain: Domain, shard?: string): void {
  if (!hasSession(branch, domain, shard)) {
    return;
  }

  const session = loadSession(branch, domain, shard);
  if (session.currentIndex < session.rules.length) {
    die(
      `Session already active for ${sessionKey(domain, shard)} on ${branch}. Complete it or reset it first.`,
    );
  }
}

function advanceSession(branch: string, session: ReviewSession): void {
  session.currentIndex += 1;
  session.updatedAt = new Date().toISOString();
  saveSession(branch, session);
  printRule(session);
}

/** Changed-file paths this session may cite as evidence: its scope plus the full plan. */
function sessionScope(branch: string, session: ReviewSession): string[] | null {
  const paths = new Set<string>(session.scopedFiles ?? []);
  if (existsSync(planPath(branch))) {
    const plan = loadPlan(branch);
    for (const file of plan.changedFiles) {
      paths.add(file.path);
    }
  }

  return paths.size > 0 ? [...paths] : null;
}

function assertCriticalPassEvidence(
  branch: string,
  session: ReviewSession,
  rule: Rule,
  evidence: string,
): void {
  if (rule.severity !== 'critical') {
    return;
  }

  if (evidence.trim().length < 30) {
    die(
      `BLOCKED: critical rule "${rule.slug}" needs concrete pass evidence (>= 30 characters).\n` +
        'State which scoped diffs or files you read and the specific condition you verified.',
    );
  }

  const scope = sessionScope(branch, session);
  if (!scope) {
    return;
  }

  const citesFile = scope.some(
    (path) => evidence.includes(path) || evidence.includes(basename(path)),
  );
  if (!citesFile && !evidence.includes('file-list')) {
    die(
      `BLOCKED: critical rule "${rule.slug}" pass evidence must cite what you actually read.\n\n` +
        'Include at least one changed-file path (or file name) from your scope that you inspected for this rule.\n' +
        'If you concluded the rule cannot apply from the changed-file paths alone, include the token "file-list" plus that reasoning.\n' +
        'Generic evidence such as "checked the diff" is not accepted.',
    );
  }
}

function start(branch: string, domain: Domain, shard?: string): void {
  ensureDomainNotActive(branch, domain, shard);
  const rules = loadDomainRules(domain);

  let scopedFiles: string[] | undefined;
  if (existsSync(planPath(branch))) {
    const plan = loadPlan(branch);
    const entry = plan.subagents.find(
      (subagent) => subagent.domain === domain && (subagent.shard ?? null) === (shard ?? null),
    );
    if (shard && !entry) {
      die(
        `No planned shard "${shard}" for domain "${domain}" on branch "${branch}". ` +
          'Use the exact --shard from the stored plan task, or omit --shard.',
      );
    }
    scopedFiles = entry?.scopedFiles;
  } else if (shard) {
    die('--shard requires a stored plan. Run plan/plan-pr first.');
  }

  const session: ReviewSession = {
    branch,
    domain,
    shard,
    scopedFiles,
    rules,
    currentIndex: 0,
    findings: 0,
    currentRuleFindings: 0,
    findingRules: 0,
    passes: 0,
    skipped: 0,
    criticalPasses: 0,
    criticalSkipped: 0,
    criticalFindings: 0,
    warningPasses: 0,
    warningSkipped: 0,
    warningFindings: 0,
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  ensureSessionDirectories(branch);
  saveSession(branch, session);
  saveFindings(branch, domain, [], shard);

  const summary = severitySummary(session);
  console.log(
    `Session started for ${sessionKey(domain, shard)} on ${branch}. critical ${summary.criticalTotal}, warning ${summary.warningTotal}.`,
  );
  if (scopedFiles && scopedFiles.length > 0) {
    console.log(`Scoped to ${scopedFiles.length} changed file(s).`);
  }
  printRule(session);
}

function next(branch: string, domain: Domain, shard?: string): void {
  printRule(loadSession(branch, domain, shard));
}

function pass(branch: string, domain: Domain, evidence: string, shard?: string): void {
  if (evidence.trim().length < 10) {
    die('--evidence must be at least 10 characters');
  }

  const session = loadSession(branch, domain, shard);
  if (session.currentIndex >= session.rules.length) {
    die(`All rules already completed for ${sessionKey(domain, shard)}.`);
  }

  const rule = session.rules[session.currentIndex];
  if (session.currentRuleFindings > 0) {
    die(
      `BLOCKED: rule "${rule.slug}" already has ${session.currentRuleFindings} recorded finding(s).\n` +
        'A rule with findings is closed with rule-done, not pass.',
    );
  }

  assertCriticalPassEvidence(branch, session, rule, evidence);

  console.log(`PASS: ${rule.slug} -- ${evidence.trim()}`);
  session.passes += 1;
  if (rule.severity === 'critical') session.criticalPasses += 1;
  else session.warningPasses += 1;
  advanceSession(branch, session);
}

function parseSkipReason(value: string): SkipReason {
  if ((SKIP_REASONS as readonly string[]).includes(value)) {
    return value as SkipReason;
  }

  die(`Unknown --reason "${value}". Valid reasons: ${SKIP_REASONS.join(', ')}`);
}

function skip(
  branch: string,
  domain: Domain,
  reason: string,
  note?: string | null,
  shard?: string,
): void {
  const parsedReason = parseSkipReason(reason);
  const trimmedNote = note?.trim();
  if (note != null && !trimmedNote) {
    die('--note must not be empty when provided');
  }

  const session = loadSession(branch, domain, shard);
  if (session.currentIndex >= session.rules.length) {
    die(`All rules already completed for ${sessionKey(domain, shard)}.`);
  }

  const rule = session.rules[session.currentIndex];
  if (session.currentRuleFindings > 0) {
    die(
      `BLOCKED: rule "${rule.slug}" already has ${session.currentRuleFindings} recorded finding(s).\n` +
        'A rule with findings is closed with rule-done, not skip.',
    );
  }

  if (rule.severity === 'critical') {
    die(
      `BLOCKED: critical rule "${rule.slug}" cannot be skipped.\n\n` +
        `Rule: ${rule.description}\n\n` +
        `You MUST make an explicit judgment on the actual diff for this rule.\n` +
        `Re-read the changed hunks now, then choose one of:\n` +
        `  • No issue found → pass --evidence "<quote the specific code or absence you verified that proves this rule does not apply>"\n` +
        `  • Issue found    → finding --file <path> --line <n> --side RIGHT --body-file <tmp>\n\n` +
        `Do NOT call skip again on a critical rule.`,
    );
  }

  // Only warning rules reach this point — critical rules are blocked above.
  console.log(`SKIP: ${rule.slug} -- ${parsedReason}${trimmedNote ? ` | ${trimmedNote}` : ''}`);
  session.skipped += 1;
  session.warningSkipped += 1;
  advanceSession(branch, session);
}

function parseSeverityOverride(args: string[]): Severity | undefined {
  const value = getArg(args, '--severity');
  if (!value) {
    return undefined;
  }
  if (value !== 'critical' && value !== 'warning') {
    die('--severity must be critical or warning');
  }

  return value;
}

function finding(branch: string, domain: Domain, args: string[]): void {
  const file = requireArg(args, '--file');
  const line = Number(requireArg(args, '--line'));
  const side = requireArg(args, '--side').toUpperCase();
  const shard = getArg(args, '--shard') ?? undefined;
  const severityOverride = parseSeverityOverride(args);
  const body = readFindingBody(args);

  if (!Number.isInteger(line)) {
    die('--line must be an integer');
  }
  if (side !== 'RIGHT' && side !== 'LEFT') {
    die('--side must be RIGHT or LEFT');
  }
  if (body.trim().length < 10) {
    die('--body must be at least 10 characters');
  }

  const session = loadSession(branch, domain, shard);
  if (session.currentIndex >= session.rules.length) {
    die(`All rules already completed for ${sessionKey(domain, shard)}.`);
  }

  // Enforce diff-anchor: findings must target a file that was actually changed in this PR.
  // If the plan exists and lists changed files, reject findings outside that set.
  // This forces agents to anchor every finding to a changed line; references to
  // pre-existing code belong in the finding body, not as the finding target.
  if (existsSync(planPath(branch))) {
    const plan = loadPlan(branch);
    const changedPaths = plan.changedFiles.map((f) => f.path);
    if (changedPaths.length > 0 && !changedPaths.includes(file)) {
      die(
        `BLOCKED: "${file}" is not in the PR diff.\n\n` +
          `Every finding must be anchored to a line that was changed in this PR.\n` +
          `If the issue is in existing code that this PR introduces a dependency on or exposes:\n` +
          `  1. Find the changed line in the diff that introduces or calls that code\n` +
          `  2. Record the finding there: --file <changed-file> --line <that-line>\n` +
          `  3. Quote or reference the problematic pre-existing code in the finding body\n\n` +
          `Changed files in this PR:\n${changedPaths.map((p) => `  ${p}`).join('\n')}`,
      );
    }

    // Hunk-level check: the line must fall within a diff hunk for this file.
    // Skip only when hunks is undefined (file-list mode / legacy plan — no diff was parsed).
    // An empty array [] means the file was in the diff but has no changed hunks (e.g. a pure
    // rename or mode-change). In that case GitHub will also reject an inline comment, so we
    // reject the finding here rather than letting engine/submit-review.mjs silently drop it later.
    const fileEntry = plan.changedFiles.find((f) => f.path === file);
    if (fileEntry?.hunks !== undefined) {
      if (fileEntry.hunks.length === 0) {
        die(
          `BLOCKED: "${file}" has no changed hunks in the PR diff (it may be a pure rename or mode-change).\n\n` +
            `GitHub does not allow inline comments on files with no changed lines.\n` +
            `Record the finding on a file that has actual line changes, or skip this rule with an appropriate reason.`,
        );
      }

      const range =
        side === 'LEFT' ? (['oldStart', 'oldEnd'] as const) : (['newStart', 'newEnd'] as const);
      const inHunk = fileEntry.hunks.some(
        (hunk) => line >= hunk[range[0]] && line <= hunk[range[1]],
      );
      if (!inHunk) {
        const hunkRanges = fileEntry.hunks.map((h) => `${h[range[0]]}–${h[range[1]]}`).join(', ');
        die(
          `line ${line} of "${file}" is not in the PR diff.\n` +
            `Changed hunks (${side} side): lines ${hunkRanges}\n` +
            `Read the diff for this file and re-record at a line within those ranges, or drop this finding and move on.`,
        );
      }
    }
  }

  const rule = session.rules[session.currentIndex];
  const severity = severityOverride ?? rule.severity;
  const reviewFinding: ReviewFinding = {
    path: file,
    line,
    side: side as ReviewFinding['side'],
    severity,
    rule: rule.slug,
    domain,
    body,
  };

  appendFinding(branch, domain, reviewFinding, shard);
  session.findings += 1;
  session.currentRuleFindings += 1;
  if (severity === 'critical') session.criticalFindings += 1;
  else session.warningFindings += 1;
  session.updatedAt = new Date().toISOString();
  saveSession(branch, session);
  console.log(
    `FINDING recorded: ${rule.slug} @ ${file}:${line} (${severity}) — ${session.currentRuleFindings} finding(s) on this rule.`,
  );
  console.log(
    'The rule stays open: keep scanning the remaining scoped files for more instances. Close it with rule-done when fully swept.',
  );
}

function ruleDone(branch: string, domain: Domain, shard?: string): void {
  const session = loadSession(branch, domain, shard);
  if (session.currentIndex >= session.rules.length) {
    die(`All rules already completed for ${sessionKey(domain, shard)}.`);
  }

  if (session.currentRuleFindings === 0) {
    die(
      'rule-done closes a rule that has recorded findings. This rule has none.\n' +
        'Use pass (rule applies, no issue found) or skip (warning rule, structurally impossible) instead.',
    );
  }

  const rule = session.rules[session.currentIndex];
  console.log(`RULE DONE: ${rule.slug} — ${session.currentRuleFindings} finding(s) recorded.`);
  session.findingRules += 1;
  session.currentRuleFindings = 0;
  advanceSession(branch, session);
}

function status(branch: string, maybeDomain: string | null, shard?: string): void {
  if (maybeDomain && shard) {
    const session = loadSession(branch, parseDomain(maybeDomain), shard);
    console.log(formatStatusLine(session));
    return;
  }

  if (maybeDomain) {
    const domain = parseDomain(maybeDomain);
    const sessions = loadBranchSessions(branch).filter((session) => session.domain === domain);
    if (sessions.length === 0) {
      // Preserve the precise single-session error for unknown domains.
      loadSession(branch, domain);
      return;
    }

    for (const session of sessions) {
      console.log(formatStatusLine(session));
    }
    return;
  }

  const sessions = loadBranchSessions(branch);
  if (sessions.length === 0) {
    console.log(`No sessions found for branch "${branch}".`);
    return;
  }

  for (const session of sessions) {
    console.log(formatStatusLine(session));
  }
}

function rule(args: string[]): void {
  const slug = requireArg(args, '--slug');
  const domainArg = getArg(args, '--domain');
  const domain = domainArg ? parseDomain(domainArg) : undefined;
  const matches = lookupRulesBySlug(slug, domain);

  if (matches.length === 0) {
    die(`No rule found for slug "${slug}"${domain ? ` in domain "${domain}"` : ''}.`);
  }

  if (matches.length > 1) {
    die(
      `Multiple rules found for slug "${slug}" across domains: ${matches
        .map((match) => match.domain)
        .join(', ')}. Re-run with --domain.`,
    );
  }

  const match = matches[0];
  if (args.includes('--json')) {
    console.log(JSON.stringify(match, null, 2));
    return;
  }

  console.log(`domain: ${match.domain}`);
  console.log(`slug: ${match.slug}`);
  console.log(`severity: ${match.severity}`);
  console.log(`description: ${match.description}`);
}

function summary(branch: string): void {
  const sessions = loadBranchSessions(branch);
  if (sessions.length === 0) {
    console.log(`No sessions found for branch "${branch}".`);
    return;
  }

  let criticalDone = 0;
  let criticalTotal = 0;
  let warningDone = 0;
  let warningTotal = 0;
  const reviewSummary = summarizeReviewOutcomes(sessions);

  for (const session of sessions) {
    const progress = severitySummary(session);
    criticalDone += progress.criticalDone;
    criticalTotal += progress.criticalTotal;
    warningDone += progress.warningDone;
    warningTotal += progress.warningTotal;
  }

  console.log(
    `domains=${sessions.length} critical ${criticalDone}/${criticalTotal} warning ${warningDone}/${warningTotal} ${formatReviewCounts(reviewSummary)}`,
  );
}

function parseCarriedCriticals(args: string[]): number {
  const raw = getArg(args, '--carried-criticals');
  if (raw === null) {
    return 0;
  }

  const value = Number(raw);
  if (!Number.isInteger(value) || value < 0) {
    die('--carried-criticals must be a non-negative integer');
  }
  return value;
}

function compile(branch: string, carriedCriticals = 0): void {
  const sessions = loadBranchSessions(branch);
  if (sessions.length === 0) {
    die(`No sessions found for branch "${branch}".`);
  }

  const incomplete = sessions.filter((session) => session.currentIndex < session.rules.length);
  if (incomplete.length > 0) {
    die(
      `Cannot compile. Incomplete sessions: ${incomplete
        .map(
          (session) =>
            `${sessionKey(session.domain, session.shard)} (${session.currentIndex}/${session.rules.length})`,
        )
        .join(', ')}`,
    );
  }

  const comments = compileFindings(
    sessions.flatMap((session) => loadFindings(branch, session.domain, session.shard)),
  );
  const reviewSummary = summarizeReviewOutcomes(sessions);
  const generatedAt = new Date().toISOString();

  const criticalCount = comments.filter((comment) => comment.severity === 'critical').length;
  const warningCount = comments.length - criticalCount;
  const domainRows = sessions.map((session) => {
    const sv = severitySummary(session);
    return {
      domain: sessionKey(session.domain, session.shard),
      phase: sv.phase,
      criticalTotal: sv.criticalTotal,
      criticalPassed: session.criticalPasses,
      criticalSkipped: session.criticalSkipped,
      criticalFindings: session.criticalFindings,
      warningTotal: sv.warningTotal,
      warningPassed: session.warningPasses,
      warningSkipped: session.warningSkipped,
      warningFindings: session.warningFindings,
    };
  });
  let metadata: ReviewMetadataMarker | undefined;
  if (existsSync(planPath(branch))) {
    const plan = loadPlan(branch);
    if (plan.reviewScope?.headSha) {
      metadata = {
        schema: 'agentkit-code-review',
        version: 1,
        headSha: plan.reviewScope.headSha,
        baseSha: plan.reviewScope.baseSha ?? null,
        scope: plan.reviewScope.scope,
        changedFilesHash: createChangedFilesHash(plan.changedFiles),
        domains: [...new Set(sessions.map((session) => session.domain))],
        generatedAt,
        sourceReviewId: plan.reviewScope.sourceReviewId,
        sourceReviewSubmittedAt: plan.reviewScope.sourceReviewSubmittedAt,
      };
    }
  }

  const githubReviewBody = buildGithubReviewBody(
    reviewSummary,
    domainRows,
    comments,
    metadata,
    carriedCriticals,
  );
  const githubReviewEvent = selectGithubReviewEvent(comments, carriedCriticals);
  const commentsWithSummary = comments.map((comment, index) =>
    index === 0 ? { ...comment, reviewSummary } : comment,
  );
  const report = {
    branch,
    generatedAt,
    summary: {
      totalReviewedRules: reviewSummary.totalReviewedRules,
      passedCount: reviewSummary.passedCount,
      skippedCount: reviewSummary.skippedCount,
      findingCount: reviewSummary.findingCount,
      totalFindings: comments.length,
      criticalCount,
      warningCount,
      carriedCriticals,
      domainCount: sessions.length,
    },
    githubReview: {
      body: githubReviewBody,
      event: githubReviewEvent,
      summary: reviewSummary,
    },
    domains: sessions.map((session) => ({
      domain: session.domain,
      shard: session.shard,
      findings: session.findings,
      passes: session.passes,
      skipped: session.skipped,
      ...severitySummary(session),
    })),
    comments: commentsWithSummary,
  };

  writeFileSync(reportPath(branch), JSON.stringify(report, null, 2));
  writeFileSync(commentsPath(branch), JSON.stringify(commentsWithSummary, null, 2));
  console.log(formatReviewedRulesSentence(reviewSummary));
  console.log(
    `Compiled ${comments.length} finding(s): ${criticalCount} critical, ${warningCount} warning.`,
  );
  if (carriedCriticals > 0) {
    console.log(
      `Carried ${carriedCriticals} unaddressed prior critical(s) from the verifier. Event: ${githubReviewEvent}.`,
    );
  }
  console.log(`Comments: ${commentsPath(branch)}`);
  console.log(`Report: ${reportPath(branch)}`);
}

function doctor(branch: string): void {
  const sessions = loadBranchSessions(branch);
  if (sessions.length === 0) {
    die(`No sessions found for branch "${branch}".`);
  }

  for (const session of sessions) {
    const label = sessionKey(session.domain, session.shard);
    if (session.currentIndex > session.rules.length) {
      die(`${label}: currentIndex exceeds rule count`);
    }
    if (session.currentIndex !== session.findingRules + session.passes + session.skipped) {
      die(`${label}: currentIndex does not match finding-closed rules + passes + skipped`);
    }
    if (session.currentIndex >= session.rules.length && session.currentRuleFindings > 0) {
      die(`${label}: session is complete but has findings on an unclosed rule`);
    }

    // The sweep rule is a critical that intentionally runs last — exclude it
    // from the criticals-before-warnings ordering invariant.
    const warningBeforeCritical = session.rules
      .slice(0, session.currentIndex)
      .some(
        (rule, index, completed) =>
          rule.severity === 'warning' &&
          completed
            .slice(index + 1)
            .some((laterRule) => laterRule.severity === 'critical' && !laterRule.sweep),
      );
    if (warningBeforeCritical) {
      die(`${label}: warning rule completed before remaining critical rule`);
    }

    if (session.criticalSkipped > 0) {
      die(
        `${label}: ${session.criticalSkipped} critical rule(s) were skipped — this is forbidden. Critical rules must be passed or flagged as findings.`,
      );
    }

    const findings = loadFindings(branch, session.domain, session.shard);
    if (findings.length !== session.findings) {
      die(`${label}: findings file count does not match session counter`);
    }
  }

  console.log(`Doctor OK for ${branch}.`);
}

function notes(branch: string, domain: Domain, note: string, shard?: string): void {
  if (note.trim().length === 0) {
    die('--append must not be empty');
  }
  appendNote(branch, domain, note, shard);
  console.log(`Note appended for ${sessionKey(domain, shard)}.`);
}

function showNotes(branch: string, domain: Domain, shard?: string): void {
  const notesContent = readNotes(branch, domain, shard);
  if (notesContent.length === 0) {
    console.log(`No notes for ${sessionKey(domain, shard)} on ${branch}.`);
    return;
  }

  process.stdout.write(notesContent);
}

function usage(): void {
  console.log(
    'Usage: review-cli <classify|plan|plan-pr|prompt|rule|start|next|pass|skip|finding|rule-done|status|summary|compile|doctor|notes|show-notes|reset|round-complete> ...',
  );
}

/**
 * Worktree mode only: records the current git HEAD as the completion SHA for
 * this review round, after its one fix commit has landed. The next
 * `plan --branch <label> --base ...`-less call for this branch defaults its
 * base to this SHA.
 */
function roundComplete(branch: string): void {
  const marker = markRoundComplete(branch);
  console.log(`Round ${marker.round} marked complete for "${branch}" at ${marker.sha}.`);
  console.log('The next `plan` call without --base will default to this SHA.');
}

function reset(branch: string, maybeDomain: string | null, shard?: string): void {
  resetSession(branch, maybeDomain ? parseDomain(maybeDomain) : undefined, shard);
  if (maybeDomain) {
    console.log(`Reset session for ${sessionKey(parseDomain(maybeDomain), shard)} on ${branch}.`);
    return;
  }

  console.log(`Reset all sessions for ${branch}.`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];
  if (!command) {
    usage();
    process.exit(0);
  }

  if (command === 'classify') {
    const result = await classifyFromArgs(args.slice(1));
    if (args.includes('--json')) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    console.log(renderClassification(result));
    return;
  }

  if (command === 'plan') {
    if (args.includes('--json')) {
      const result = await createPlanFromArgs(args.slice(1));
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    if (args.includes('--tasks')) {
      console.log(await renderPlanTasksFromArgs(args.slice(1)));
      return;
    }

    const result = await createPlanFromArgs(args.slice(1));
    console.log(renderPlan(result));
    return;
  }

  if (command === 'plan-pr') {
    const result = await createPullRequestPlanFromArgs(args.slice(1));
    console.log(renderPlan(result));
    return;
  }

  if (command === 'rule') {
    rule(args.slice(1));
    return;
  }

  const branch = requireArg(args, '--branch');
  const shard = getArg(args, '--shard') ?? undefined;

  if (command === 'prompt') {
    console.log(renderStoredPrompt(branch, parseDomain(requireArg(args, '--domain')), shard));
    return;
  }

  switch (command) {
    case 'start':
      start(branch, parseDomain(requireArg(args, '--domain')), shard);
      break;
    case 'next':
      next(branch, parseDomain(requireArg(args, '--domain')), shard);
      break;
    case 'pass':
      pass(
        branch,
        parseDomain(requireArg(args, '--domain')),
        requireArg(args, '--evidence'),
        shard,
      );
      break;
    case 'skip':
      skip(
        branch,
        parseDomain(requireArg(args, '--domain')),
        requireArg(args, '--reason'),
        getArg(args, '--note'),
        shard,
      );
      break;
    case 'finding':
      finding(branch, parseDomain(requireArg(args, '--domain')), args);
      break;
    case 'rule-done':
      ruleDone(branch, parseDomain(requireArg(args, '--domain')), shard);
      break;
    case 'status':
      status(branch, getArg(args, '--domain'), shard);
      break;
    case 'summary':
      summary(branch);
      break;
    case 'compile':
      compile(branch, parseCarriedCriticals(args));
      break;
    case 'doctor':
      doctor(branch);
      break;
    case 'notes':
      notes(
        branch,
        parseDomain(requireArg(args, '--domain')),
        requireArg(args, '--append'),
        shard,
      );
      break;
    case 'show-notes':
      showNotes(branch, parseDomain(requireArg(args, '--domain')), shard);
      break;
    case 'reset':
      reset(branch, getArg(args, '--domain'), shard);
      break;
    case 'round-complete':
      roundComplete(branch);
      break;
    default:
      usage();
      die(`Unknown command "${command}"`);
  }
}

const isMain =
  process.argv[1] &&
  fileURLToPath(import.meta.url) ===
    (process.argv[1].startsWith('/')
      ? process.argv[1]
      : new URL(process.argv[1], import.meta.url).pathname);

if (isMain) {
  void main().catch((error: unknown) => {
    die(error instanceof Error ? error.message : String(error));
  });
}
