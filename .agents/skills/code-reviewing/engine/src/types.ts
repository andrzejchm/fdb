export type Severity = 'critical' | 'warning';

export type ChangeType = 'added' | 'deleted' | 'modified';

export interface DiffHunk {
  oldStart: number;
  oldEnd: number;
  newStart: number;
  newEnd: number;
}

export interface ChangedFile {
  path: string;
  changeType: ChangeType;
  hunks?: DiffHunk[]; // absent when plan was built from file-list (no diff available)
}

export type Domain = string;

export type SkipReason =
  | 'changed-file-scope'
  | 'docs-only-change'
  | 'test-only-change'
  | 'no-relevant-runtime-surface'
  | 'other';

export interface Rule {
  slug: string;
  severity: Severity;
  description: string;
  /** Synthetic open-sweep rule injected at the end of every domain rule set. */
  sweep?: boolean;
}

export interface ReviewDomainConfig {
  id: number;
  name: Domain;
  ruleFile: string;
  /** Project config only: `false` ignores the bundled rule file, so the project file is the whole domain. */
  bundledRules?: boolean;
  /** Project config only: `true` removes a bundled domain. */
  disabled?: boolean;
}

/** Project rule-file entry that removes the bundled rule with the same slug. */
export interface DisabledRule {
  slug: string;
  disabled: true;
}

/** Shape of `.opencode/code-reviewing/review-config.json`, merged over the bundled config. */
export interface ProjectReviewConfig {
  domains?: Array<Partial<ReviewDomainConfig> & { name: Domain }>;
  classification?: Partial<ReviewCliConfig['classification']>;
  orchestration?: Partial<ReviewCliConfig['orchestration']>;
}

export interface ReviewCliConfig {
  domains: ReviewDomainConfig[];
  classification: {
    boundaryPatterns: Array<{ pattern: string; boundary: string }>;
    testPatterns: string[];
    codePatterns: string[];
    excludedCodePatterns: string[];
    specRoots: string[];
    uiRoots: string[];
    alwaysOnDomains: Domain[];
    codeDomains: Domain[];
    testDomains: Domain[];
    uiDomains: Domain[];
    /** Domains whose relevant file slice is specRoots + markdown files. */
    specDomains?: Domain[];
  };
  orchestration: {
    reviewerAgent: string;
    defaultTitle: string;
    defaultDescription: string;
    /** Max changed files per reviewer session before a domain is sharded. Default 30. */
    maxShardFiles?: number;
    /** Hard cap on shards per domain (shard size grows beyond maxShardFiles if hit). Default 4. */
    maxShardsPerDomain?: number;
  };
}

export interface ReviewInput {
  files: string[];
  proposalContent: string;
  rawInput?: string;
  reviewTarget: ReviewTarget;
}

export interface BaseReviewTarget {
  mode: 'base';
  source: 'git';
  baseRef: string;
  inputKind: 'diff';
  diffsDir?: string;
}

export interface DiffReviewTarget {
  mode: 'diff';
  source: 'path' | 'stdin';
  inputKind: 'diff' | 'file-list';
  diffPath?: string;
  storedInputPath?: string;
}

export type ReviewTarget = BaseReviewTarget | DiffReviewTarget;

export interface ReviewFinding {
  path: string;
  line: number;
  side: 'RIGHT' | 'LEFT';
  severity: Severity;
  rule: string;
  domain: Domain;
  body: string;
  rules?: string[];
  domains?: Domain[];
  reviewSummary?: ReviewOutcomeSummary;
}

export interface ReviewOutcomeSummary {
  totalReviewedRules: number;
  passedCount: number;
  skippedCount: number;
  findingCount: number;
}

export type ReviewScopeKind = 'full' | 'incremental' | 'manual';

export interface ReviewScope {
  scope: ReviewScopeKind;
  headSha?: string;
  baseSha?: string | null;
  sourceReviewId?: number;
  sourceReviewSubmittedAt?: string;
}

export interface ReviewMetadataMarker {
  schema: 'agentkit-code-review';
  version: 1;
  headSha: string;
  baseSha: string | null;
  scope: ReviewScopeKind;
  changedFilesHash: string;
  domains: Domain[];
  generatedAt: string;
  sourceReviewId?: number;
  sourceReviewSubmittedAt?: string;
}

/**
 * Worktree-mode (no-PR) round marker. Persists the commit SHA recorded right
 * after a review round's fixes were committed, so the next round's `plan
 * --base` can default to it instead of relying on the orchestrator's memory.
 * PR mode does not use this — it derives scope from GitHub review markers.
 */
export interface WorktreeRoundMarker {
  /** Round number this marker completes (1 = round 1's fixes landed). */
  round: number;
  /** HEAD SHA at the moment the round was marked complete. */
  sha: string;
  recordedAt: string;
}

export interface ReviewSession {
  branch: string;
  domain: Domain;
  /** Shard id (e.g. "s1") when the domain was split across multiple reviewers. */
  shard?: string;
  /** Changed-file paths this session is scoped to. Absent = all plan files. */
  scopedFiles?: string[];
  rules: Rule[];
  currentIndex: number;
  /** Total finding instances recorded across all rules. */
  findings: number;
  /** Finding instances recorded on the current (not yet closed) rule. */
  currentRuleFindings: number;
  /** Rules closed via rule-done (i.e. closed with at least one finding). */
  findingRules: number;
  passes: number;
  skipped: number;
  criticalPasses: number;
  criticalSkipped: number;
  criticalFindings: number;
  warningPasses: number;
  warningSkipped: number;
  warningFindings: number;
  startedAt: string;
  updatedAt: string;
}

export interface ClassificationResult {
  domains: number[];
  domainNames: Domain[];
  classification: {
    boundaries: string[];
    hasCode: boolean;
    hasSpec: boolean;
    hasUi: boolean;
    hasTests: boolean;
  };
}

export interface ReviewPlanSubagent {
  domain: Domain;
  /** Shard id (e.g. "s1") when the domain was split across multiple reviewers. */
  shard?: string;
  /** Changed-file paths this subagent reviews. Absent = all plan files. */
  scopedFiles?: string[];
  agent: string;
  promptCommand: string;
  spawnPrompt: string;
}

export interface ReviewPlanResult {
  branch: string;
  title: string;
  description: string;
  repoRoot: string;
  cliPath: string;
  changedFiles: ChangedFile[];
  reviewTarget?: ReviewTarget;
  domainIds: number[];
  domainsToSpawn: Domain[];
  classification: ClassificationResult['classification'];
  reviewScope?: ReviewScope;
  subagents: ReviewPlanSubagent[];
}

export interface StoredReviewPlan extends ReviewPlanResult {}
