# Review and Fix

Two related workflows: **fixing an open PR** against real GitHub reviews and CI, and the **review-fix polish loop** (subagent-orchestrated reviewer/fixer rounds, usable with or without an open PR).

## Contents

- Fixing a PR: Inputs
- Step-by-Step
- Pagination and Orchestration Rules
- Review-Fix Polish Loop
- Polish Loop Prompt Templates

## Fixing a PR: Inputs

Requires a PR number or URL. Pre-fetched PR data from an invoking command may be reused — skip re-fetching what's already available.

## Step-by-Step

Copy and track:

```
- [ ] Step 1: Checkout PR and verify base branch
- [ ] Step 2: Gather reviews, threads, and CI checks
- [ ] Step 2b: Triage CI failures
- [ ] Step 3: Assess all unresolved comment threads (VALID-FIX / VALID-WONTFIX / INVALID / STALE)
- [ ] Step 3b: Apply finding rule and fix-shape gate
- [ ] Step 4: Fix approved VALID-FIX items via developer subagent; verify fixes applied
- [ ] Step 5: Run the project's check command AND test command for every modified package; loop until both are green
- [ ] Step 6: Resolve threads per triage outcome
- [ ] Step 7: Run proportional self-review when the risk gate matches — do NOT post findings to GitHub
- [ ] Step 8: Triage review findings, fix VALID-FIX items, re-run verification if fixed
- [ ] Step 9: Commit and push
- [ ] Step 10: Re-request reviews from human reviewers
- [ ] Step 11: Post fix report
```

Execute steps in order. Do NOT skip steps unless explicitly noted.

**Step 1 — Checkout.** `gh pr checkout <number-or-url>` then `git pull`. Check `baseRefName`: if targeting anything other than the main branch, this is a stacked PR — report "blocked on parent PR" and stop if the parent is not merged.

**Step 2 — Gather data (run in parallel):** reviews (`gh api repos/{owner}/{repo}/pulls/<number>/reviews`), review threads via GraphQL `reviewThreads` (use this exclusively for triage — the REST `pulls/<number>/comments` endpoint does not expose `isResolved` and returns comments from already-resolved threads), thread comments per thread id, and `gh pr checks <number>`. Paginate both `reviewThreads` and each thread's `comments` with `pageInfo { hasNextPage endCursor }` until complete; comment cursors are per-thread, never reused across threads.

**Step 2b — Triage CI failures.** Fixable (broken test, lint error, typecheck failure, build error) → fix it, spawning a developer subagent if needed. Infra/flaky (intermittent network failure, runner timeout, external service) → note as a remaining blocker, do not attempt to fix it. Unknown → read the job logs (`gh run view <run-id> --log-failed`) before classifying. Do not proceed to Step 3 while fixable CI failures remain.

