import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

import {
  classify,
  getBoundaryFromPath,
  isCodeFile,
  isIgnored,
  isReviewInfrastructureFile,
  isTestFile,
  loadReviewIgnore,
  parseDiffOrFileList,
  readReviewInputFromArgs,
  savePerFileDiffs,
  splitAndCleanDiff,
} from './classify.ts';
import { parseReviewMetadataMarker } from './marker.ts';
import { REVIEW_CONFIG, loadPromptTemplate } from './rules.ts';
import {
  cliPath,
  diffDir,
  loadPlan,
  loadRoundMarker,
  repoRoot,
  savePlan,
  saveReviewTargetInput,
  saveRoundMarker,
} from './session-store.ts';
import type {
  ChangedFile,
  DiffHunk,
  Domain,
  ReviewPlanResult,
  ReviewMetadataMarker,
  ReviewScope,
  ReviewTarget,
  StoredReviewPlan,
  WorktreeRoundMarker,
} from './types.ts';

type PullRequestReview = {
  id?: number;
  submitted_at?: string;
  body?: string | null;
};

type SelectedReviewMetadata = {
  reviewId?: number;
  submittedAt?: string;
  metadata: ReviewMetadataMarker;
};

function getArg(args: string[], flag: string): string | null {
  const index = args.indexOf(flag);
  if (index === -1 || index + 1 >= args.length) {
    return null;
  }

  return args[index + 1];
}

function requireArg(args: string[], flag: string): string {
  const value = getArg(args, flag);
  if (!value) {
    throw new Error(`${flag} is required`);
  }

  return value;
}

function renderChangedFiles(files: ChangedFile[]): string {
  return files.map((file) => `- ${file.path} [${file.changeType}]`).join('\n');
}

function shardLabel(domain: Domain, shard?: string): string {
  return shard ? `${domain}@${shard}` : domain;
}

function renderSubagents(plan: ReviewPlanResult): string {
  return plan.subagents
    .map(
      (subagent) =>
        `- agent: ${subagent.agent} | domain: ${shardLabel(subagent.domain, subagent.shard)} | files: ${subagent.scopedFiles?.length ?? plan.changedFiles.length} | prompt_command: ${subagent.promptCommand}`,
    )
    .join('\n');
}

function renderTemplate(template: string, values: Record<string, string>): string {
  return Object.entries(values).reduce(
    (prompt, [key, value]) => prompt.replaceAll(`{{${key}}}`, value),
    template,
  );
}

function getOptionalNumberArg(args: string[], flag: string): number | undefined {
  const value = getArg(args, flag);
  if (!value) {
    return undefined;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed)) {
    throw new Error(`${flag} must be an integer`);
  }

  return parsed;
}

function parseReviewScope(args: string[]): ReviewScope | undefined {
  const scope = getArg(args, '--scope');
  if (!scope) {
    return undefined;
  }
  if (scope !== 'full' && scope !== 'incremental' && scope !== 'manual') {
    throw new Error('--scope must be full, incremental, or manual');
  }

  return {
    scope,
    headSha: getArg(args, '--head-sha') ?? undefined,
    baseSha: getArg(args, '--base-sha') ?? null,
    sourceReviewId: getOptionalNumberArg(args, '--source-review-id'),
    sourceReviewSubmittedAt: getArg(args, '--source-review-submitted-at') ?? undefined,
  };
}

function quotedCliPath(path: string): string {
  return `"${path}"`;
}

function planCommand(path: string, branch: string): string {
  return `${quotedCliPath(path)} plan --branch "${branch}" --tasks`;
}

function compileCommand(path: string, branch: string): string {
  return `${quotedCliPath(path)} compile --branch "${branch}"`;
}

function shardFlag(shard?: string): string {
  return shard ? ` --shard ${shard}` : '';
}

function promptCommand(path: string, branch: string, domain: Domain, shard?: string): string {
  return `${quotedCliPath(path)} prompt --branch "${branch}" --domain ${domain}${shardFlag(shard)}`;
}

