# Code Review Orchestration

Use the bundled CLI at `<skill-dir>/engine/review-cli` (`<skill-dir>` is defined in `SKILL.md`).

## Contents

- Session Model
- Worktree-Mode Round Policy
- Required Flow
- CLI Commands
- Severity Order
- Orchestrator Budget
- Prompt Ownership

## Session Model

- Session identity is `--branch <label>` plus `--domain <name>` plus optional `--shard <id>`.
- Session state lives under `.review-sessions/<sanitized-branch>/`.
- Domain and shard files are isolated. Parallel review is safe across different domain+shard sessions.
- Starting the same `branch + domain + shard` twice is an error.
- On large PRs the plan shards each domain's relevant file slice (default: above 30 files, up to 4 shards per domain). Each shard task carries `--shard` in its prompt command; every CLI call for that session must repeat it.

## Worktree-Mode Round Policy

Worktree mode (`--base`, no PR, one agent at a time, direct-to-main) has no GitHub review to read a scope marker from, so the CLI persists its own round marker under `.review-sessions/<sanitized-branch>/round-marker.json`:

- Round 1: `--base` is the task's starting commit — pass it explicitly. No marker exists yet.
- After round 1's findings are fixed with exactly **one commit**, run `round-complete` to record that commit's SHA as the round-1-complete marker.
- Round N>1: omit `--base`. `plan` reads the round marker and defaults `--base` to it automatically — the CLI owns this, not the orchestrator's memory. An explicit `--base` always overrides the marker.
- Repeat fix-then-`round-complete` after every round so the next round's base stays accurate.
- One commit per fix round is a precondition the orchestrator/fixer must uphold — the CLI does not enforce it and cannot detect multiple commits collapsed or split incorrectly.

## Required Flow

1. Gather PR metadata.
2. **PR mode only:** Use the CLI to choose the review diff scope. It reads agentkit metadata from prior review bodies, uses the full PR diff when no prior marker exists, and uses an incremental diff from the last marked review SHA on re-runs.
3. Persist the orchestration plan to `.review-sessions/<sanitized-branch>/plan.json`:
   - PR mode: `<skill-dir>/engine/review-cli plan-pr --pr <n> --branch "<label>" --title "<pr title>" --description "<pr description>"`
   - Worktree mode, round 1: `<skill-dir>/engine/review-cli plan --branch "<label>" --base <task-starting-commit> --title "<pr title>" --description "<pr description>"`
   - Worktree mode, round N>1: after the previous round's fixes land in **one commit** and `round-complete` has recorded it, omit `--base` — the CLI defaults it to the recorded round marker: `<skill-dir>/engine/review-cli plan --branch "<label>" --title "<pr title>" --description "<pr description>"`
4. Read the tagged plan summary output. It is metadata only, not the spawn prompt.
5. Emit exact `<SUBAGENT_TASK>` blocks from the stored plan:
   - `<skill-dir>/engine/review-cli plan --branch "<label>" --tasks`
   - This output also includes the post-subagent compile command in `<ORCHESTRATOR_AFTER_SUBAGENTS>`.
