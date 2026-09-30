# Merging

Merge-blocker diagnosis, squash-merge steps, linked-ticket status update, and worktree cleanup.

## Contents

- Hard Rules
- Workflow Checklist
- Fetching PR State and Triage
- Review — Wait or Trigger
- Final Pre-Merge Verification
- Squash-Merge
- Update the Linked Ticket
- Worktree Cleanup

## Hard Rules

- ALWAYS squash-merge. Never merge-commit, never rebase-merge.
- Never merge a draft PR or a fork PR (an automated review bot typically skips forks — no approval possible).
- Never bypass `mergeable: MERGEABLE` + `mergeStateStatus: CLEAN`, or merge without `reviewDecision: APPROVED`.
- Never merge without reading the review body AND inline comments AND conversation comments, even when `reviewDecision: APPROVED` — approved-with-comments is a common verdict.
- Never merge while any required check is `pending`, `in_progress`, `queued`, or `failure`.
- Never write, override, or fabricate a commit status via the GitHub Statuses API to force mergeability. If a stale or non-required check leaves `UNSTABLE`, confirm via branch protection that all REQUIRED checks are green, then merge on that basis — do not edit statuses.
- Never maintain stacked implementation PRs — merge the current one before opening the next dependent one.
- Delete the branch on merge. Use ephemeral, short-lived branches.
- ALWAYS run the project's check and test commands locally before pushing any fix, and address failing checks or requested changes before returning to the merge gate.

## Workflow Checklist

```
- [ ] Step 1: Load `polling-monitoring` before any wait loop
- [ ] Step 2: Fetch PR state (mergeability, review decision, all checks)
- [ ] Step 3: Triage non-green state (if any)
- [ ] Step 4: Wait for or trigger a re-review (if needed)
- [ ] Step 5: Final pre-merge verification
- [ ] Step 5.5: Read review body + inline + conversation comments, triage findings
- [ ] Step 6: Squash-merge with --delete-branch
- [ ] Step 7: Confirm merge state
- [ ] Step 7.5: Update the linked ticket's status manually (see Update the Linked Ticket)
- [ ] Step 8: Clean up worktree (only if clean)
```

Execute in order — do NOT skip Step 5 even if Step 2 looked green; state can change while waiting.

## Fetching PR State and Triage

```bash
gh pr view <PR> --repo <owner>/<repo> \
  --json mergeable,mergeStateStatus,reviewDecision,isDraft,headRefOid,labels,state,statusCheckRollup \
  --jq '{
    state, isDraft,
    mergeable, mergeStateStatus, reviewDecision,
    headSha: .headRefOid,
    labels: [.labels[].name],
    checks: [.statusCheckRollup[] | {name, status, conclusion}]
  }'
```

Required reads:

- `state` must be `OPEN`. If `MERGED` or `CLOSED`, stop.
- `isDraft` must be `false`. If `true`, ask the user; do not silently mark ready.
- `mergeable` must be `MERGEABLE`. `CONFLICTING` needs Step 3. `UNKNOWN` means GitHub is still calculating mergeability — wait 5-10s and re-fetch.
- `mergeStateStatus` must be `CLEAN`. Other values: `BLOCKED` (failing checks/reviews), `BEHIND` (head ref out of date), `DIRTY` (merge commit cannot be cleanly created), `UNSTABLE` (mergeable but a non-required check is failing — verify before merging), `HAS_HOOKS` (mergeable with passing checks and pre-receive hooks — safe to merge), `DRAFT` (PR is a draft), `UNKNOWN` (state still being computed — re-fetch).

When `mergeable: CONFLICTING`, GitHub does NOT run workflows on new pushes to that branch — the PR sits with no CI signal until conflicts are resolved. ALWAYS resolve conflicts FIRST, THEN push, THEN expect CI to run. Draft PRs also skip CI entirely (most CI setups gate on `draft != true`) — mark the PR ready first if you need CI on a draft.

`reviewDecision` must be `APPROVED`. `""` / `null` / `COMMENTED` are NOT approved — re-trigger review and wait. `CHANGES_REQUESTED` means address feedback first. `REVIEW_REQUIRED` means it has not been reviewed yet.

Inspect every entry in `statusCheckRollup`, not just the headline review status. `conclusion`: `SUCCESS`, `SKIPPED`, `NEUTRAL` are passing; `FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `STARTUP_FAILURE`, `STALE` are failing. `status`: `COMPLETED` is required; `IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING` mean wait. Determine the actual required checks dynamically from the repository's branch protection rules (`gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.contexts'`) — do not assume a fixed job list. Some jobs `SKIP` for spec-only PRs (no app/package diff); that is a pass, not a failure.