function renderReviewTargetInstructions(reviewTarget?: ReviewTarget): string {
  if (!reviewTarget) {
    return loadPromptTemplate('review-target-none.md');
  }

  if (reviewTarget.mode === 'base') {
    return renderTemplate(loadPromptTemplate('review-target-base.md'), {
      diffsDir: reviewTarget.diffsDir ?? '',
    });
  }

  if (reviewTarget.inputKind === 'diff') {
    if (reviewTarget.storedInputPath) {
      return renderTemplate(loadPromptTemplate('review-target-diff-stored.md'), {
        diffsDir: reviewTarget.storedInputPath,
      });
    }
    if (reviewTarget.source === 'path' && reviewTarget.diffPath) {
      return renderTemplate(loadPromptTemplate('review-target-diff-path.md'), {
        diffPath: reviewTarget.diffPath,
      });
    }
    return loadPromptTemplate('review-target-diff-content.md');
  }

  if (reviewTarget.storedInputPath) {
    return renderTemplate(loadPromptTemplate('review-target-file-list-stored.md'), {
      storedInputPath: reviewTarget.storedInputPath,
    });
  }
  if (reviewTarget.source === 'path' && reviewTarget.diffPath) {
    return renderTemplate(loadPromptTemplate('review-target-file-list-path.md'), {
      diffPath: reviewTarget.diffPath,
    });
  }
  return loadPromptTemplate('review-target-file-list-content.md');
}

function renderReviewScopeInstructions(reviewScope?: ReviewScope): string {
  if (reviewScope?.scope === 'full') {
    return loadPromptTemplate('review-scope-full.md');
  }

  if (reviewScope?.scope === 'incremental') {
    return renderTemplate(loadPromptTemplate('review-scope-incremental.md'), {
      sourceReviewLabel: reviewScope.sourceReviewId
        ? `agentkit review ${reviewScope.sourceReviewId}`
        : 'the previous agentkit review',
      baseShaSuffix: reviewScope.baseSha ? ` at ${reviewScope.baseSha}` : '',
    });
  }

  if (reviewScope?.scope === 'manual') {
    return loadPromptTemplate('review-scope-manual.md');
  }

  return loadPromptTemplate('review-scope-unknown.md');
}

function createStoredPrompt(
  plan: StoredReviewPlan,
  domain: Domain,
  subagent?: StoredReviewPlan['subagents'][number],
): string {
  const scopedPaths = subagent?.scopedFiles;
  const scopedChangedFiles =
    scopedPaths && scopedPaths.length > 0
      ? plan.changedFiles.filter((file) => scopedPaths.includes(file.path))
      : plan.changedFiles;
  const shard = subagent?.shard;
  const shardLine = shard
    ? `\nSHARD: ${shard} — this session owns ${scopedChangedFiles.length} of ${plan.changedFiles.length} changed files. Review only the files listed below; parallel shards own the rest.`
    : '';

  return renderTemplate(loadPromptTemplate('reviewer.md'), {
    branch: plan.branch,
    domain,
    shardLine,
    shardFlag: shardFlag(shard),
    title: plan.title,
    description: plan.description,
    changedFiles: renderChangedFiles(scopedChangedFiles),
    cliPath: quotedCliPath(plan.cliPath),
    reviewTargetInstructions: renderReviewTargetInstructions(plan.reviewTarget),
    reviewScopeInstructions: renderReviewScopeInstructions(plan.reviewScope),
  });
}

function createSpawnPrompt(path: string, branch: string, domain: Domain, shard?: string): string {
  return renderTemplate(loadPromptTemplate('spawn.md'), {
    branch,
    domain,
    promptCommand: promptCommand(path, branch, domain, shard),
  });
}

function toStoredPlan(plan: ReviewPlanResult): StoredReviewPlan {
  return {
    ...plan,
    subagents: plan.subagents.map((subagent) => ({
      domain: subagent.domain,
      shard: subagent.shard,
      scopedFiles: subagent.scopedFiles,
      agent: subagent.agent,
      promptCommand: subagent.promptCommand,
      spawnPrompt: subagent.spawnPrompt,
    })),
  };
}

/**
 * The slice of changed files a domain is responsible for reading.
 * Derived from the classification config groups; an empty slice falls back to
 * all changed files so always-on domains never start blind.
 */
