---
name: managing-pull-requests
description: Use when naming or creating a branch, opening a pull request (including a spec PR/PR1, an implementation PR/PR2, or a draft PR), writing or updating a PR title or description, fixing a PR after review feedback or a CI failure, resolving GitHub review threads, dismissing or re-triggering a bot review, running a review-fix polish loop, or merging, squashing, shipping, landing, or closing out a PR. Also use when diagnosing merge blockers such as CONFLICTING, BLOCKED, BEHIND, DIRTY, or UNSTABLE merge state, or a CHANGES_REQUESTED review.
compatibility: opencode
metadata:
  schemaVersion: "1"
  version: "2.0.1"
  stability: stable
  category: workflow
  appliesTo: any
  requires: code-reviewing
---

Guide for the full PR lifecycle: branch, open, review-fix, merge. Contains rules across 3 topics. `code-reviewing` is a separate skill — load it for the actual review engine; this skill only covers triaging and applying its findings. Waiting on CI, a deployment, or a review run is a separate skill too — load `polling-monitoring`.

## Topics

| # | Topic | Covers | Reference |
|---|-------|--------|-----------|
| 1 | Branching and opening | Branch naming, PR title/description format, draft vs ready, PR type rules, updating an existing PR | [BRANCHING-AND-OPENING.md](BRANCHING-AND-OPENING.md) |
| 2 | Review and fix | Resolving review threads, CI triage, the fixing-PR workflow, the review-fix polish loop | [REVIEW-AND-FIX.md](REVIEW-AND-FIX.md) |
| 3 | Merging | Merge-blocker diagnosis, squash-merge steps, linked-ticket status update, worktree cleanup | [MERGING.md](MERGING.md) |

## Quick Checklist

Copy and track for a full PR lifecycle:

```
- [ ] Branch named CU-<id>/<type>/<slug> (BRANCHING-AND-OPENING.md)
- [ ] The project's check and test commands both pass before opening
- [ ] PR opened with a real title/description, ready unless draft explicitly requested
- [ ] Reviews + CI triaged, VALID-FIX items fixed, threads resolved (REVIEW-AND-FIX.md)
- [ ] The project's check and test commands both green before every push
- [ ] Merge gate checked: mergeable=MERGEABLE, mergeStateStatus=CLEAN, reviewDecision=APPROVED, all checks green (MERGING.md)
- [ ] Squash-merge with --delete-branch
- [ ] Linked ticket status set manually (nothing does this automatically)
- [ ] Worktree removed only if git status is clean
```

## Hard Rules

- NEVER use placeholder PR titles ("Update feature") or auto-generated branch-name titles.
- NEVER skip the project's check command (format, lint, typecheck) AND its test command (unit tests) before opening a new PR or before any push, scoped to the touched packages (e.g. `task check:pkg -- <pkg>` and `task test:pkg -- <pkg>` in projects using the agentkit taskfile recipe). Run them as two separate required commands: a check command that runs no tests is not a substitute for the test command.
- NEVER create stacked implementation PRs — merge the current one before opening the next dependent one.
- ALWAYS squash-merge with `--delete-branch`. Never merge-commit, rebase-merge, or merge a draft/fork PR.
- ALWAYS resolve or reply to every review thread before considering a PR merge-ready (REVIEW-AND-FIX.md Step 6).
- ALWAYS close every finding (review comment, CI observation, caveat, out-of-scope issue) one of two ways: fix it in the same PR when the fix is minimal and obvious, or report it to the user in chat with a suggested follow-up ticket (title + one-line why — never auto-created). PRs are read only by agents, never by people — a finding left only in a PR description, review reply, or thread disappears unnoticed.
- ALWAYS update the linked ticket's status manually after merge — nothing does this automatically (MERGING.md).
- Follow `polling-monitoring`'s bounded check/report/sleep/check pattern before any wait loop on CI, a deployment, or a review run — never `watch`, `tail -f`, or shell `while` loops.
- Apply `humanizing-ai-text`'s rules to every PR title, description, review reply, and status update you write — no em dashes, no chatbot filler, no sycophantic openings.

## Related, Separate Skills

- `code-reviewing` — the actual review engine, rule corpus, and subagent orchestration. Load it for the review pass itself.
- `polling-monitoring` — the bounded check/report/sleep/check pattern for CI checks, deployments, and any other async status this skill waits on.
- `humanizing-ai-text` — the human-voice rules for PR titles, descriptions, review replies, and status updates.
- `managing-openspec` — decides whether a change needs a spec PR (PR1) + implementation PR (PR2) or a lightweight single-PR path; this skill only covers the PR mechanics once that decision is made.
