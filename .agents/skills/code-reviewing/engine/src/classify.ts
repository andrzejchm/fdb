import { execSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';

import { DOMAIN_IDS, REVIEW_CONFIG, domainNameFromId } from './rules.ts';
import { diffFilePath, ensureSessionDirectories } from './session-store.ts';
import type { ChangeType, ClassificationResult, DiffReviewTarget, ReviewInput } from './types.ts';

const BOUNDARY_PATTERNS = REVIEW_CONFIG.classification.boundaryPatterns.map(
  ({ pattern, boundary }) => ({
    pattern: new RegExp(pattern),
    boundary,
  }),
);

const TEST_PATTERNS = REVIEW_CONFIG.classification.testPatterns.map(
  (pattern) => new RegExp(pattern),
);
const CODE_PATTERNS = REVIEW_CONFIG.classification.codePatterns.map(
  (pattern) => new RegExp(pattern),
);
const EXCLUDED_CODE_PATTERNS = REVIEW_CONFIG.classification.excludedCodePatterns.map(
  (pattern) => new RegExp(pattern),
);

export function isTestFile(filePath: string): boolean {
  return TEST_PATTERNS.some((pattern) => pattern.test(filePath));
}

export function isCodeFile(filePath: string): boolean {
  return CODE_PATTERNS.some((pattern) => pattern.test(filePath));
}

export function isReviewInfrastructureFile(filePath: string): boolean {
  return EXCLUDED_CODE_PATTERNS.some((pattern) => pattern.test(filePath));
}

export function getBoundaryFromPath(filePath: string): string | null {
  for (const { pattern, boundary } of BOUNDARY_PATTERNS) {
    if (pattern.test(filePath)) {
      return boundary;
    }
  }

  if (REVIEW_CONFIG.classification.specRoots.some((specRoot) => filePath.startsWith(specRoot))) {
    return 'spec';
  }

  if (TEST_PATTERNS.some((pattern) => pattern.test(filePath))) {
    return 'tests';
  }

  return null;
}

function parseProposalBoundaries(content: string): Set<string> {
  const boundaries = new Set<string>();
  const sectionMatch = content.match(/##\s+Affected Boundaries\s*\n([\s\S]*?)(?=\n##|\s*$)/);
  if (!sectionMatch) {
    return boundaries;
  }

  const knownBoundaries = new Set(['contracts+db', 'api', 'worker', 'web']);
  for (const line of sectionMatch[1].split('\n')) {
    const match = line.match(/^\s*-\s+\*\*([^*]+)\*\*\s*:\s*(.+)/);
    if (!match) {
      continue;
    }

    const name = match[1].trim().toLowerCase();
    const value = match[2].trim();
    if (knownBoundaries.has(name) && !value.startsWith('N/A')) {
      boundaries.add(name);
    }
  }

  return boundaries;
}

function extractFilesFromDiff(diff: string): string[] {
  const files: string[] = [];
  for (const line of diff.split('\n')) {
    const match = line.match(/^diff --git a\/.+ b\/(.+)/);
    if (match) {
      files.push(match[1]);
    }
  }
  return files;
}

function extractProposalFromDiff(diff: string): string {
  const lines = diff.split('\n');
  let inProposal = false;
  const proposalLines: string[] = [];

  for (const line of lines) {
    if (line.startsWith('diff --git ')) {
      inProposal = line.includes('/proposal.md ') || line.endsWith('/proposal.md');
      continue;
    }

    if (inProposal && line.startsWith('+') && !line.startsWith('+++')) {
      proposalLines.push(line.slice(1));
    }
  }

  return proposalLines.join('\n');
}

/**
 * Reads <repoRoot>/.review-ignore and returns active glob patterns.
 * Strips blank lines and comment lines (starting with #).
 * Returns [] if the file does not exist — never throws.
 */
export function loadReviewIgnore(repoRoot: string): string[] {
  const filePath = join(repoRoot, '.review-ignore');
  if (!existsSync(filePath)) {
    return [];
  }

  return readFileSync(filePath, 'utf8')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'));
}

/**
 * Returns true if filePath matches any of the given glob patterns.
 *
 * Matching rules (no external dependencies — Node built-ins only):
 * - Exact match: pattern equals filePath
 * - `**\/` prefix patterns: match anywhere in the path tree
 * - `*` wildcard within a path segment: match any characters in that segment
 *
 * Also tests a `**\/<pattern>` variant for patterns with no `/` so bare
 * patterns like `*.json` match in subdirectories.
 */
export function isIgnored(filePath: string, patterns: string[]): boolean {
  for (const pattern of patterns) {
    if (matchesGlob(filePath, pattern)) {
      return true;
    }
    // For patterns without a directory separator, also try **/<pattern>
    if (!pattern.includes('/') && matchesGlob(filePath, `**/${pattern}`)) {
      return true;
    }
  }
  return false;
}

/**
 * Matches filePath against a single glob pattern.
 * Supports `**` (any number of path segments) and `*` (any characters within a segment).
 */
function matchesGlob(filePath: string, pattern: string): boolean {
  // Build a regex from the glob pattern
  const regexSource = globToRegexSource(pattern);
  const regex = new RegExp(`^${regexSource}$`);
  return regex.test(filePath);
}

/**
 * Converts a glob pattern string to a regex source string (without anchors).
 * Supports `**` (any path depth) and `*` (any characters in a single segment).
 */
function globToRegexSource(pattern: string): string {
  // Split on ** first to handle multi-segment wildcards
  const parts = pattern.split('**/');
  if (parts.length === 1) {
    // No **/ in pattern — treat as a literal path with single-segment wildcards
    return segmentToRegex(pattern);
  }

  // Join parts with "anything including path separators"
  return parts.map((part) => segmentToRegex(part)).join('(?:.+/)?');
}

/**
 * Converts a single path segment (may contain `*`) to a regex source string.
 * `*` matches any characters except a path separator.
 */
function segmentToRegex(segment: string): string {
  return segment
    .split('*')
    .map((part) => escapeRegex(part))
    .join('[^/]*');
}

function escapeRegex(str: string): string {
  return str.replace(/[.+^${}()|[\]\\]/g, '\\$&');
}

const NOISE_LINE_PATTERNS = [
  /^diff --git a\/.+ b\/.+/,
  /^index [0-9a-f]+\.\.[0-9a-f]+/,
  /^--- (a\/|\/dev\/null)/,
  /^\+\+\+ (b\/|\/dev\/null)/,
  /^Binary files /,
  /^new file mode /,
  /^deleted file mode /,
  /^old mode /,
  /^new mode /,
];

function detectChangeType(rawChunkLines: string[]): ChangeType {
  const hasFromNull = rawChunkLines.some((line) => line.startsWith('--- /dev/null'));
  const hasToNull = rawChunkLines.some((line) => line.startsWith('+++ /dev/null'));

  if (hasFromNull && !hasToNull) {
    return 'added';
  }
  if (hasToNull && !hasFromNull) {
    return 'deleted';
  }
  return 'modified';
}

export function splitAndCleanDiff(
  fullDiff: string,
  ignoredPatterns: string[] = [],
): Map<string, { content: string; changeType: ChangeType }> {
  const result = new Map<string, { content: string; changeType: ChangeType }>();
  const lines = fullDiff.split('\n');

  let currentFile: string | null = null;
  let currentLines: string[] = [];
  let rawChunkLines: string[] = [];

  function flushCurrentFile(): void {
    if (currentFile !== null) {
      if (!isIgnored(currentFile, ignoredPatterns)) {
        // Trim trailing blank line introduced by the final \n split
        const content = currentLines.join('\n').replace(/\n$/, '');
        const changeType = detectChangeType(rawChunkLines);
        result.set(currentFile, { content, changeType });
      }
    }
  }

  for (const line of lines) {
    const headerMatch = line.match(/^diff --git a\/.+ b\/(.+)/);
    if (headerMatch) {
      flushCurrentFile();
      currentFile = headerMatch[1];
      currentLines = [];
      rawChunkLines = [];
      // Do not include the header line itself
      continue;
    }

    if (currentFile !== null) {
      rawChunkLines.push(line);
      const isNoise = NOISE_LINE_PATTERNS.some((pattern) => pattern.test(line));
      if (!isNoise) {
        currentLines.push(line);
      }
    }
  }

  flushCurrentFile();
  return result;
}

export function savePerFileDiffs(
  branch: string,
  diffMap: Map<string, { content: string; changeType: ChangeType }>,
  ignoredPatterns: string[] = [],
): void {
  ensureSessionDirectories(branch);
  for (const [filePath, { content }] of diffMap) {
    if (isIgnored(filePath, ignoredPatterns)) {
      continue;
    }
    const outputPath = diffFilePath(branch, filePath);
    mkdirSync(dirname(outputPath), { recursive: true });
    writeFileSync(outputPath, numberDiffLines(content));
  }
}

const HUNK_HEADER = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/;

/**
 * Prefix every hunk line with its real line number so reviewers copy the number
 * instead of counting: `R<n> |` for context/added lines (new file, --side RIGHT),
 * `L<n> |` for removed lines (old file, --side LEFT). The original diff line follows
 * the `|` verbatim.
 */
export function numberDiffLines(diff: string): string {
  let oldLine = 0;
  let newLine = 0;
  let inHunk = false;

  return diff
    .split('\n')
    .map((line) => {
      const hunk = HUNK_HEADER.exec(line);
      if (hunk) {
        oldLine = Number(hunk[1]);
        newLine = Number(hunk[2]);
        inHunk = true;
        return line;
      }
      if (!inHunk) {
        return line;
      }
      if (line.startsWith('+')) {
        return `R${newLine++} |${line}`;
      }
      if (line.startsWith('-')) {
        return `L${oldLine++} |${line}`;
      }
      if (line.startsWith(' ')) {
        oldLine++;
        return `R${newLine++} |${line}`;
      }
      return line;
    })
    .join('\n');
}

export function parseDiffOrFileList(
  input: string,
  reviewTarget: Omit<DiffReviewTarget, 'inputKind'>,
): ReviewInput {
  if (input.includes('diff --git ')) {
    return {
      files: extractFilesFromDiff(input),
      proposalContent: extractProposalFromDiff(input),
      rawInput: input,
      reviewTarget: { ...reviewTarget, inputKind: 'diff' },
    };
  }

  return {
    files: input.trim().split('\n').filter(Boolean),
    proposalContent: '',
    rawInput: input,
    reviewTarget: { ...reviewTarget, inputKind: 'file-list' },
  };
}

function diffAgainstBase(baseRef: string): string {
  const result = spawnSync('git', ['diff', `${baseRef}...HEAD`], { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `git diff ${baseRef}...HEAD failed`);
  }

  return result.stdout;
}

export function classify(files: string[], proposalContent = ''): ClassificationResult {
  const hasCode = files.some(
    (file) =>
      !isReviewInfrastructureFile(file) &&
      isCodeFile(file) &&
      !isTestFile(file) &&
      !file.endsWith('.md'),
  );
  const hasUi = files.some(
    (file) =>
      REVIEW_CONFIG.classification.uiRoots.some((uiRoot) => file.startsWith(uiRoot)) &&
      !file.endsWith('.md'),
  );
  const hasSpec = files.some((file) =>
    REVIEW_CONFIG.classification.specRoots.some((specRoot) => file.startsWith(specRoot)),
  );
  const hasTests = files.some((file) => !isReviewInfrastructureFile(file) && isTestFile(file));

  const boundaries = new Set<string>();
  for (const file of files) {
    const boundary = getBoundaryFromPath(file);
    if (boundary && boundary !== 'spec' && boundary !== 'tests') {
      boundaries.add(boundary);
    }
  }

  if (proposalContent) {
    for (const boundary of parseProposalBoundaries(proposalContent)) {
      boundaries.add(boundary);
    }
  }

  const domains = REVIEW_CONFIG.classification.alwaysOnDomains.map((domain) => DOMAIN_IDS[domain]);
  if (hasCode || (hasSpec && boundaries.size > 0)) {
    domains.push(...REVIEW_CONFIG.classification.codeDomains.map((domain) => DOMAIN_IDS[domain]));
  }

  if (hasCode || hasTests || (hasSpec && boundaries.size > 0)) {
    domains.push(...REVIEW_CONFIG.classification.testDomains.map((domain) => DOMAIN_IDS[domain]));
  }

  if ((hasCode && hasUi) || (hasSpec && boundaries.has('web'))) {
    domains.push(...REVIEW_CONFIG.classification.uiDomains.map((domain) => DOMAIN_IDS[domain]));
  }

  const uniqueDomains = [...new Set(domains)].sort((left, right) => left - right);

  return {
    domains: uniqueDomains,
    domainNames: uniqueDomains.map((domainNumber) => domainNameFromId(domainNumber)),
    classification: {
      boundaries: [...boundaries].sort(),
      hasCode,
      hasSpec,
      hasUi,
      hasTests,
    },
  };
}

async function readStdin(): Promise<string> {
  return await new Promise<string>((resolve, reject) => {
    let input = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      input += chunk;
    });
    process.stdin.on('end', () => {
      resolve(input);
    });
    process.stdin.on('error', (error) => {
      reject(error);
    });
    process.stdin.resume();
  });
}