function relevantChangedFiles(domain: Domain, changedFiles: ChangedFile[]): ChangedFile[] {
  const groups = REVIEW_CONFIG.classification;
  let scoped: ChangedFile[];
  if (groups.specDomains?.includes(domain)) {
    scoped = changedFiles.filter(
      (file) =>
        groups.specRoots.some((specRoot) => file.path.startsWith(specRoot)) ||
        file.path.endsWith('.md'),
    );
  } else if (groups.testDomains.includes(domain)) {
    scoped = changedFiles.filter((file) => isTestFile(file.path));
  } else if (groups.uiDomains.includes(domain)) {
    scoped = changedFiles.filter((file) =>
      groups.uiRoots.some((uiRoot) => file.path.startsWith(uiRoot)),
    );
  } else if (groups.codeDomains.includes(domain)) {
    scoped = changedFiles.filter(
      (file) => isCodeFile(file.path) && !isReviewInfrastructureFile(file.path),
    );
  } else {
    scoped = changedFiles;
  }

  return scoped.length > 0 ? scoped : changedFiles;
}

/**
 * Split a domain's file slice into shards so each reviewer session stays small
 * enough to actually read everything it owns. Files are grouped by boundary
 * before chunking so related files land in the same shard.
 */
function shardChangedFiles(files: ChangedFile[]): Array<{ shard?: string; files: ChangedFile[] }> {
  const maxShardFiles = REVIEW_CONFIG.orchestration.maxShardFiles ?? 30;
  const maxShards = REVIEW_CONFIG.orchestration.maxShardsPerDomain ?? 4;
  if (files.length <= maxShardFiles) {
    return [{ files }];
  }

  const shardCount = Math.min(Math.ceil(files.length / maxShardFiles), maxShards);
  const sorted = [...files].sort((left, right) => {
    const leftBoundary = getBoundaryFromPath(left.path) ?? '~';
    const rightBoundary = getBoundaryFromPath(right.path) ?? '~';
    return leftBoundary.localeCompare(rightBoundary) || left.path.localeCompare(right.path);
  });
  const chunkSize = Math.ceil(sorted.length / shardCount);
  const shards: Array<{ shard?: string; files: ChangedFile[] }> = [];
  for (let index = 0; index < shardCount; index += 1) {
    const chunk = sorted.slice(index * chunkSize, (index + 1) * chunkSize);
    if (chunk.length > 0) {
      shards.push({ shard: `s${index + 1}`, files: chunk });
    }
  }

  return shards;
}

/**
 * Parse hunk ranges from a unified diff string.
 * Mirrors the parseHunks() logic in engine/submit-review.mjs.
 */
function parseHunks(diff: string): Map<string, DiffHunk[]> {
  const hunksByPath = new Map<string, DiffHunk[]>();
  let currentPath: string | null = null;
  let oldPath: string | null = null;

  for (const line of diff.split('\n')) {
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

    if (!currentPath) {
      continue;
    }

    const match = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line);
    if (!match) {
      continue;
    }

    hunksByPath.get(currentPath)!.push({
      oldStart: Number(match[1]),
      oldEnd: Number(match[1]) + Number(match[2] ?? '1') - 1,
      newStart: Number(match[3]),
      newEnd: Number(match[3]) + Number(match[4] ?? '1') - 1,
    });
  }

  return hunksByPath;
}

export function createChangedFilesHash(files: ChangedFile[]): string {
  const normalized = files
    .map((file) => ({
      path: file.path,
      changeType: file.changeType,
      hunks: file.hunks ?? [],
    }))
    .sort((left, right) => left.path.localeCompare(right.path));
  return createHash('sha256').update(JSON.stringify(normalized)).digest('hex');
}

export function selectLatestReviewMetadata(
  reviews: PullRequestReview[],
): SelectedReviewMetadata | null {
  const markedReviews = reviews
    .map((review): SelectedReviewMetadata | null => {
      const metadata = parseReviewMetadataMarker(review.body);
      if (!metadata) {
        return null;
      }
      return {
        reviewId: review.id,
        submittedAt: review.submitted_at,
        metadata,
      };
    })
    .filter((review): review is SelectedReviewMetadata => review !== null)
    .sort((left, right) => (left.submittedAt ?? '').localeCompare(right.submittedAt ?? ''));

  return markedReviews.at(-1) ?? null;
}

