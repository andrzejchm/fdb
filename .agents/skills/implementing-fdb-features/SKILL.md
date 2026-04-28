---
name: implementing-fdb-features
description: Implements features, functionalities, and improvements to fdb and its packages. Use when creating new features, adding new commands, or improving existing functionality in fdb or fdb_helper.
metadata:
  internal: true
---

## Workflow checklist

Copy and track progress for each feature:

```
Capture:
- [ ] If starting from chat: create a GitHub issue first (Step 1a)
- [ ] If starting from an issue: read it in full and claim it (Step 1b)

Setup:
- [ ] Create a worktree: mcp_Git-worktree create <feature-name> main fetch=true
- [ ] Run task setup in the worktree

Implementation:
- [ ] CLI command: lib/commands/<name>.dart (runXxx pattern)
- [ ] Register in bin/fdb.dart (case + usage string)
- [ ] fdb_helper handler: packages/fdb_helper/lib/src/handlers/<name>_handler.dart
- [ ] Register in fdb_binding.dart (one _registerExtension line)
- [ ] Test app changes in example/test_app/lib/main.dart (if needed)

Taskfile tests:
- [ ] test:<command> task added following existing pattern
- [ ] Task added to smoke sequence
- [ ] task analyze passes (dart analyze + dart format + flutter analyze)

Docs (see Step 3 for full list):
- [ ] README.md, doc/README.agents.md, testing-fdb/SKILL.md updated

Manual platform tests (ALL mandatory before PR):
- [ ] macOS — all scenarios pass, screenshots confirm correct behavior
- [ ] Android physical — all scenarios pass, screenshots confirm
- [ ] iOS simulator — all scenarios pass, screenshots confirm

Review loop (delegated):
- [ ] Spawn review-fixing-loop agent on the worktree
- [ ] All findings resolved or triaged, loop converges

Checks (delegated):
- [ ] Spawn checks agent: dart analyze + flutter analyze + dart format
- [ ] All clean

Beads:
- [ ] bd close <id> for the implemented issue
- [ ] issues.jsonl copied from repo root into worktree and committed (worktree rule — see managing-beads skill)

PR:
- [ ] Push branch
- [ ] CI green
- [ ] PR opened following managing-pr-descriptions skill
- [ ] bd close <id> run on the feature branch; issues.jsonl committed on that same branch
- [ ] Worktree removed after merge
```

---

## Step 1 — Capture the feature

### 1a — Starting from a chat pitch (no issue yet)

When the user describes a feature in conversation rather than pointing at an issue, **create the GitHub issue before touching any code**. A good issue is the contract the implementation is held to.

The issue must include:
- **Problem** — what agents/users cannot do today
- **CLI interface** — exact command, flags, and usage examples
- **Output tokens** — exact stdout tokens (`THING=value`) and stderr error format
- **Implementation notes** — which files to create/modify, which existing utilities to reuse
- **Test app changes** — any new widget needed in `example/test_app/lib/main.dart`
- **Acceptance criteria** — numbered checkboxes, one per testable behaviour

```bash
gh issue create \
  --title "feat: fdb <command> — <short description>" \
  --body "..." \
  --repo andrzejchm/fdb
```

Only proceed to Step 2 after the issue is created. Reference it throughout as the source of truth.

### 1b — Starting from an existing issue

Read the full issue and claim it before writing any code:
```bash
gh issue view <number> --repo andrzejchm/fdb
bd update <id> --claim
```

The issue contains acceptance criteria, CLI interface, output token format, implementation notes, and Taskfile test scenarios. Do not deviate from the specified output tokens or CLI flags without updating the issue first.

---

## Step 2 — Create a worktree

Never work on `main` directly. Use a dedicated worktree:

```bash
# Via mcp_Git-worktree tool:
mcp_Git-worktree action=create name=<feature-name> ref=main fetch=true
# Worktree lands at: .worktrees/<feature-name>/
```

Run setup inside the worktree:
```bash
cd .worktrees/<feature-name>
task setup
```

---

## Step 3 — Implement

Read the relevant files before writing any code:

**Always read first:**
- `AGENTS.md` — project overview and conventions
- `CODE-STYLE.md` — Dart style rules
- `packages/fdb_helper/AGENTS.md` — handler architecture rules
- `lib/commands/scroll_to.dart` — canonical recent CLI command example
- `packages/fdb_helper/lib/src/handlers/scroll_to_handler.dart` — canonical handler example
- `packages/fdb_helper/lib/src/gesture_dispatcher.dart` — if adding gestures
- `packages/fdb_helper/lib/src/handlers/tap_handler.dart` — if similar to tap

