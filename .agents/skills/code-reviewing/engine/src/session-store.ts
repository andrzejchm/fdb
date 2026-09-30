import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { DOMAIN_ORDER } from './rules.ts';
import type {
  ChangedFile,
  DiffReviewTarget,
  Domain,
  ReviewFinding,
  ReviewSession,
  Severity,
  StoredReviewPlan,
  WorktreeRoundMarker,
} from './types.ts';

type StoredReviewSession = Omit<
  ReviewSession,
  | 'skipped'
  | 'currentRuleFindings'
  | 'findingRules'
  | 'criticalPasses'
  | 'criticalSkipped'
  | 'criticalFindings'
  | 'warningPasses'
  | 'warningSkipped'
  | 'warningFindings'
> &
  Partial<
    Pick<
      ReviewSession,
      | 'skipped'
      | 'currentRuleFindings'
      | 'findingRules'
      | 'criticalPasses'
      | 'criticalSkipped'
      | 'criticalFindings'
      | 'warningPasses'
      | 'warningSkipped'
      | 'warningFindings'
    >
  >;

const __dirname = dirname(fileURLToPath(import.meta.url));
// Bundled as a self-contained skill engine: session state lives in the consumer
// project root (cwd), and the launcher sits one level above dist/.
const REPO_ROOT = process.cwd();
const CLI_PATH = join(__dirname, '..', 'review-cli');

export function repoRoot(): string {
  return REPO_ROOT;
}

export function cliPath(): string {
  return CLI_PATH;
}

export function sanitizeBranch(branch: string): string {
  if (branch.length === 0) {
    throw new Error('branch must be a non-empty string');
  }

  return branch.replace(/[/\\]/g, '-');
}

function sessionsDir(branch: string): string {
  return join(REPO_ROOT, '.review-sessions', sanitizeBranch(branch));
}

export function findingsDir(branch: string): string {
  return join(sessionsDir(branch), 'findings');
}

function notesDir(branch: string): string {
  return join(sessionsDir(branch), 'notes');
}

export function diffDir(branch: string): string {
  return join(sessionsDir(branch), 'diffs');
}

export function diffFilePath(branch: string, filePath: string): string {
  return join(diffDir(branch), filePath + '.diff');
}

export function sanitizeShard(shard: string): string {
  if (!/^[A-Za-z0-9-]+$/.test(shard)) {
    throw new Error(`Invalid shard id "${shard}". Use alphanumeric shard ids like "s1".`);
  }

  return shard;
}

/** File-name stem for a session: `<domain>` or `<domain>@<shard>`. */
export function sessionKey(domain: Domain, shard?: string): string {
  return shard ? `${domain}@${sanitizeShard(shard)}` : domain;
}

export function sessionPath(branch: string, domain: Domain, shard?: string): string {
  return join(sessionsDir(branch), `${sessionKey(domain, shard)}.json`);
}

export function findingsPath(branch: string, domain: Domain, shard?: string): string {
  return join(findingsDir(branch), `${sessionKey(domain, shard)}.json`);
}

export function notesPath(branch: string, domain: Domain, shard?: string): string {
  return join(notesDir(branch), `${sessionKey(domain, shard)}.md`);
}

export function reportPath(branch: string): string {
  return join(sessionsDir(branch), 'review-report.json');
}

export function commentsPath(branch: string): string {
  return join(sessionsDir(branch), 'review-comments.json');
}

export function planPath(branch: string): string {
  return join(sessionsDir(branch), 'plan.json');
}

export function roundMarkerPath(branch: string): string {
  return join(sessionsDir(branch), 'round-marker.json');
}

export function reviewTargetInputPath(
  branch: string,
  inputKind: DiffReviewTarget['inputKind'],
): string {
  return join(
    sessionsDir(branch),
    inputKind === 'diff' ? 'review-target.diff' : 'review-target-files.txt',
  );
}

export function ensureSessionDirectories(branch: string): void {
  mkdirSync(sessionsDir(branch), { recursive: true });
  mkdirSync(findingsDir(branch), { recursive: true });
  mkdirSync(notesDir(branch), { recursive: true });
  mkdirSync(diffDir(branch), { recursive: true });
}

