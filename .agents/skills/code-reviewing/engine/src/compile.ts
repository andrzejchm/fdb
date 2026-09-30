import type { Domain, ReviewFinding } from './types.ts';

export function compileFindings(findings: ReviewFinding[]): ReviewFinding[] {
  const seen = new Map<string, ReviewFinding>();

  for (const finding of findings) {
    const key = `${finding.path}:${finding.line}:${finding.side}`;
    const existing = seen.get(key);
    if (!existing) {
      seen.set(key, { ...finding, rules: [finding.rule], domains: [finding.domain] });
      continue;
    }

    const domains = [
      ...new Set([...(existing.domains ?? [existing.domain]), finding.domain]),
    ] as Domain[];
    const rules = [...new Set([...(existing.rules ?? [existing.rule]), finding.rule])];
    const severity =
      finding.severity === 'critical' || existing.severity === 'critical' ? 'critical' : 'warning';
    const body =
      existing.body === finding.body ? existing.body : `${existing.body}\n\n---\n${finding.body}`;

    const merged: ReviewFinding = {
      ...existing,
      severity,
      body,
      rules,
      domains,
    };

    if (finding.severity === 'critical' && existing.severity !== 'critical') {
      merged.rule = finding.rule;
      merged.domain = finding.domain;
    }

    seen.set(key, merged);
  }

  return [...seen.values()].sort((left, right) => {
    if (left.severity !== right.severity) {
      return left.severity === 'critical' ? -1 : 1;
    }

    if (left.path !== right.path) {
      return left.path.localeCompare(right.path);
    }

    return left.line - right.line;
  });
}
