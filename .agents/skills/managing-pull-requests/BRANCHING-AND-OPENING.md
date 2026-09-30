# Branching and Opening

Branch naming, PR title/description format, and the PR-opening workflow.

## Contents

- Branch Name Format
- Ticket Extraction
- Title Format
- Description Format
- Writing Rules and Anti-Patterns
- Opening Workflow
- Updating an Existing PR
- PR Type Rules

## Branch Name Format

```
CU-<clickup-task-id>/<type>/<short-description>
```

ClickUp ID comes first so branches for the same task group together in sorted listings.

```
CU-86c8zdwuk/spec/ci-cd-pipeline       — spec-only PR (PR1)
CU-86c8zdwuk/impl/ci-cd-pipeline       — implementation PR (PR2)
CU-86c8zc483/feat/auth-session         — new feature
CU-86c8zdy13/fix/media-list-sort       — bugfix
CU-86c8zk2yt/chore/update-deps         — tooling, deps, config
CU-86c8zhr32/refactor/extract-service  — refactoring
```

| Type | When to use |
|---|---|
| `spec` | PR1 in the two-PR workflow (OpenSpec artifacts only) |
| `impl` | PR2 in the two-PR workflow (implementation) |
| `feat` | New feature or lightweight spec-linked single PR |
| `fix` | Bug fix |
| `chore` | Tooling, dependencies, CI config, non-feature changes |
| `refactor` | Code restructuring with no behavior change |
| `docs` | Documentation-only changes |
| `test` | Test-only changes |

Rules:

- **Always include `CU-<id>`** — ClickUp auto-detects `CU-{taskId}` from branch names and links PRs, commits, and branches to the task. No manual linking needed. You can also include `CU-<taskId>` in PR titles and commit messages for additional linkage points.
- **Short description in kebab-case** — 2-4 words, matches the OpenSpec change name when applicable.
- **`spec/` and `impl/` branches for the same task share the same CU prefix and description** — only the type segment differs. `impl/` is created stacked on `spec/`; after the spec PR merges, rebase `impl/` onto `main`.
- **If no ClickUp task exists** (rare), omit the `CU-<id>/` prefix: `chore/fix-typo-in-readme`.

```bash
# Spec-only PR (PR1)
git checkout -b CU-<taskId>/spec/<change-name> main
# Implementation PR (PR2), stacked on spec branch
git checkout -b CU-<taskId>/impl/<change-name> CU-<taskId>/spec/<change-name>
# Single-PR features or lightweight spec-linked changes
git checkout -b CU-<taskId>/feat/<short-description> main
```

## Ticket Extraction

Branch names follow `CU-<taskId>/<type>/<description>`. Extract from `headRefName` with the pattern `CU-[a-zA-Z0-9]+`. Format as `[CU-<taskId>]` in the PR title; omit if not found. The extracted ID also builds the ClickUp link used in the description body.

## Title Format

```
<type>: [CU-<taskId>] <concise summary>
```

- With task: `feat: [CU-86c8zdwuk] Add user preferences`. Without: `chore: Fix typo in readme`.
- Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `spec`. Breaking change: add `!` after the type.
- Max 72 characters total. `spec` type is for PR1 in the two-PR workflow.

## Description Format

```
ClickUp: https://app.clickup.com/t/<taskId>

## Why
<1-2 sentences: what problem this solves or what need triggered it>

## What changed
- <bullet 1: high-level change, not file names>
- <bullet 2>

## Caveats
- <breaking changes, migration notes, non-obvious decisions>
- <or omit this section entirely if none>
```

- ClickUp link is always the first line when a task exists (omit for no-task chore PRs).
- "Why" is mandatory — answer what breaks or is missing without this PR.
- "What changed" uses bullets describing behavior, not file paths or code structure. Max 5 bullets.
- "Caveats" is optional — only breaking changes, migration steps, or non-obvious decisions reviewers need to know. A caveat that still needs a decision or follow-up also gets reported to the user per SKILL.md's finding-reporting hard rule — the PR description alone doesn't satisfy it.
- Omit empty sections. A self-explanatory PR can have just the ClickUp link + 1 sentence.

## Writing Rules and Anti-Patterns

- No emojis. Use the standard sections only (Why / What changed / Caveats) — no custom headers.
- NEVER list files, classes, or code structure — reviewers see the diff.
- NEVER mention counts ("6 event types", "26 tests", "5 factory constructors").
- NEVER restate code — don't describe what classes contain or what enums have.
- Sound human: explain WHY and WHAT PROBLEM, not implementation. Apply `humanizing-ai-text`'s rules — no em dashes, unsupported hedging, or chatbot sign-offs. Run a final em-dash sweep on the title and body before `gh pr create`/`gh pr edit` — the humanizing skill is applied per-output and can miss PR metadata.
- Use imperative mood ("Add feature" not "Added feature"). Be specific in titles: "Fix null check in UserRepository" beats "Fix bug".
- No filler — if there's nothing important to say, the description can be one sentence.