**CLI layer** (`lib/commands/<name>.dart`):
- Export exactly one public function: `Future<int> runXxx(List<String> args)`
- Parse args manually with `for` loop + `switch` — no CLI framework
- Call the VM extension via `vmServiceCall(uri, 'ext.fdb.yourExt', params)`
- Errors → `stderr` prefixed with `ERROR: `, exit 1
- Success tokens → `stdout` in `UPPER_SNAKE_CASE` (e.g. `TAPPED=`, `SCROLLED_TO=`)
- Register in `bin/fdb.dart`: add `case 'your-command':` and add to usage string

**fdb_helper layer** (`packages/fdb_helper/lib/src/handlers/<name>_handler.dart`):
- Export exactly one public function: `Future<developer.ServiceExtensionResponse> handleXxx(String method, Map<String, String> params)`
- All helpers and constants are private (`_prefixed`) in the same file
- No classes — top-level functions only
- Register in `fdb_binding.dart`: add ONE `_registerExtension('ext.fdb.xxx', handleXxx)` line
- Add the extension name to the FdbBinding doc comment

**Docs to update (new command):**
- `README.md` — add to commands table
- `doc/README.agents.md` — add to commands reference table; update troubleshooting section if relevant
- `.agents/skills/testing-fdb/SKILL.md` — add the new `task test:<command>` to the individual test list
- `.agents/skills/using-fdb/SKILL.md` — add usage examples (if the skill exists)

**Docs to update (bug fix that changes existing behaviour):**
- `doc/README.agents.md` — update any affected troubleshooting tips or output token descriptions
- `.agents/skills/testing-fdb/SKILL.md` — add any new test tasks that were added to the smoke sequence

---

## Step 4 — Add Taskfile tests

Every new command needs a `test:<command>` task in `Taskfile.yml` following the exact existing pattern:

```yaml
test:your-command:
  desc: <short description>
  dir: '{{.TEST_APP}}'
  cmds:
    - |
      echo "==> <scenario description>"
      OUTPUT=$({{.FDB}} your-command --flag value 2>&1)
      EXIT_CODE=$?
      echo "$OUTPUT"
      if [ $EXIT_CODE -ne 0 ]; then
        echo "FAIL: fdb your-command exited with code $EXIT_CODE" >&2
        exit 1
      fi
      if echo "$OUTPUT" | grep -q "YOUR_TOKEN="; then
        echo "PASS: fdb your-command"
      else
        echo "FAIL: fdb your-command - YOUR_TOKEN= not found in output" >&2
        exit 1
      fi
```

- Add it to the `smoke` task sequence in the right position (after similar commands)
- Test scenarios must match the acceptance criteria in the issue
- The app must be running (via `task test:launch`) for most tests

Run to verify:
```bash
task test:launch DEVICE=<simulator_id>
task test:your-command
task analyze
```

---

## Step 5 — Manual platform testing (MANDATORY)

**All three platforms must pass before opening a PR. No exceptions.**

Available devices (run `fdb devices` to confirm):
- **macOS**: `DEVICE_ID=macos`
- **Android physical**: `DEVICE_ID=b433094a` (or current device)
- **iOS simulator**: `DEVICE_ID=C1DE4562-CFBF-45D8-B79E-740A11E86171` (iPhone 17 Pro) or run `fdb devices` to find it

For each platform:

```bash
# 1. Kill any running app
cd .worktrees/<feature-name>/example/test_app
dart run ../../bin/fdb.dart kill

# 2. Launch (first build may take up to 3 min)
dart run ../../bin/fdb.dart launch --device <DEVICE_ID>

# 3. Run the new command's test task
cd .worktrees/<feature-name>
task test:<command>

# 4. Take a screenshot and visually confirm correct behavior
cd example/test_app
dart run ../../bin/fdb.dart screenshot
# Read the screenshot file with Read tool to confirm the UI state

# 5. Kill
dart run ../../bin/fdb.dart kill
```

For each platform, document:
- Command output (exact stdout/stderr)
- Screenshot showing the expected result
- PASS or FAIL with reason

**If any platform fails:** fix the bug, relaunch, re-test. Do not skip to PR until all three pass.

**Platform-specific notes:**
- macOS: `fdb restart` (SIGUSR2) is unreliable — use `kill` + `launch` between scenarios
- iOS simulator: `xcrun simctl` must be on PATH for screenshots (installed with Xcode)
- Android: `adb` must be on PATH; first build is slow (~3–5 min)
- Physical iOS requires a provisioning profile — use the simulator instead

---

## Step 6 — Spawn review-fix loop agent (DELEGATE)

After all platform tests pass, spawn a review agent. Do not inline the review — delegate it:

```
Spawn a coding subagent with prompt:
/review-fixing-loop

Work in the git worktree at `.worktrees/<feature-name>`.

Review the changes introduced by this feature. Focus on:
1. Correctness of the implementation against the GitHub issue acceptance criteria
2. Code style — matches CODE-STYLE.md and packages/fdb_helper/AGENTS.md
3. Edge cases — error handling, invalid inputs, missing selectors
4. Output tokens — match the specified format exactly
5. Taskfile test quality — scenarios cover the acceptance criteria
6. Doc accuracy — README, agents doc, skill file

After all fixes converge, commit and push.
```