**Step 3 — Assess comments.** For every unresolved thread, determine: **VALID-FIX** (real issue, fix it); **VALID-WONTFIX** (real concern not minimal/obvious to fix in this PR — close it per SKILL.md's finding-reporting hard rule); **INVALID** (already fixed, misunderstanding, or a style preference that contradicts project conventions — reply only to human comments, never to bot comments); **STALE** (refers to code that no longer exists or was already addressed). Read the referenced files before assessing — never guess. Scope covers ALL inline comments, not just the latest review; an `APPROVED` review can still carry actionable comments requiring triage.

**Step 3b — Finding rule and fix-shape gate.** For every VALID-FIX item, record: rule slug and exact rule text for rule-based bot findings (extract the slug from the `[rule-slug]` prefix and fetch the canonical text with `code-reviewing`'s `<skill-dir>/engine/review-cli rule --slug <slug>`, per its ORCHESTRATION.md), or `source: human review` plus the reviewer and concern for human findings, plus the review id, head SHA, file/line, whether it targets PR-introduced code or pre-existing code only exposed by the PR, and the approved fix shape.

Approve only the smallest fix shape: no shared components, exported props, public APIs, or cross-package abstractions unless the finding explicitly requires that shape. Prefer narrowing, deleting, or reverting changed code over layering another abstraction. Stop and ask before broader abstraction, public API, cross-package, or unrelated file changes. If a finding appears caused by an over-broad review rule rather than the implementation, report that instead of editing production code.

**Step 4 — Fix valid issues.** Use one `developer` session for the whole fix round. Reuse the implementation developer's `task_id` when available; otherwise spawn once and retain its `task_id` for Step 8. Send: the findings list (file/line), the Step 3b records (rule slug + exact rule text, or `source: human review` + reviewer + concern, review id, head SHA, PR-introduced-vs-pre-existing classification, and approved fix shape), project conventions from AGENTS.md, and an instruction to apply only the approved fix shape. If fixing requires an unstated behavior, scope, or architecture choice, stop and report a clarification blocker — do not guess. If no approved minimal fix shape exists, report UNFIXABLE — do not invent a broader solution. Fix only VALID-FIX items and verification failures caused by those fixes; do not refactor, rename, reformat, or clean up nearby code unless required.
After the subagent returns, verify each fix was applied: re-read the changed files and confirm the issue is resolved. If a fix is missing or incorrect, resume the same session with targeted instructions.

**Step 5 — Verify LOCALLY before pushing.** NEVER push a fix without local verification passing first. For every package or module you modified, run the project's scoped check command (format, lint, typecheck) AND its scoped test command (unit tests), e.g. `task check:pkg -- <pkg>` and `task test:pkg -- <pkg>` in projects using the agentkit taskfile recipe. Both are required; run them as two separate commands. Skip full end-to-end runs here and let CI cover them. Fix, then re-run both before pushing.
A consistently failing end-to-end/browser test is a real regression, NOT a timing issue — NEVER add a timeout to "fix" it. Inspect the failing run's output, screenshot, or video to see what actually renders, diff what the relevant component produces before vs after your changes, and fix the broken code path. Timeout adjustments require profiling proof and an inline comment.

**Step 6 — Resolve threads (MANDATORY, do NOT skip).** Every review thread MUST be resolved or replied to — an unresolved thread signals ignored feedback. After verification passes:

- Resolve in bulk: `gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<threadId>"}) { thread { isResolved } } }'`.
- **VALID-FIX**: delete the bot comment (`gh api -X DELETE repos/{owner}/{repo}/pulls/comments/<id>`) ONLY after confirming the fix is present in the pushed diff (`gh pr diff <number>`). If the code was NOT changed at that location, do NOT delete — leave it unresolved so the next re-review adjudicates it instead of the finding silently vanishing.
- **INVALID/STALE**: delete the bot comment. If the finding was actually valid, the next review re-raises it.
- **VALID-WONTFIX**: **MUST reply with a rationale explaining WHY you are not fixing this. Do NOT resolve the thread — leave it unresolved.** A missing, vague, or non-responsive rationale on a critical finding gets re-raised and keeps the PR blocked. Every WONTFIX thread MUST have a reply, no exceptions. Also report it to the user in Step 11 per SKILL.md's finding-reporting hard rule — the GitHub reply alone doesn't satisfy it.
- **Needs user input**: do NOT resolve, delete, or reply — report it in Step 11.

**Step 6a — Closeout audit (gate before push/merge).** Produce a thread ledger covering every inline comment fetched in Step 2: thread id + comment id, triage outcome (FIX / WONTFIX / INVALID / STALE), GitHub action taken (resolved / deleted / replied), and the review state of the parent review. If any comment has no recorded action — including comments on APPROVED reviews — Step 6 is incomplete and the PR is NOT merge-ready.

**Step 7 — Re-review or self-review.** Skip this step entirely when fixes only address already-reviewed findings inside the original approved fix shape and do not broaden behavior — go straight to Step 8.

Otherwise, check whether the project's CI already runs a full automated review triggered on PR open, push, or a re-review label/trigger (check the project's CI workflow configuration). If it does, do NOT spawn a local reviewer fan-out here — it would duplicate the same review engine CI already runs. Step 10 re-triggers that review after push; treat its result as this step's review.

If the project has no such CI-triggered review, run a local proportional self-review when a fix touches authentication/permissions, external side effects, schema or data migrations, three or more app/package boundaries, or code outside the approved fix shape. When it runs, spawn a `reviewer` subagent to orchestrate a full code review. The subagent must:

1. Load the `code-reviewing` skill for ground rules and the full orchestration workflow.
2. Follow the orchestration steps: spawn reviewer sub-subagents in parallel (one per domain, including the conditional UI-domain subagent for UI PRs).
3. Each sub-subagent uses the `code-reviewing` skill's engine as the only review engine.
4. Scope: all files changed in the PR (`gh pr diff <number> --name-only`).
5. Compile and deduplicate findings from all reviewers.
6. **CRITICAL: do NOT post anything to GitHub and do NOT submit a review. Return the findings in the response only.**

**Step 8 — Assess review findings** when Step 7 ran, using the same triage as Step 3 (VALID-FIX / VALID-WONTFIX / INVALID). If there are VALID-FIX items, resume the Step 4 developer session to fix them, then re-run the project's check and test commands for the affected packages.

**Step 9 — Commit and push.** Step 5's gate is mandatory before push. While CI runs, check main drift — see `polling-monitoring`'s "Main drift while polling CI" section.

```bash
git add -A
git diff --cached --exit-code || git commit -m "fix: address review feedback"
git push
```

Review staged files with `git diff --cached --stat` before committing — unstage unexpected files (build artifacts, `.env`, credentials) with `git reset HEAD <file>`. The `--exit-code` guard skips the commit when nothing changed (all comments were INVALID/STALE). Fix and retry on pre-push hook failure.

**Step 10 — Re-request reviews.** For human reviewers who left CHANGES_REQUESTED and had at least one VALID-FIX item addressed: `gh api repos/{owner}/{repo}/pulls/<number>/requested_reviewers -f reviewers[]="<login>"`. Skip re-requesting from reviewers whose only open items are VALID-WONTFIX — reply with a rationale instead. For an automated bot review (e.g. Claude): dismiss the CHANGES_REQUESTED review (`gh api -X PUT .../reviews/<review_id>/dismissals -f message="Fixes applied"`), then re-trigger by adding the `review` label (`gh pr edit <number> --add-label "review"`).

**Step 11 — Report** using headers `## PR #<number> Fix Report`, `**Fixed (<count>):**`, `**Won't fix (<count>):**`, `**Discarded (<count>):**`, `**Remaining blockers:**` — each followed by a one-liner bullet per item; each Won't fix bullet also carries a suggested follow-up ticket (title + one-line why), per SKILL.md's finding-reporting hard rule. Omit sections with zero items.

## Pagination and Orchestration Rules

**CRITICAL: always use `--paginate` or `?per_page=100`** on any `gh api` call returning PR comments or reviews — the REST API defaults to 30 items per page and multi-round PRs can have 100+. For GraphQL, request enough items explicitly and paginate with `pageInfo { hasNextPage endCursor }` until complete.

**NEVER delegate this workflow to a subagent.** The agent that loaded this skill orchestrates the loop; delegate only code fixes (`developer` subagent) and review passes (`reviewer` subagent). Never tell a subagent to "fix and merge the PR" — every triage decision and merge action stays with the orchestrator.

**Maximum 3 review-fix rounds.** After 3: STOP. Do NOT merge. Do NOT dismiss the review. Report remaining unresolved findings to the user and wait for explicit instruction.

DOs: resolve every addressed thread (mandatory); reply to threads handled differently than requested; run the project's scoped check and test commands before every push; assess comments before fixing; record rule slug/text/review id/head SHA/provenance/fix shape before fixing; use subagents for fixing and reviewing; triage CI failures before review comments; verify subagent output before proceeding; paginate every `gh api` call that returns comments or reviews.

DON'Ts: leave addressed threads unresolved; reply "Fixed in \<commit\>" instead of resolving; resolve WONTFIX threads (reply and leave unresolved — silently resolving causes infinite review loops); delete a VALID-FIX bot comment with no matching code change; broaden a fix beyond the approved fix shape (report UNFIXABLE instead); post code review findings to GitHub; merge the PR (only prepare it); fix architectural concerns without user approval; reply to INVALID bot comments explaining why they're wrong; re-trigger review after 3 rounds; treat an APPROVED review as "nothing to triage"; delegate the whole workflow to a subagent.

## Review-Fix Polish Loop

A separate, lighter-weight pattern for **polishing implementation quality** — with or without an open PR — via a strict reviewer/fixer subagent loop.

**Orchestrator protocol.** You do NOT review or fix code yourself — spawn subagents for all review and fix work. Reviewer subagents are always fresh (never reuse `task_id`). The fixer is spawned fresh in round 1, then resumed via `task_id` in later rounds. The reviewer is READ-ONLY — a PASS can only come from a reviewer finding zero issues, never from one that "fixed things itself." Every reviewer runs the SAME full-scope review with the SAME criteria; round 2+ reviewers do NOT receive previous findings, they review from scratch.

**Before starting:** check `git status`. Only staged/recently committed changes from current work → commit automatically with a descriptive message. Mixed, unrelated, or ambiguous changes → ask the user to commit first, then re-invoke. Clean working tree with recent commits → proceed. Identify the baseline the reviewer should examine. Gather project review criteria: the `code-reviewing` skill, `AGENTS.md`/`CLAUDE.md` at project root, and the project's automated check commands.

**Spawn protocol:** PR mode (a PR number exists) and worktree mode (no PR yet) both use parallel domain subagents per the `code-reviewing` skill's orchestration workflow, compiled and deduplicated afterward. Choose one mode upfront and keep it for every round — do not mix modes mid-loop.

**The loop** (max 2 rounds, non-negotiable):

```
round = 0; max_rounds = 2
LOOP:
  round += 1
  STEP 1 — REVIEW (fresh, read-only subagent, identical prompt every round + growing
    "Deferred exclusions" list of already-triaged-out items):
    Reviewer runs automated checks, reads changed files, reports STATUS: PASS or FAIL
    with numbered findings. Never edits or fixes.
  STEP 2 — TRIAGE (orchestrator, not a subagent):
    PASS (zero findings) → exit, report success.
    FAIL → classify each finding: FIX (legitimate, send to fixer) / REJECT (contradicts
    stated intent, spec, prior accepted fix, or project convention — log reason) /
    DEFER (valid but out of scope, needs a user decision, or previously reported
    UNFIXABLE by the fixer — log reason).
    All REJECT/DEFER → exit, report as effective PASS with notes.
    round == max_rounds → exit, report remaining FIX items plus accumulated REJECT/DEFER.
    Else → continue to Step 3 with only FIX items.
  STEP 3 — FIX (round 1: fresh fixer subagent, save task_id; round 2+: resume via
    task_id). Fixer receives ONLY FIX-triaged findings — REJECT/DEFER are withheld.
  STEP 4 — EVALUATE: read the fixer's VERIFY line. Fail → re-prompt via task_id up to
    2 times, then stop and report the exact failing output — never advance with
    broken code. Pass → commit (`git add -A && git commit`) in exactly one commit,
    then (worktree mode) run `code-reviewing`'s `<skill-dir>/engine/review-cli
    round-complete --branch "<label>"` to record the round marker BEFORE the next
    round's `<skill-dir>/engine/review-cli plan --branch "<label>" ...` call (omit
    `--base` — the CLI defaults it to the recorded marker, per ORCHESTRATION.md's
    Worktree-Mode Round Policy). Committing in one commit first matters because a
    plan snapshots the diff at execution time — committing before re-planning
    prevents round-2 reviewers re-flagging already-fixed items. Go to Step 1 with a
    fresh reviewer.
```

**Triage criteria, in order:** (a) contradicts an explicit user/spec/requirements decision → REJECT; (b) undoes a fix applied in a previous round and automated checks still pass → REJECT (flip-flop); (c) previously reported UNFIXABLE by the fixer → DEFER; (d) style/preference conflicting with established project conventions → REJECT; (e) genuine bug/correctness/convention violation → FIX; (f) valid but needs user input or an architectural change → DEFER.
Maintain an internal (never-written-to-file) triage ledger across rounds to detect flip-flops and preserve accumulated REJECT/DEFER items for the final report.

**Rules:** never review or fix code yourself; reviewer always fresh, fixer always resumed (except round 1); reviewer is strictly read-only; fixer stays in scope (no drive-by refactoring); structured output only — free-form prose is treated as FAIL and re-prompted once, then escalated; 2 rounds max, non-negotiable; never short-circuit — a FAIL with FIX items always gets a fixer, a fixer always gets a fresh reviewer after; triage is mandatory, never forward findings blindly; fixer never sees REJECT/DEFER items; flip-flop detection rejects oscillation; the fixer's mandatory verify gate blocks advancing with broken code; the spawn mode is fixed for the whole loop.
Report on PASS: "Review-fix loop completed in {N} round(s). All checks pass." plus any accumulated REJECT/DEFER items. On max-rounds: list remaining FIX items plus all REJECT/DEFER across rounds, and note they may need manual attention. On fixer UNFIXABLE items: surface them explicitly as needing user input.

## Polish Loop Prompt Templates

Default `subagent_type` is `"reviewer"` for reviewers and `"developer"` for fixers, or `"coding"` for both if the project does not define specialized subagent types. Save the fixer's returned `task_id` after round 1 and pass it in every later round to resume the same session.

**Reviewer prompt (identical every round — only the Deferred exclusions list grows):**

```
You are a code reviewer. You MUST NOT edit, write, or modify any files. You are read-only.
Your job is to find issues. You do not fix them.

## Scope
{scope_description from user's command argument}

## What to review
{changed files list, commit range, or "working copy changes" — orchestrator decides}

## Review criteria

### Automated checks
Run these commands and report any failures as findings:
{automated check commands, or "No automated checks found — skip this section"}

### Project review standards
{contents of the code-reviewing skill, or "No code-reviewing skill found"}

### Project conventions
{relevant sections from AGENTS.md/CLAUDE.md, or "No project conventions file found — use general clean code principles"}

### Spec requirements
{any requirements context the orchestrator has from the conversation}

## Deferred exclusions (do NOT re-flag these)
The following items have already been reviewed and triaged as out of scope for this loop.
Do not report them as findings. If you independently identify the same issue, skip it.
{deferred_exclusions list, or "None — no items deferred yet"}

Format used by orchestrator to populate this section:
  - [{file}:{line-or-area}] {one-line description of the deferred concern} -- REASON: {why deferred}

## Your task
1. Run automated checks. Report failures as findings.
2. Read the changed files. Do NOT edit them.
3. Review against all criteria above.
4. Skip any finding that matches an item in the Deferred exclusions list above.
5. Report every other issue found. Be specific: file path, line number, what is wrong, why.
6. Do NOT edit any files. Do NOT fix anything. Report only.

## Required output format

STATUS: PASS
Summary: {one sentence — all criteria met, no issues found}

OR

STATUS: FAIL
Findings:
1. [{file}:{line}] {description of issue and why it is wrong}
2. [{file}:{line}] {description}
...
Summary: {count} issues found. {one sentence overview}
```

**Fixer prompt template.** Round 1 includes the Scope and Project conventions sections and step 1 below. Round 2+ omits both sections and step 1 — keep everything else identical, and prefix with "New findings from round {N}. Fix every one of them. Same rules as before."

```
You are a code fixer. Fix the specific issues listed below. Nothing else.

## Scope (round 1 only)
{scope_description}

## Project conventions (round 1 only)
{relevant sections from AGENTS.md/CLAUDE.md, or "Use general clean code principles"}

## Issues to fix
These were found by a code reviewer. Fix every one of them.
{numbered findings from reviewer — paste the full findings list}

## Your task
1. Read the project's AGENTS.md or CLAUDE.md if available (round 1 only).
2. Fix each issue. Reference by finding number.
3. MANDATORY VERIFY GATE — after ALL fixes are applied, run the verification commands:
   - {automated check commands, or "No automated checks — read the changed code to verify correctness"}
   - If verification fails (type errors, test failures, lint errors), fix the failures
     before reporting. Do NOT commit or report FIXES if verification is failing.
   - If you cannot make verification pass, report the block in UNFIXABLE with the
     exact error output.
4. Do NOT fix things not listed above. Do NOT refactor, rename, reformat, or clean up nearby code unless required by a listed finding or by verification failures caused by your fix.
5. If a finding cannot be fixed (needs user decision, architectural change, or is out of scope), explain why in the UNFIXABLE section.

## Required output format

FIXES:
1. [Finding #{n}] {what you changed and where}
...
UNFIXABLE:
- [Finding #{n}] {why this cannot be fixed}

(If all findings were fixed, omit the UNFIXABLE section.)

VERIFY: {pass | fail — one sentence with the command run and outcome}

Summary: {one sentence — what was fixed, what was not}
```