6. The `plan --tasks` output is for the orchestrator only. Do not pass the entire output to a reviewer subagent.
7. **PR mode only:** Spawn the prior-findings verifier subagent **in the same message** as the domain subagents (all run in parallel). Pass it the PR number, owner, and repo, and tell it to load `code-reviewing`'s SKILL.md and follow the prior-findings verification reference it names. It reads code, adjudicates each surviving prior comment, and returns a blocking-critical count. In worktree mode skip this step.
8. Spawn exactly one subagent per returned `<SUBAGENT_TASK>` block. Large PRs emit multiple shard tasks per domain — spawn all of them; do not merge or drop shards.
9. Pass exactly the text inside that task's `<PROMPT>` block to the spawned subagent. Do not rewrite it. MUST additionally state the exact worktree working directory in the Task tool's own prompt/description (separate from the verbatim `<PROMPT>` text) — the CLI binary path inside `<PROMPT>` does not control the subagent's cwd; a subagent that runs `review-cli` from the wrong directory (e.g. the main checkout instead of its assigned worktree) resolves a different `.review-sessions/<branch>/` path and can silently overwrite or reset a sibling domain/shard session with no error.
10. The orchestrator must not execute the prompt commands itself.
11. MUST cross-check the session count after all subagents return: compare the domain/shard count in `compile`/`summary` output against the number of `<SUBAGENT_TASK>` blocks actually spawned. A mismatch means a session's state was clobbered (most commonly by a wrong-cwd `review-cli plan` call from another subagent) — do not proceed to `compile` until resolved. Checking `status`/`summary` mid-run while reviewers are still working is optional; this end-of-run count cross-check is not.
12. Compile once all domain sessions **and** the prior-findings verifier are complete. Pass the verifier's blocking-critical count so unaddressed prior criticals keep the review `REQUEST_CHANGES`:
    - `<skill-dir>/engine/review-cli compile --branch "<label>" --carried-criticals <count>`
    - Omit `--carried-criticals` (or pass `0`) in worktree mode and first-review runs.
13. **PR mode only:** Drop any compiled finding that duplicates a `resolved-in-code` or `wontfix-valid` verdict from the verifier (same file, same concern or nearby line). See the prior-findings verification reference named in `code-reviewing`'s SKILL.md.
14. PR mode: post the filtered findings from the repo root with `<skill-dir>/engine/submit-review.mjs <owner> <repo> <pr> <comments-file>`, where `<comments-file>` is the `Comments:` path that `compile` printed. The script drops findings that fall outside the PR diff, reproduces them in the review body as an inconclusive review, and writes `.review-outcome`.

## CLI Commands

- Plan a PR review with CLI-owned full vs incremental scope detection:
  - `<skill-dir>/engine/review-cli plan-pr --pr <n> --branch "<label>" --title "<pr title>" --description "<pr description>"`
- Start a domain session (append `--shard <id>` for sharded plan tasks; same for every command below):
  - `<skill-dir>/engine/review-cli start --branch "<label>" --domain security`
  - `<skill-dir>/engine/review-cli start --branch "<label>" --domain security --shard s1`
- Print the full stored reviewer instructions for one domain or shard:
  - `<skill-dir>/engine/review-cli prompt --branch "<label>" --domain security`
- Look up one canonical rule by slug:
  - `<skill-dir>/engine/review-cli rule --slug qual-dry-violation`
  - `<skill-dir>/engine/review-cli rule --slug qual-dry-violation --domain code-quality --json`
- Reprint the current rule:
  - `<skill-dir>/engine/review-cli next --branch "<label>" --domain security`
- Record a pass (critical rules reject evidence that cites no changed-file path):
  - `<skill-dir>/engine/review-cli pass --branch "<label>" --domain security --evidence "<files or diffs read + concrete condition verified>"`
- Record a skip for a structurally impossible warning rule:
  - `<skill-dir>/engine/review-cli skip --branch "<label>" --domain security --reason changed-file-scope --note "<structural path/file-type reason>"`
- Record a finding (does NOT advance the rule — record one finding per violating file:line, then close with `rule-done`):
  - Preferred for Markdown: write the body to a temp file, then run `<skill-dir>/engine/review-cli finding --branch "<label>" --domain security --file <path> --line <n> --side RIGHT|LEFT --body-file "<path-to-temp-file>"`
  - Alternative for piped input: `<skill-dir>/engine/review-cli finding --branch "<label>" --domain security --file <path> --line <n> --side RIGHT|LEFT --body-stdin`
  - Optional `--severity warning` downgrades a non-blocking instance recorded under a critical rule.
  - Inline `--body "<text>"` is only safe for plain text without shell-sensitive Markdown. Do not put backticks, quotes, or `$()` in shell arguments.
- Close the current rule after recording its findings:
  - `<skill-dir>/engine/review-cli rule-done --branch "<label>" --domain security`