export async function readReviewInputFromArgs(
  args: string[],
  commandName = 'classify',
): Promise<ReviewInput> {
  const usageError =
    'No input provided. Use one of:\n' +
    `  ${commandName} --base <ref>\n` +
    `  ${commandName} --diff <path>\n` +
    '  pipe via stdin';

  if (args.includes('--base')) {
    const baseRef = args[args.indexOf('--base') + 1];
    if (!baseRef) {
      throw new Error('--base requires a git ref');
    }

    const diff = diffAgainstBase(baseRef);
    return {
      files: extractFilesFromDiff(diff),
      proposalContent: extractProposalFromDiff(diff),
      rawInput: diff,
      reviewTarget: {
        mode: 'base',
        source: 'git',
        baseRef,
        inputKind: 'diff',
      },
    };
  }

  if (args.includes('--diff')) {
    const diffPath = args[args.indexOf('--diff') + 1];
    if (!diffPath) {
      throw new Error('--diff requires a path');
    }

    return parseDiffOrFileList(readFileSync(diffPath, 'utf8'), {
      mode: 'diff',
      source: 'path',
      diffPath,
    });
  }

  if (!process.stdin.isTTY) {
    const input = await readStdin();
    if (input.trim().length === 0) {
      throw new Error(usageError);
    }

    return parseDiffOrFileList(input, {
      mode: 'diff',
      source: 'stdin',
    });
  }

  throw new Error(usageError);
}

export async function classifyFromArgs(args: string[]): Promise<ClassificationResult> {
  const input = await readReviewInputFromArgs(args, 'classify');
  return classify(input.files, input.proposalContent);
}

export function renderClassification(result: ClassificationResult): string {
  const boundaries =
    result.classification.boundaries.length > 0
      ? result.classification.boundaries.join(', ')
      : 'none';

  return [
    `domains: ${result.domainNames.join(', ')}`,
    `hasCode: ${result.classification.hasCode}`,
    `hasSpec: ${result.classification.hasSpec}`,
    `hasUi: ${result.classification.hasUi}`,
    `hasTests: ${result.classification.hasTests}`,
    `boundaries: ${boundaries}`,
  ].join('\n');
}