export function loadSession(branch: string, domain: Domain, shard?: string): ReviewSession {
  const path = sessionPath(branch, domain, shard);
  if (!existsSync(path)) {
    throw new Error(
      `No session found for domain "${sessionKey(domain, shard)}" on branch "${branch}".`,
    );
  }

  return normalizeSession(JSON.parse(readFileSync(path, 'utf8')) as StoredReviewSession);
}

export function hasSession(branch: string, domain: Domain, shard?: string): boolean {
  return existsSync(sessionPath(branch, domain, shard));
}

export function saveSession(branch: string, session: ReviewSession): void {
  ensureSessionDirectories(branch);
  writeFileSync(
    sessionPath(branch, session.domain, session.shard),
    JSON.stringify(session, null, 2),
  );
}

function normalizeSession(session: StoredReviewSession): ReviewSession {
  return {
    ...session,
    skipped: session.skipped ?? 0,
    // Legacy sessions advanced on every finding, so finding-closed rules == finding instances.
    findingRules: session.findingRules ?? session.findings,
    currentRuleFindings: session.currentRuleFindings ?? 0,
    criticalPasses: session.criticalPasses ?? 0,
    criticalSkipped: session.criticalSkipped ?? 0,
    criticalFindings: session.criticalFindings ?? 0,
    warningPasses: session.warningPasses ?? 0,
    warningSkipped: session.warningSkipped ?? 0,
    warningFindings: session.warningFindings ?? 0,
  };
}

export function savePlan(branch: string, plan: StoredReviewPlan): void {
  ensureSessionDirectories(branch);
  writeFileSync(planPath(branch), JSON.stringify(plan, null, 2));
}

/**
 * Loads the worktree-mode round marker for a branch, or null if no round has
 * been marked complete yet (e.g. round 1, which requires an explicit --base).
 */
export function loadRoundMarker(branch: string): WorktreeRoundMarker | null {
  const path = roundMarkerPath(branch);
  if (!existsSync(path)) {
    return null;
  }

  return JSON.parse(readFileSync(path, 'utf8')) as WorktreeRoundMarker;
}

export function saveRoundMarker(branch: string, marker: WorktreeRoundMarker): void {
  ensureSessionDirectories(branch);
  writeFileSync(roundMarkerPath(branch), JSON.stringify(marker, null, 2));
}

export function saveReviewTargetInput(
  branch: string,
  inputKind: DiffReviewTarget['inputKind'],
  content: string,
): string {
  ensureSessionDirectories(branch);
  const path = reviewTargetInputPath(branch, inputKind);
  writeFileSync(path, content);
  return path;
}

/**
 * Normalizes the stored plan's changedFiles field to the current ChangedFile[] shape.
 * Old plans stored changedFiles as string[] — migrate them to { path, changeType: 'modified' }.
 */
function normalizePlan(raw: unknown): StoredReviewPlan {
  const plan = raw as Record<string, unknown>;
  if (Array.isArray(plan['changedFiles']) && plan['changedFiles'].length > 0) {
    const first = plan['changedFiles'][0];
    if (typeof first === 'string') {
      // Old format: string[] — migrate to ChangedFile[]
      plan['changedFiles'] = (plan['changedFiles'] as string[]).map(
        (p): ChangedFile => ({ path: p, changeType: 'modified' }),
      );
    }
  }
  return plan as unknown as StoredReviewPlan;
}

export function loadPlan(branch: string): StoredReviewPlan {
  const path = planPath(branch);
  if (!existsSync(path)) {
    throw new Error(
      `No stored plan found for branch "${branch}". Run \`${relative(REPO_ROOT, CLI_PATH)} plan --branch "${branch}" ...\` first.`,
    );
  }

  return normalizePlan(JSON.parse(readFileSync(path, 'utf8')));
}

export function loadFindings(branch: string, domain: Domain, shard?: string): ReviewFinding[] {
  const path = findingsPath(branch, domain, shard);
  if (!existsSync(path)) {
    return [];
  }

  return JSON.parse(readFileSync(path, 'utf8')) as ReviewFinding[];
}

export function saveFindings(
  branch: string,
  domain: Domain,
  findings: ReviewFinding[],
  shard?: string,
): void {
  ensureSessionDirectories(branch);
  writeFileSync(findingsPath(branch, domain, shard), JSON.stringify(findings, null, 2));
}

export function appendFinding(
  branch: string,
  domain: Domain,
  finding: ReviewFinding,
  shard?: string,
): void {
  const findings = loadFindings(branch, domain, shard);
  findings.push(finding);
  saveFindings(branch, domain, findings, shard);
}