**Terrible** (restates code, lists files, counts things):

```
New files:
- core/lib/src/live_event/live_event_type.dart - Enum with 6 event types and hex codes

Testing: 26 unit tests added and passing.
```

**Good** (closer PR):

```
ClickUp: https://app.clickup.com/t/86c8def34

## Why
Users lost theme preferences on every page refresh.
```

**Good** (spec PR — PR1):

```
ClickUp: https://app.clickup.com/t/86c8abc12

## Why
Defines the data model and state transitions for the live event integration before implementation begins.

## What changed
- OpenSpec change `live-event-integration` with proposal, design, tasks
- REQ-5.1 added to docs/requirements
```

## Opening Workflow

Copy and track:

```
- [ ] If creating a new PR, run the project's check command AND test command for the touched packages; stop and report on failure
- [ ] Confirm the current branch is not `main`/`master`
- [ ] Confirm there is no older open implementation PR this one would depend on — never stack PRs
- [ ] Confirm the branch is pushed (`git push -u origin HEAD` if not)
- [ ] Generate title and description per the formats above
- [ ] Apply the writing rules; run the em-dash sweep
- [ ] Decide draft vs ready (ready by default)
- [ ] Run `gh pr create` or `gh pr ready`
- [ ] Verify with `gh pr view --json url,title,isDraft,body`
```

Skip the check and test commands only when editing metadata on an existing PR. Before opening a new implementation PR, confirm the previous implementation PR is already merged — if the next change depends on code still under review, stop and ask whether to wait for merge or reduce scope to an independent diff.

Default to ready for review. Open draft only when the user explicitly asks (e.g. "open as draft", "draft PR"):

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)" --draft
# or ready
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
# promote an existing draft
gh pr ready
```

Post-create verification: `gh pr view --json url,title,isDraft,body,headRefName,baseRefName` — confirm `url` exists, `title` matches, `isDraft` matches intent, `body` has expected headers, `headRefName`/`baseRefName` match intent. Fix with `gh pr edit` on any mismatch.

## Updating an Existing PR

Retitling or rewriting the description of a PR that already exists — never re-run the full opening workflow for this.

1. Extract the PR identifier from the user's message (URL, number, or branch name).
2. Fetch current metadata: `gh pr view <pr> --json title,body,comments,headRefName`.
3. Extract the ClickUp task ID from the branch name, comments, or the existing title (see Ticket Extraction above).
4. Fetch the diff: `gh pr diff <pr>` and file list: `gh pr diff <pr> --name-only`.
5. Generate the new title and description per the formats above.
6. Apply immediately — never just show the proposed metadata:
   ```bash
   gh pr edit <pr> --title "<new-title>"
   gh pr edit <pr> --body "$(cat <<'EOF'
   <new-body>
   EOF
   )"
   ```
7. Confirm with `gh pr view <pr> --json title,body` and report what changed.

The project's check and test commands are not required for a metadata-only update (no code changed).

## PR Type Rules

**Spec PR (PR1)**: type `spec`. No application/implementation code changes. No migrations or infrastructure changes. Include only OpenSpec artifacts (`openspec/changes/<change-id>/`), requirement docs, and feature docs. Never closes the ticket — the implementation PR does.

**Implementation PR (PR2)**: type `impl`. References the approved OpenSpec change ID from PR1. All tests pass before opening. Open only after the previous implementation PR in the sequence is merged — never create `pr2a`/`pr2b` dependency chains. Only the FINAL slice PR closes the ticket; earlier slice PRs don't.

**Ad-hoc (feat, fix, chore, etc.)**: used when there is no active OpenSpec change requiring the two-PR path (see `managing-openspec`), including lightweight single-PR spec-linked changes that edit canonical specs directly. Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`. Include the ticket ID only when the branch has one. For lightweight changes, mention the canonical spec path and use OpenSpec change ID `N/A`.

Which PR closes the linked ticket, and how, is decided at merge time, not at opening — return to SKILL.md's Topics table and load the Merging topic's ticket step.

## Example Commands

```bash
git diff $(git merge-base HEAD main)...HEAD
git diff $(git merge-base HEAD main)...HEAD --name-only

gh pr create --title "feat: [CU-86c8zdwuk] Add user preferences" --body "$(cat <<'EOF'
ClickUp: https://app.clickup.com/t/86c8zdwuk

Users lose their theme selection on every page refresh. This adds persistence so preferences survive across sessions.
EOF
)"

gh pr view 123 --json title,body,comments,headRefName
gh pr diff 123
gh pr edit 123 --title "feat: [CU-86c8zdwuk] Add user preferences"
```