Wait for the review agent to complete before proceeding.

---

## Step 7 — Spawn checks agent (DELEGATE)

After the review loop converges, spawn a separate checks agent:

```
Spawn a coding subagent with prompt:
Run all static analysis and format checks on the fdb worktree at
`.worktrees/<feature-name>`.

1. dart pub get && flutter pub get --directory packages/fdb_helper
2. dart analyze (from worktree root)
3. dart format --set-exit-if-changed . (from worktree root)
4. flutter analyze packages/fdb_helper

Fix ALL issues. Commit and push.
Return: exact output of each check and confirmation all pass.
```

---

## Step 8 — Close issue, sync jsonl, and push

Close the beads issue, then sync `issues.jsonl` into the worktree before pushing.
See the **Working in a git worktree** section of the managing-beads skill for the exact copy command — the pre-commit hook writes to the main repo, not the worktree.

```bash
bd close <issue-id>
# copy + stage + commit issues.jsonl per managing-beads worktree rule
git push -u origin <branch-name>
```

Wait for CI to run:
```bash
gh pr checks <pr-number> --repo andrzejchm/fdb
# or watch the run:
gh run list --repo andrzejchm/fdb --branch <branch-name>
```

CI runs `task verify` which includes format, analyze, and unit tests. It must be green before merging.

---

## Step 9 — Open PR (DELEGATE)

Load the `managing-pr-descriptions-global` skill and create the PR:

```bash
gh pr create \
  --title "feat: <short summary>" \
  --body "..." \
  --repo andrzejchm/fdb
```

PR description rules (from managing-pr-descriptions skill):
- 2–3 sentences max
- Explain WHY the feature exists and what it enables
- No file lists, no implementation details, no counts
- Reference the issue: "Closes #<number>"

---

## Step 10 — Merge and clean up

### How `bd` and worktrees interact

All worktrees share **one Dolt database** in the main repo's `.beads/embeddeddolt/`.
`bd` discovers it via git's common-directory mechanism — any `bd` write (claim,
close, update) from any worktree goes to that same shared DB immediately.

`issues.jsonl` is a **git-tracked file** that lives in each branch's checkout.
The pre-commit hook auto-exports the current DB state into whichever branch's
`issues.jsonl` is being committed. This means:

- `bd close <id>` updates the shared DB regardless of which worktree you run it from
- The commit that carries the updated `issues.jsonl` to `main` is whatever branch
  you commit to **after** running `bd close`
- Therefore: run `bd close` and commit **on the feature branch**, before merging,
  so the closed state reaches `main` via the squash commit

### Steps

Run from inside the feature worktree before merging:

```bash
bd close <id>
# The pre-commit hook auto-exports issues.jsonl — just stage and commit:
git add .beads/issues.jsonl
git commit -m "chore: close issue <id>"
git push
```

Then merge:
```bash
gh pr merge <number> --squash --delete-branch --repo andrzejchm/fdb
```

Remove the worktree:
```bash
# Via mcp_Git-worktree tool:
mcp_Git-worktree action=remove name=<feature-name>
```

---

## Key invariants (never break these)

- `fdb_binding.dart` is registration-only — never add handler logic to it
- Each handler = one file in `handlers/`, one public `handleXxx` function
- CLI args parsed manually — no CLI framework packages
- `fdb_helper` production `dependencies:` must not grow without explicit approval
- All three platforms (macOS, Android, iOS) must pass manual tests before PR
- The review-fix loop and checks are always spawned as separate delegated agents
- `bd close <id>` must be run before merging; the resulting `issues.jsonl` commit goes on the feature branch — all worktrees share one DB so the close takes effect immediately regardless of CWD, but only the branch you commit to carries the update to `main`
- Worktrees are always cleaned up after merge

## Reference files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Project overview, directory layout |
| `CODE-STYLE.md` | Dart style, architecture rules |
| `packages/fdb_helper/AGENTS.md` | Handler file layout, binding rules |
| `TESTING.md` | Test commands and conventions |
| `Taskfile.yml` | All test tasks and smoke sequence |
| `lib/commands/scroll_to.dart` | Canonical CLI command example |
| `packages/fdb_helper/lib/src/handlers/scroll_to_handler.dart` | Canonical handler example |
| `packages/fdb_helper/lib/src/gesture_dispatcher.dart` | Gesture dispatch primitives |
| `packages/fdb_helper/lib/src/element_tree_finder.dart` | Widget tree search utilities |
| `packages/fdb_helper/lib/src/widget_matcher.dart` | Selector parsing |