- Compile findings into the GitHub review payload, carrying unaddressed prior criticals from the verifier (PR re-review only — see the prior-findings verification reference named in `code-reviewing`'s SKILL.md):
  - `<skill-dir>/engine/review-cli compile --branch "<label>" --carried-criticals <count>`
- Check one domain or all domains:
  - `<skill-dir>/engine/review-cli status --branch "<label>"`
  - `<skill-dir>/engine/review-cli status --branch "<label>" --domain security`
- Check branch-wide progress:
  - `<skill-dir>/engine/review-cli summary --branch "<label>"`
- Validate session consistency:
  - `<skill-dir>/engine/review-cli doctor --branch "<label>"`
- Store or read reviewer notes:
  - `<skill-dir>/engine/review-cli notes --branch "<label>" --domain security --append "<note>"`
  - `<skill-dir>/engine/review-cli show-notes --branch "<label>" --domain security`
- Reset a stuck session:
  - `<skill-dir>/engine/review-cli reset --branch "<label>" --domain security`
  - `<skill-dir>/engine/review-cli reset --branch "<label>"`
- **Worktree mode only:** record the current git HEAD as this round's completion SHA, after its one fix commit lands (the next `--base`-less `plan` call for this branch reads it):
  - `<skill-dir>/engine/review-cli round-complete --branch "<label>"`

## Severity Order

- The CLI always serves `critical` rules first.
- Once a domain exhausts `critical` rules, the CLI automatically advances to `warning` rules.
- Every domain ends with a final critical open-sweep rule for real issues the canonical rules did not cover.
- `compile` preserves comprehensive findings and writes criticals before warnings.

## Orchestrator Budget

The orchestrator only does this:
- Fetch PR title, description, and changed files.
- In PR mode, call `plan-pr` so the CLI chooses full vs incremental review scope.
- Run `plan`, then `plan --tasks`.
- Launch the prior-findings verifier + all domain/shard subagents in one parallel message (PR mode), each with its worktree working directory stated explicitly in the Task prompt.
- Optionally check `status` or `summary` while reviewers run; MUST cross-check the final domain/shard session count against the number of subagents spawned before compiling (see Required Flow step 11).
- Run `compile` with the verifier's `--carried-criticals` count after the verifier finishes.
- Drop findings duplicating verifier `resolved-in-code`/`wontfix-valid` verdicts (PR mode).
- Post the filtered findings.
- In worktree mode, after fixes for a round land in one commit, run `round-complete` before starting the next round's `plan`.

The orchestrator does not:
- Read production code for review.
- Read canonical rule files directly.
- Manually dedupe or reorder findings outside the CLI and verifier dedup.

## Prompt Ownership

- The CLI owns the reviewer prompt templates in `<skill-dir>/engine/config/prompts/`, or the project copies in `.opencode/code-reviewing/prompts/` when present.
- The CLI owns both the spawn prompt and the full reviewer prompt.
- Reviewer prompts treat scoped diffs as the primary review context for changed files.
- In PR re-review mode, the scoped diff contains only changes since the most recent agentkit review marker. Reviewers may read full files for context, but the review mandate and inline findings stay scoped to the incremental changed hunks.
- Review changed hunks first. Read full files only when the scoped diff is insufficient for the current rule.
- Do not report pre-existing issues outside changed hunks unless the change introduced, exposed, or now depends on them. When reporting such issues, anchor the finding to the changed line that creates the dependency and quote the pre-existing code in the finding body — the CLI hard-blocks findings on files not in the diff.
- The default `plan` output is a tagged summary for the orchestrator. It is never passed to a reviewer subagent.
- The `review-cli plan --tasks` output is for the orchestrator only.
- The `review-cli plan --tasks` output includes the post-subagent compile command, but the canonical command is the CLI output itself.
- Do not pass the entire `review-cli plan --tasks` output to a reviewer subagent.
- Spawn one subagent per `<SUBAGENT_TASK>` and pass exactly the text inside that task's `<PROMPT>` block.
- The orchestrator must not execute the prompt commands itself.
- Do not duplicate or hand-edit reviewer instructions in this document.