| State | Action |
|---|---|
| `mergeStateStatus: CONFLICTING` / `mergeable: CONFLICTING` | Merge the base branch into the PR branch in a worktree, resolve conflicts, run the project's check and test commands, push. Do NOT use the GitHub web "Resolve conflicts" UI. |
| `mergeStateStatus: BEHIND` | Merge the base branch into the PR branch and push. Required when branch protection enforces "up to date with base branch". |
| `mergeStateStatus: BLOCKED` with failing checks | Fix the failing checks — return to SKILL.md's Topics table and load the Review and fix topic (Step 2b). |
| `mergeStateStatus: UNSTABLE` | One non-required check is failing. Inspect `statusCheckRollup` to identify it; if it's a known infra flake, re-run that single job (`gh run rerun <run-id> --failed`). Otherwise confirm via branch protection that the failing check is not required — never edit its status to force `CLEAN`. |
| `reviewDecision: CHANGES_REQUESTED` | Address every requested change and resolve threads before merging — return to SKILL.md's Topics table and load the Review and fix topic. Do NOT merge. |
| `reviewDecision: REVIEW_REQUIRED` | Go to Review — Wait or Trigger below. |

## Review — Wait or Trigger

A configured automated review (e.g. "Claude PR Code Review") fires on PR `opened`, `reopened`, or `ready_for_review` — running in parallel with CI — and on any re-review triggered by adding the `review` label. Forks and drafts are silently skipped. After a successful review the workflow typically adds a `bot-reviewed` label. A new push does NOT auto-trigger another review — add the `review` label to re-review. If the status reads `Skipped — already reviewed`, treat it as a pass.

Manually trigger with `gh pr edit <PR> --add-label review --repo <owner>/<repo>` when: a new HEAD needs re-review (pushes do not auto-trigger); `reviewDecision: REVIEW_REQUIRED` with no run for the current head SHA (e.g. the initial open-event run errored on infra); or the previous run failed for upstream reasons (rate limit, timeout, runner crash). Do NOT re-trigger when the status is `Skipped — already reviewed`.

If the label is already set and no new run started, the previous run never picked it up — toggle it off then back on with a short sleep between:

```bash
gh pr edit <PR> --remove-label review --repo <owner>/<repo>
sleep 5
gh pr edit <PR> --add-label review --repo <owner>/<repo>
```

If resolved bot comments were deleted while a review run was already in flight, that run started before the deletion and will still see and re-flag them — cancel the in-progress run (find its id filtering by `head_branch`, workflow name, and status `in_progress`/`queued`) and re-trigger via the label toggle above.

Poll using `polling-monitoring`'s check/report/sleep/check pattern, sleeping 30s between checks. On EVERY iteration also refresh `mergeable`, `mergeStateStatus`, and `reviewDecision` — any of these can regress mid-wait (main moving → `BEHIND`/`CONFLICTING`; a new review round → `CHANGES_REQUESTED`). Also check main drift every other iteration per `polling-monitoring`'s guidance. If `mergeable` flips to `CONFLICTING` or `mergeStateStatus` flips to `BEHIND`, abort polling and return to the triage table above. If `reviewDecision` flips to `CHANGES_REQUESTED`, abort polling and do NOT merge.

Terminal state is `status: completed`. On `conclusion: failure`, **rate-limit handling order:** read the commit-status description first, fall back to the job log only when it's uninformative.

1. Read the review check's commit-status description (`gh pr checks <PR>`) if the project's review workflow publishes a rate-limit status description (e.g. `Rate limited, resets <time>` instead of a generic `Review failed`). It is cheaper and more precise than log digging.
2. Fall back to the job log for a rate-limit error (`gh run view --job <id> --log-failed | rg -i 'limit|rate|exit code'`) only when the description is generic or absent.
3. On a rate-limit signal with a stated reset time, do NOT immediately retry — sleep until the reset time plus 2 minutes, then re-trigger. Same applies if a fallback model also failed.

If the review job checks out review-engine scripts or skill files from the PR branch and these drifted from the base branch, the review may silently skip or error — merge the base branch into the PR branch and re-trigger. Fork PRs cannot be merged via this skill (the review workflow is gated on the head repo matching the base repo) — refuse and explain to the user.

## Final Pre-Merge Verification

Repeat the state fetch once more. Confirm `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`, `reviewDecision: APPROVED`, and all checks `SUCCESS`/`SKIPPED` with `status: COMPLETED`. Then verify no review run is still active on the branch (catches a manual re-trigger overlapping with an auto-triggered run):

```bash
gh run list --repo <owner>/<repo> --branch <branch> --workflow "<review-workflow-name>" \
  --limit 10 --json status \
  --jq '[.[] | select(.status == "in_progress" or .status == "queued" or .status == "pending")] | length'
```

Must return `0`. If anything regressed, go back to the relevant step — do NOT proceed to merge on stale data.

**Step 5.5.** Fetch every review comment and thread, classify each as VALID-FIX / VALID-WONTFIX / INVALID / STALE, and resolve or reply accordingly before merging — an unresolved thread means the PR is not merge-ready. Report the triage to the user, per SKILL.md's finding-reporting hard rule:

```
Findings triaged:
- [FIX] <summary> -- <where addressed>
- [WONTFIX] <summary> -- <reasoning>
- [DEFER] <summary> -- <suggested follow-up ticket: title + one-line why>
```

Do NOT re-trigger review when fixes only address its own comments — the APPROVED decision stands.

## Squash-Merge

```bash
gh pr merge <PR> --repo <owner>/<repo> --squash --delete-branch
```