function runRequired(command: string, args: string[]): string {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `${command} ${args.join(' ')} failed`);
  }
  return result.stdout;
}

/**
 * Marks the current git HEAD as the "round complete" SHA for worktree-mode
 * (no-PR) review. Run this after committing a round's fixes (one commit per
 * round) so the next `plan --base`-less call resolves the correct base.
 * PR mode does not use this — it never calls markRoundComplete.
 */
export function markRoundComplete(branch: string): WorktreeRoundMarker {
  const sha = runRequired('git', ['rev-parse', 'HEAD']).trim();
  const previous = loadRoundMarker(branch);
  const marker: WorktreeRoundMarker = {
    round: (previous?.round ?? 0) + 1,
    sha,
    recordedAt: new Date().toISOString(),
  };
  saveRoundMarker(branch, marker);
  return marker;
}

function fetchPullRequestReviews(prNumber: string): PullRequestReview[] {
  const output = runRequired('gh', [
    'api',
    `repos/{owner}/{repo}/pulls/${prNumber}/reviews`,
    '--paginate',
    '--slurp',
  ]);
  const pages = JSON.parse(output) as PullRequestReview[][] | PullRequestReview[];
  if (Array.isArray(pages[0])) {
    return (pages as PullRequestReview[][]).flat();
  }
  return pages as PullRequestReview[];
}

function fetchPullRequestHeadSha(prNumber: string): string {
  return runRequired('gh', [
    'pr',
    'view',
    prNumber,
    '--json',
    'headRefOid',
    '--jq',
    '.headRefOid',
  ]).trim();
}

/**
 * Changes the PR introduced since its previous review, scoped to the PR's own
 * files. Scoping `prevHead..head` to `gh pr diff --name-only` keeps target-branch
 * commits the branch absorbed via merge-base from being attributed to the PR
 * (which would otherwise produce phantom findings on files the PR never touched).
 */
function diffSinceLastReview(prNumber: string, previousHeadSha: string, headSha: string): string {
  const prFiles = runRequired('gh', ['pr', 'diff', prNumber, '--name-only'])
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  if (prFiles.length === 0) {
    return '';
  }
  return runRequired('git', ['diff', `${previousHeadSha}..${headSha}`, '--', ...prFiles]);
}

