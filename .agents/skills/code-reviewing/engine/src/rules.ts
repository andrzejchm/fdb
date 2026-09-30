import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import type {
  DisabledRule,
  Domain,
  ProjectReviewConfig,
  ReviewCliConfig,
  ReviewDomainConfig,
  Rule,
} from './types.ts';

export interface RuleLookupResult extends Rule {
  domain: Domain;
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const TOOL_ROOT = join(__dirname, '..');

// Project-level override directory: .opencode/code-reviewing/ relative to cwd.
// Resolved once at startup so it stays consistent across all rule loads in a session.
const PROJECT_OVERRIDES_DIR = join(process.cwd(), '.opencode', 'code-reviewing');

const PROJECT_CONFIG_PATH = join(PROJECT_OVERRIDES_DIR, 'review-config.json');
const PROJECT_PROMPTS_DIR = join(PROJECT_OVERRIDES_DIR, 'prompts');
const BUNDLED_CONFIG_PATH = join(TOOL_ROOT, 'config', 'review-config.json');
const BUNDLED_PROMPTS_DIR = join(TOOL_ROOT, 'config', 'prompts');

const DOMAIN_GROUP_KEYS = [
  'alwaysOnDomains',
  'codeDomains',
  'testDomains',
  'uiDomains',
  'specDomains',
] as const;

function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, 'utf8')) as T;
}

// The project config is merged over the bundled one instead of replacing it, so
// a repo states only what differs and still picks up upstream config changes.
// Domains merge by name; classification and orchestration merge per key (a
// project array replaces the bundled array for that key).
export function mergeReviewConfig(
  bundled: ReviewCliConfig,
  project: ProjectReviewConfig,
  projectPath = PROJECT_CONFIG_PATH,
): ReviewCliConfig {
  const domainsByName = new Map<Domain, Partial<ReviewDomainConfig>>(
    bundled.domains.map((domain) => [domain.name, domain]),
  );
  for (const domain of project.domains ?? []) {
    domainsByName.set(domain.name, { ...domainsByName.get(domain.name), ...domain });
  }

  const domains: ReviewDomainConfig[] = [];
  for (const [name, domain] of domainsByName) {
    if (domain.disabled) continue;
    if (typeof domain.id !== 'number' || !domain.ruleFile) {
      throw new Error(
        `Domain "${name}" in ${projectPath} needs an "id" and a "ruleFile" (it is not a bundled domain).`,
      );
    }
    domains.push(domain as ReviewDomainConfig);
  }
  // Domain id is the review order, so a project domain slots in by id, not at the end.
  domains.sort((left, right) => left.id - right.id);

  const duplicateIds = domains
    .map((domain) => domain.id)
    .filter((id, index, ids) => ids.indexOf(id) !== index);
  if (duplicateIds.length > 0) {
    throw new Error(`Duplicate domain ids in ${projectPath}: ${[...new Set(duplicateIds)].join(', ')}`);
  }

  const knownNames = new Set(domainsByName.keys());
  const activeNames = new Set(domains.map((domain) => domain.name));
  const classification = { ...bundled.classification, ...project.classification };
  for (const key of DOMAIN_GROUP_KEYS) {
    const group = classification[key];
    if (!group) continue;
    const unknown = group.filter((name) => !knownNames.has(name));
    if (unknown.length > 0) {
      throw new Error(`classification.${key} in ${projectPath} names unknown domains: ${unknown.join(', ')}`);
    }
    // A disabled domain drops out of every group so the planner never schedules it.
    classification[key] = group.filter((name) => activeNames.has(name));
  }

  return {
    domains,
    classification,
    orchestration: { ...bundled.orchestration, ...project.orchestration },
  };
}

const BUNDLED_CONFIG = readJson<ReviewCliConfig>(BUNDLED_CONFIG_PATH);

export const REVIEW_CONFIG = existsSync(PROJECT_CONFIG_PATH)
  ? mergeReviewConfig(BUNDLED_CONFIG, readJson<ProjectReviewConfig>(PROJECT_CONFIG_PATH))
  : BUNDLED_CONFIG;

export const DOMAIN_ORDER = REVIEW_CONFIG.domains.map((domain) => domain.name);
export const DOMAIN_IDS = Object.fromEntries(
  REVIEW_CONFIG.domains.map((domain) => [domain.name, domain.id]),
) as Record<Domain, number>;
export const DOMAIN_NAMES_BY_ID = Object.fromEntries(
  REVIEW_CONFIG.domains.map((domain) => [domain.id, domain.name]),
) as Record<number, Domain>;
const DOMAIN_CONFIGS = Object.fromEntries(
  REVIEW_CONFIG.domains.map((domain) => [domain.name, domain]),
) as Record<Domain, ReviewDomainConfig>;