export function appendNote(branch: string, domain: Domain, note: string, shard?: string): void {
  ensureSessionDirectories(branch);
  const path = notesPath(branch, domain, shard);
  const existing = existsSync(path) ? readFileSync(path, 'utf8') : '';
  const entry = `- ${note.trim()}\n`;
  writeFileSync(path, `${existing}${entry}`);
}

export function readNotes(branch: string, domain: Domain, shard?: string): string {
  const path = notesPath(branch, domain, shard);
  if (!existsSync(path)) {
    return '';
  }

  return readFileSync(path, 'utf8');
}

export function loadBranchSessions(branch: string): ReviewSession[] {
  const dir = sessionsDir(branch);
  if (!existsSync(dir)) {
    return [];
  }

  const reservedFiles = new Set([
    basename(planPath(branch)),
    basename(reportPath(branch)),
    basename(commentsPath(branch)),
    basename(roundMarkerPath(branch)),
  ]);
  const sessions: ReviewSession[] = [];
  for (const entry of readdirSync(dir)) {
    if (!entry.endsWith('.json') || reservedFiles.has(entry)) {
      continue;
    }

    sessions.push(
      normalizeSession(JSON.parse(readFileSync(join(dir, entry), 'utf8')) as StoredReviewSession),
    );
  }

  const domainRank = (domain: Domain): number => {
    const rank = DOMAIN_ORDER.indexOf(domain);
    return rank === -1 ? DOMAIN_ORDER.length : rank;
  };
  return sessions.sort(
    (left, right) =>
      domainRank(left.domain) - domainRank(right.domain) ||
      (left.shard ?? '').localeCompare(right.shard ?? ''),
  );
}

export function branchHasSessions(branch: string): boolean {
  const dir = sessionsDir(branch);
  if (!existsSync(dir)) {
    return false;
  }

  const reportFileName = basename(reportPath(branch));
  const commentsFileName = basename(commentsPath(branch));
  const planFileName = basename(planPath(branch));
  const roundMarkerFileName = basename(roundMarkerPath(branch));
  return readdirSync(dir).some(
    (entry: string) =>
      entry.endsWith('.json') &&
      entry !== reportFileName &&
      entry !== commentsFileName &&
      entry !== planFileName &&
      entry !== roundMarkerFileName,
  );
}

function removeDomainFiles(dir: string, domain: Domain, extension: string): void {
  if (!existsSync(dir)) {
    return;
  }

  for (const entry of readdirSync(dir)) {
    if (entry === `${domain}${extension}` || entry.startsWith(`${domain}@`)) {
      rmSync(join(dir, entry), { force: true });
    }
  }
}

export function resetSession(branch: string, domain?: Domain, shard?: string): void {
  if (domain && shard) {
    rmSync(sessionPath(branch, domain, shard), { force: true });
    rmSync(findingsPath(branch, domain, shard), { force: true });
    rmSync(notesPath(branch, domain, shard), { force: true });
    return;
  }

  if (domain) {
    // Remove the unsharded session plus every shard of this domain.
    removeDomainFiles(sessionsDir(branch), domain, '.json');
    removeDomainFiles(findingsDir(branch), domain, '.json');
    removeDomainFiles(notesDir(branch), domain, '.md');
    return;
  }

  rmSync(sessionsDir(branch), { recursive: true, force: true });
}

export function severitySummary(session: ReviewSession): {
  criticalDone: number;
  criticalTotal: number;
  warningDone: number;
  warningTotal: number;
  phase: Severity | 'complete';
} {
  // Count by actual rule order — the sweep rule is a critical that runs last,
  // so contiguous-prefix math over criticalTotal does not hold.
  const criticalTotal = session.rules.filter((rule) => rule.severity === 'critical').length;
  const warningTotal = session.rules.length - criticalTotal;
  const completed = session.rules.slice(0, session.currentIndex);
  const criticalDone = completed.filter((rule) => rule.severity === 'critical').length;
  const warningDone = completed.length - criticalDone;

  const currentRule = session.rules[session.currentIndex];
  const phase: Severity | 'complete' = currentRule ? currentRule.severity : 'complete';

  return { criticalDone, criticalTotal, warningDone, warningTotal, phase };
}