function createPlanFromInput(
  branch: string,
  title: string,
  description: string,
  input: Awaited<ReturnType<typeof readReviewInputFromArgs>>,
  reviewScope?: ReviewScope,
): ReviewPlanResult {
  const storedRepoRoot = repoRoot();
  const storedCliPath = cliPath();
  const ignoredPatterns = loadReviewIgnore(storedRepoRoot);
  const classification = classify(input.files, input.proposalContent);

  let changedFiles: ChangedFile[];
  let reviewTarget: ReviewTarget;

  if (input.reviewTarget.mode === 'diff' && input.rawInput) {
    if (input.reviewTarget.inputKind === 'diff') {
      // Split the full diff into per-file artifacts; store the diffs directory path
      const diffMap = splitAndCleanDiff(input.rawInput, ignoredPatterns);
      savePerFileDiffs(branch, diffMap, ignoredPatterns);
      // Parse hunk ranges so finding() can enforce line-level anchoring
      const hunksByPath = parseHunks(input.rawInput);
      // Build changedFiles with detected change types and hunks from the diff map
      changedFiles = [...diffMap.entries()].map(([path, { changeType }]) => ({
        path,
        changeType,
        hunks: hunksByPath.get(path) ?? [],
      }));
      reviewTarget = {
        ...input.reviewTarget,
        storedInputPath: diffDir(branch),
      };
    } else {
      // file-list input: persist as before; change type is unknown → default to 'modified'
      // No diff available → hunks left undefined; hunk check is skipped gracefully
      changedFiles = [...new Set(input.files)]
        .filter((f) => !isIgnored(f, ignoredPatterns))
        .map((path) => ({ path, changeType: 'modified' as const }));
      reviewTarget = {
        ...input.reviewTarget,
        storedInputPath: saveReviewTargetInput(
          branch,
          input.reviewTarget.inputKind,
          input.rawInput,
        ),
      };
    }
  } else if (input.reviewTarget.mode === 'base') {
    // --base flow: split the git diff into per-file diffs (even if empty)
    if (input.rawInput) {
      const diffMap = splitAndCleanDiff(input.rawInput, ignoredPatterns);
      savePerFileDiffs(branch, diffMap, ignoredPatterns);
      // Parse hunk ranges so finding() can enforce line-level anchoring
      const hunksByPath = parseHunks(input.rawInput);
      changedFiles = [...diffMap.entries()].map(([path, { changeType }]) => ({
        path,
        changeType,
        hunks: hunksByPath.get(path) ?? [],
      }));
    } else {
      // No diff available → hunks left undefined; hunk check is skipped gracefully
      changedFiles = [...new Set(input.files)]
        .filter((f) => !isIgnored(f, ignoredPatterns))
        .map((path) => ({ path, changeType: 'modified' as const }));
    }
    reviewTarget = {
      ...input.reviewTarget,
      diffsDir: diffDir(branch),
    };
  } else {
    // fallback: no diff available, use file list with 'modified' default
    changedFiles = [...new Set(input.files)]
      .filter((f) => !isIgnored(f, ignoredPatterns))
      .map((path) => ({ path, changeType: 'modified' as const }));
    reviewTarget = input.reviewTarget;
  }

  const plan: ReviewPlanResult = {
    branch,
    title,
    description,
    repoRoot: storedRepoRoot,
    cliPath: storedCliPath,
    changedFiles,
    reviewTarget,
    domainIds: classification.domains,
    domainsToSpawn: classification.domainNames,
    classification: classification.classification,
    reviewScope,
    subagents: classification.domainNames.flatMap((domain) => {
      const scoped = relevantChangedFiles(domain, changedFiles);
      return shardChangedFiles(scoped).map(({ shard, files }) => ({
        domain,
        shard,
        scopedFiles: files.map((file) => file.path),
        agent: REVIEW_CONFIG.orchestration.reviewerAgent,
        promptCommand: promptCommand(storedCliPath, branch, domain, shard),
        spawnPrompt: createSpawnPrompt(storedCliPath, branch, domain, shard),
      }));
    }),
  };

  savePlan(branch, toStoredPlan(plan));
  return plan;
}

/**
 * Worktree mode (--base, no PR) has no GitHub review to read a scope marker
 * from. Round 1 requires an explicit --base (the task's starting commit).
 * Round N>1 defaults --base to the SHA the orchestrator recorded via
 * `round-complete` after that round's one fix commit landed, so the CLI
 * owns round continuity instead of the orchestrator's memory. An explicit
 * --base always overrides the stored marker.
 */
function resolveWorktreeBaseArgs(args: string[], branch: string): string[] {
  if (args.includes('--base') || args.includes('--diff')) {
    return args;
  }

  const marker = loadRoundMarker(branch);
  if (!marker) {
    return args;
  }

  console.error(
    `Defaulting --base to ${marker.sha} (round ${marker.round} complete marker for "${branch}").`,
  );
  return [...args, '--base', marker.sha];
}

export async function createPlanFromArgs(args: string[]): Promise<ReviewPlanResult> {
  const branch = requireArg(args, '--branch');
  const title = getArg(args, '--title') ?? REVIEW_CONFIG.orchestration.defaultTitle;
  const description =
    getArg(args, '--description') ?? REVIEW_CONFIG.orchestration.defaultDescription;
  const resolvedArgs = resolveWorktreeBaseArgs(args, branch);
  const input = await readReviewInputFromArgs(resolvedArgs, 'plan');
  return createPlanFromInput(branch, title, description, input, parseReviewScope(resolvedArgs));
}