export function domainNameFromId(domainId: number): Domain {
  const domainName = DOMAIN_NAMES_BY_ID[domainId];
  if (!domainName) {
    throw new Error(`Unknown domain id: ${domainId}`);
  }

  return domainName;
}

function sweepRule(domain: Domain): Rule {
  return {
    slug: `${domain}-sweep`,
    severity: 'critical',
    sweep: true,
    description:
      `Open sweep — final rule. Re-scan every scoped diff for any real ${domain} issue ` +
      'the previous rules did not cover. The canonical rules are not an exhaustive list of what ' +
      'can be wrong; this rule exists so off-checklist issues still get reported. Walk the ' +
      'CHANGED FILES list, prioritizing files you have not read yet in this session, and record ' +
      'one finding per real issue (use `--severity warning` on the finding for non-blocking ' +
      'issues; omit it for blocking ones). Do not re-report findings already recorded by earlier ' +
      'rules and do not speculate. Pass only when a sweep of the remaining diffs surfaced ' +
      'nothing new, and cite which files you swept in the evidence.',
  };
}

// Slug is the override key, so a slug repeated inside one file silently discards
// every earlier copy instead of running it. Fail loudly rather than review less
// than the file claims.
function assertUniqueSlugs(rules: Rule[], rulePath: string): void {
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  for (const rule of rules) {
    if (seen.has(rule.slug)) duplicates.add(rule.slug);
    seen.add(rule.slug);
  }

  if (duplicates.size > 0) {
    throw new Error(
      `Duplicate rule slugs in ${rulePath}: ${[...duplicates].sort().join(', ')}. ` +
        'Each rule needs its own slug — repeats overwrite each other and never reach a reviewer.',
    );
  }
}

function isDisabledRule(rule: Rule | DisabledRule): rule is DisabledRule {
  return (rule as DisabledRule).disabled === true;
}

export function loadDomainRules(domain: Domain): Rule[] {
  const { ruleFile, bundledRules: useBundled = true } = DOMAIN_CONFIGS[domain];
  const bundledRulePath = join(TOOL_ROOT, 'rules', ruleFile);
  const projectRulePath = join(PROJECT_OVERRIDES_DIR, 'rules', ruleFile);

  // A project-only domain has no bundled file; `bundledRules: false` opts out of it.
  const bundledRules =
    useBundled && existsSync(bundledRulePath) ? readJson<Rule[]>(bundledRulePath) : [];
  const projectEntries = existsSync(projectRulePath)
    ? readJson<Array<Rule | DisabledRule>>(projectRulePath)
    : [];

  assertUniqueSlugs(bundledRules, bundledRulePath);
  assertUniqueSlugs(projectEntries as Rule[], projectRulePath);

  // Project rules extend bundled rules. A matching slug replaces the bundled
  // rule so repos can patch a rule without copying the full upstream file, and
  // a `{ "slug", "disabled": true }` entry removes it.
  const rulesBySlug = new Map<string, Rule>();
  for (const rule of bundledRules) rulesBySlug.set(rule.slug, rule);
  for (const entry of projectEntries) {
    if (!isDisabledRule(entry)) {
      rulesBySlug.set(entry.slug, entry);
      continue;
    }
    // Fail on an unknown slug: a typo or an upstream rename would otherwise
    // silently re-enable the rule the project meant to turn off.
    if (!rulesBySlug.has(entry.slug)) {
      throw new Error(
        `Cannot disable "${entry.slug}" in ${projectRulePath}: no bundled ${domain} rule has that slug.`,
      );
    }
    rulesBySlug.delete(entry.slug);
  }
  const rules = [...rulesBySlug.values()];

  if (rules.length === 0) {
    throw new Error(
      `No rules left for domain "${domain}" (checked ${bundledRulePath} and ${projectRulePath}). ` +
        'To stop reviewing this domain, disable it in the project review-config.json instead.',
    );
  }

  const criticals = rules.filter((rule) => rule.severity === 'critical');
  const warnings = rules.filter((rule) => rule.severity === 'warning');
  // The sweep rule always runs last: it covers whatever the canonical rules missed.
  return [...criticals, ...warnings, sweepRule(domain)];
}

export function loadPromptTemplate(fileName: string): string {
  const projectPromptPath = join(PROJECT_PROMPTS_DIR, fileName);
  const promptPath = existsSync(projectPromptPath)
    ? projectPromptPath
    : join(BUNDLED_PROMPTS_DIR, fileName);
  return readFileSync(promptPath, 'utf8').trimEnd();
}

export function lookupRulesBySlug(slug: string, domain?: Domain): RuleLookupResult[] {
  const domains = domain ? [domain] : DOMAIN_ORDER;

  return domains.flatMap((domainName) =>
    loadDomainRules(domainName)
      .filter((rule) => rule.slug === slug)
      .map((rule) => ({
        domain: domainName,
        ...rule,
      })),
  );
}