`--squash` is mandatory — never substitute `--merge` or `--rebase`. `--delete-branch` removes the remote branch; the local branch (if in a worktree) is deleted in Step 8. Do NOT pass `--admin` to bypass branch protection — if the merge fails on protection rules, the PR is not actually ready; return to Step 2. Do NOT pass `--auto`.

If the command fails, capture the error verbatim before retrying:

| Error | Cause | Fix |
|---|---|---|
| `Pull request is not mergeable` | `mergeable` went from `MERGEABLE` to `CONFLICTING` between Step 5 and Step 6 (base branch moved) | Resolve conflicts per the triage table above |
| `At least 1 approving review is required` | Branch protection requires a human reviewer too | Ask user; do not bypass |
| `Required status check "<name>" is expected` | A required check is missing from the head SHA | Push a no-op commit or trigger the missing workflow |

Confirm the merge:

```bash
gh pr view <PR> --repo <owner>/<repo> --json state,mergedAt,mergeCommit \
  --jq '{state, mergedAt, mergeCommitSha: .mergeCommit.oid}'
```

Required: `state: MERGED`. Report the squash commit SHA to the user. If follow-up work is waiting on this merge, open the next PR only after this confirmation succeeds — never keep a dependent PR prepared ahead of time.

## Update the Linked Ticket

Extract the ticket id from the branch name or PR title. Skip if none. Nothing moves the ticket automatically — set its status yourself, using whatever ticket tracker this project uses.

Only the closer PR — the one that completes the ticket (the final implementation slice, a standalone `feat`, or a `fix`) — moves the ticket to the tracker's "merged"/"done" state. `spec` PRs, non-final implementation slices, and `chore`/`refactor`/`docs`/`test` PRs do not change ticket status; optionally comment that a supporting PR merged.

Later, move the ticket to a "deployed"/"ready to test" state only once its merge commit is an ancestor of the last production release — never revert a ticket to an earlier status just because GitHub shows the PR as `MERGED`; merged is not the same as deployed. Check ancestry generically:

```bash
git merge-base --is-ancestor <merge-commit-sha> <last-production-release-tag>
```

The exact status names ("merged", "ready to test", "deployed", etc.) come from the project's own ticket-workflow docs — this skill owns the mechanism (who moves the ticket, and when), not the status vocabulary.

Only touch the ticket linked to this PR — never move tickets outside the current task.

### Stakeholder delivery update (optional)

When the ticket has a non-technical client or stakeholder, draft a short update describing what they can now see or do — never PR links, commit messages, or code — using the `writing-client-facing-content` and `humanizing-ai-text` skills. Post it only with explicit user approval in the current turn. The ticket-status write above needs its own separate approval too, unless the project's `AGENTS.md` pre-approves that specific write.

## Worktree Cleanup

If the PR work happened in a worktree (`.worktrees/<name>/`), check for uncommitted changes BEFORE removing it — lost work cannot be recovered from git after `worktree remove`.

```bash
git -C .worktrees/<name> status --porcelain
```

| `git status --porcelain` output | Action |
|---|---|
| Empty (clean) | Remove the worktree: `git worktree remove .worktrees/<name>`. |
| Non-empty (uncommitted changes, untracked files, staged-but-uncommitted) | DO NOT remove. Flag the exact `git status` output to the user and ask whether to commit, stash, or discard. |

Never pass `--force` to `worktree remove` to override uncommitted changes — that silently destroys the work. Only use `--force` if the user explicitly says to discard everything and remove.

## DOs and DON'Ts

- DO load `polling-monitoring` before any wait loop.
- DO inspect every entry in `statusCheckRollup`, not just the headline review status row.
- DO verify state IMMEDIATELY before calling `gh pr merge` (Step 5).
- DO use `--squash --delete-branch` exactly.
- DO refuse to merge fork PRs (an automated reviewer cannot approve them).
- DO check for upstream rate-limit failures before re-triggering a review.
- DON'T merge on `mergeStateStatus: UNSTABLE` without first identifying which non-required check failed.
- DON'T write, override, or fabricate a commit status via the GitHub Statuses API to force `UNSTABLE` into `CLEAN` — confirm the failing check is non-required via branch protection instead.
- DON'T pass `--admin` to bypass branch protection.
- DON'T use the GitHub web "Resolve conflicts" editor — resolve locally with the full verification pipeline.
- DON'T re-trigger a review immediately after a rate-limit failure.
- DON'T stream `gh run watch` or use shell loops to poll.
- DON'T merge a PR with `reviewDecision: CHANGES_REQUESTED` even if all CI checks are green.
- DON'T wait on CI for a `CONFLICTING` PR — workflows will not run until conflicts are resolved.
- DON'T wait on CI for a draft PR — mark it ready for review first.
- DON'T treat a long wait as quiet — re-check `mergeable` and `mergeStateStatus` on every iteration; the base branch moving silently sends the PR to `BEHIND` or `CONFLICTING`.
- DON'T remove a worktree without checking `git status --porcelain` first.
- DON'T pass `--force` to `git worktree remove` unless the user explicitly authorizes discarding uncommitted work.