export async function createPullRequestPlanFromArgs(args: string[]): Promise<ReviewPlanResult> {
  const branch = requireArg(args, '--branch');
  const prNumber = requireArg(args, '--pr');
  const title = getArg(args, '--title') ?? REVIEW_CONFIG.orchestration.defaultTitle;
  const description =
    getArg(args, '--description') ?? REVIEW_CONFIG.orchestration.defaultDescription;
  const headSha = fetchPullRequestHeadSha(prNumber);
  const previous = selectLatestReviewMetadata(fetchPullRequestReviews(prNumber));
  const diff = previous
    ? diffSinceLastReview(prNumber, previous.metadata.headSha, headSha)
    : runRequired('gh', ['pr', 'diff', prNumber]);

  const reviewScope: ReviewScope = previous
    ? {
        scope: 'incremental',
        headSha,
        baseSha: previous.metadata.headSha,
        sourceReviewId: previous.reviewId,
        sourceReviewSubmittedAt: previous.submittedAt,
      }
    : { scope: 'full', headSha, baseSha: null };

  return createPlanFromInput(
    branch,
    title,
    description,
    parseDiffOrFileList(diff, { mode: 'diff', source: 'stdin' }),
    reviewScope,
  );
}

function hasPlanInputSource(args: string[]): boolean {
  return args.includes('--base') || args.includes('--diff');
}

export function renderPlan(plan: ReviewPlanResult): string {
  return [
    '<REVIEW_PLAN_SUMMARY>',
    '<TARGET>',
    `branch_label: ${plan.branch}`,
    `changed_files_count: ${plan.changedFiles.length}`,
    `domains: ${plan.domainsToSpawn.join(', ')}`,
    '<TITLE>',
    plan.title,
    '</TITLE>',
    '<DESCRIPTION>',
    plan.description,
    '</DESCRIPTION>',
    '</TARGET>',
    '',
    '<CHANGED_FILES>',
    renderChangedFiles(plan.changedFiles),
    '</CHANGED_FILES>',
    '',
    '<SUBAGENTS>',
    renderSubagents(plan),
    '</SUBAGENTS>',
    '',
    '<ORCHESTRATOR_NEXT_STEPS>',
    'This summary is not the subagent spawn prompt.',
    `1. Run: ${planCommand(plan.cliPath, plan.branch)}`,
    '2. For each <SUBAGENT_TASK>, spawn the listed agent with exactly the text inside <PROMPT>.',
    `3. After all domain sessions finish, run: ${compileCommand(plan.cliPath, plan.branch)}`,
    '</ORCHESTRATOR_NEXT_STEPS>',
    '</REVIEW_PLAN_SUMMARY>',
  ].join('\n');
}

export function renderPlanTasks(plan: ReviewPlanResult): string {
  const tasks = plan.subagents
    .map((subagent) =>
      [
        '<SUBAGENT_TASK>',
        `agent: ${subagent.agent}`,
        `domain: ${subagent.domain}`,
        ...(subagent.shard ? [`shard: ${subagent.shard}`] : []),
        '<PROMPT>',
        subagent.spawnPrompt,
        '</PROMPT>',
        '</SUBAGENT_TASK>',
      ].join('\n'),
    )
    .join('\n\n');

  return [
    '<SUBAGENT_TASKS>',
    '<ORCHESTRATOR_INSTRUCTIONS>',
    'This output is for the orchestrator only.',
    'Do not pass this entire output to a reviewer subagent.',
    'Spawn one subagent per <SUBAGENT_TASK>.',
    "Pass exactly the text inside that task's <PROMPT> block to the spawned subagent.",
    'The orchestrator must not execute the prompt commands itself.',
    '</ORCHESTRATOR_INSTRUCTIONS>',
    tasks,
    '<ORCHESTRATOR_AFTER_SUBAGENTS>',
    'After all spawned subagents finish, run:',
    compileCommand(plan.cliPath, plan.branch),
    '</ORCHESTRATOR_AFTER_SUBAGENTS>',
    '</SUBAGENT_TASKS>',
  ].join('\n');
}

export async function renderPlanTasksFromArgs(args: string[]): Promise<string> {
  const plan = hasPlanInputSource(args)
    ? await createPlanFromArgs(args)
    : loadPlan(requireArg(args, '--branch'));
  return renderPlanTasks(plan);
}

export function renderStoredPrompt(branch: string, domain: Domain, shard?: string): string {
  const plan = loadPlan(branch);
  const assigned = plan.subagents.find(
    (subagent) => subagent.domain === domain && (subagent.shard ?? null) === (shard ?? null),
  );
  if (!assigned) {
    throw new Error(
      `No stored plan task found for domain "${shardLabel(domain, shard)}" on branch "${branch}".`,
    );
  }

  return createStoredPrompt(plan, domain, assigned);
}
