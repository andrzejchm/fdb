---
name: code-reviewing
description: Use when asked to review a PR, check code, or validate changes before merge. Drives the CLI-based review flow using the review-cli engine bundled in this skill.
compatibility: opencode
metadata:
  schemaVersion: "1"
  version: "4.4.0"
  stability: stable
  category: workflow
  appliesTo: any
---

Load this skill before any other review skill.

`<skill-dir>` in this skill's commands and paths is the directory this SKILL.md was loaded from, relative to the repo root: `.opencode/skills/code-reviewing` or `.agents/skills/code-reviewing`, depending on the project's install path. Substitute it and run every command from the repo root.

The review engine ships inside this skill at `<skill-dir>/engine/review-cli`. It runs its TypeScript source directly on Node >= 23 (native type stripping) — no build step, no `node_modules`, no `dist/`. Just call `review-cli` (in CI and locally alike).

`engine/` is a documented pre-existing exception to the usual `scripts/`/`references/`/`assets/` layout: it is a self-contained executable CLI (config, rules, prompts, TypeScript source) that CI and every reviewer subagent invoke directly by path, so it stays in place rather than being restructured or relocated.

Read `ORCHESTRATION.md` next.

Ground rules:
- Use `<skill-dir>/engine/review-cli` as the only review engine.
- Use `<skill-dir>/engine/review-cli plan` or `plan-pr` as the only orchestration source of truth.
- Reviewer prompts from the CLI are authoritative, including how to read diffs and record line numbers.
- Do not read review rule files directly. The CLI owns the canonical rule corpus.
- Spawn reviewer subagents. Do not perform the domain review in the orchestrator.
- One subagent per `branch + domain + shard`. Never run the same domain+shard twice for the same branch. On large PRs the plan splits a domain into shards (`--shard s1`, `s2`, ...) so each reviewer owns a slice of the changed files small enough to read in full; spawn every shard task the plan emits.
- The CLI serves all `critical` rules before any `warning` rules, then a final critical open-sweep rule for issues the canonical rules did not cover.
- `finding` records one violation instance and does not advance the rule. Record every instance (one finding per file:line), then close the rule with `rule-done`. Findings are issue-count-bound, not rule-count-bound: a rule violated in five places produces five findings.
- Use `--severity warning` on a finding to downgrade a non-blocking instance recorded under a critical rule (most useful during the sweep). Omit it otherwise.
- Final output is comprehensive. Keep all findings. Do not suppress warnings when criticals exist.
- On PR re-review, a prior-findings verifier adjudicates surviving prior comments (see `VERIFYING-PRIOR-FINDINGS.md`). Unaddressed prior criticals stay blocking — they are not cleared just because their code fell outside the incremental diff.
- Use `skip` only for `warning` rules when changed file paths or file types make the rule structurally impossible to apply. Reading relevant files and finding no issue is a `pass`, not a skip. Critical rules cannot be skipped — the CLI will hard-block the attempt. For every critical rule you must either `pass` (rule applies, no issue found) or record findings and close with `rule-done`. Attempting to `skip` a critical rule exits with an error and reprints the rule; re-read the diff and make an explicit judgment.
- Critical passes need real evidence: the CLI rejects evidence under 30 characters or evidence that cites no changed-file path (use the token `file-list` plus reasoning when non-applicability is clear from paths alone).
- Record Markdown findings with `--body-file` or `--body-stdin`. Do not put Markdown finding bodies in shell arguments; backticks, quotes, and `$()` are not shell-safe.
- Write finding bodies like a direct human teammate — no chatbot filler, unsupported hedging, or sycophantic openings; apply `humanizing-ai-text`'s rules to every finding body.

## Rule Authoring

- Add reusable company-wide rules in agentkit: `skills/code-reviewing/engine/rules/<domain-rule-file>.json`. Bundled rules and config stay stack-neutral: no product paths, frameworks, or domain vocabulary. Anything tied to one product's stack goes in that product's repo.
- Add repo-specific rules in the consumer repo: `.opencode/code-reviewing/rules/<domain-rule-file>.json`.
- Repo-specific rule files extend bundled rules; they do not replace them. If a repo-specific rule uses the same `slug` as a bundled rule, the repo-specific rule overrides that bundled rule.
- To drop one bundled rule, add `{ "slug": "<slug>", "disabled": true }` to the repo-specific file for that domain. The CLI fails if the slug matches no bundled rule, so a typo or an upstream rename cannot silently turn the rule back on.
- Every `slug` MUST be unique within its file — slug is the override key, so a repeat overwrites the earlier rule and that check never reaches a reviewer. The CLI refuses to load a file that repeats one. Give each check its own slug (`spec-tasks-sections-missing`, `spec-tasks-lifecycle-counts`), never one shared topic slug.
- Do not edit anything under `<skill-dir>/engine/` in consumer repos. That directory is owned by `agentkit skills update` and is replaced on update. Every customization goes in `.opencode/code-reviewing/`.
- After changing rules, verify lookup with `<skill-dir>/engine/review-cli rule --slug <slug> --domain <domain>`.

## Project Config

`.opencode/code-reviewing/review-config.json` is merged over the bundled `engine/config/review-config.json`. Set only the keys that differ:

```json
{
  "domains": [
    { "name": "spec-docs", "disabled": true },
    { "name": "security", "bundledRules": false },
    { "id": 6, "name": "ui-compliance", "ruleFile": "ui-rules.json" }
  ],
  "classification": {
    "codePatterns": ["^apps/", "^packages/"],
    "uiRoots": ["apps/web/"],
    "uiDomains": ["ui-compliance"]
  }
}
```

- `domains` merge by `name`. `"disabled": true` removes a bundled domain, including from every classification group. `"bundledRules": false` keeps the domain but loads only the repo-specific rule file. A new domain needs `id`, `name`, and `ruleFile`, and its rules live only in the repo-specific file.
- `classification` and `orchestration` merge per key. A key you set replaces the bundled value, including whole arrays.
- The bundled classification counts every non-test, non-Markdown file as code and defines no boundaries or UI roots. Set `boundaryPatterns`, `codePatterns`, `uiRoots`, and `uiDomains` for your repo layout.
- To replace a reviewer prompt template, put a file with the same name as one in `engine/config/prompts/` into `.opencode/code-reviewing/prompts/`. The project copy is used in its place, and later upstream edits to that template do not reach it.
