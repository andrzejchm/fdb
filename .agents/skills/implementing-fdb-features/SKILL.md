---
name: implementing-fdb-features
description: Implements features, functionalities, and improvements to fdb and its packages. Use when creating new features, adding new commands, or improving existing functionality in fdb or fdb_helper.
metadata:
  internal: true
---

## Workflow checklist

Copy this into `mcp_Todowrite` at the start of every feature session and tick off each item as you go:

```
Capture:
- [ ] Read issue in full and claim it (bd update <id> --claim)

Setup:
- [ ] Create worktree (mcp_Git-worktree create <name> main)
- [ ] Run task setup in the worktree

Implementation:
- [ ] Core models: lib/core/commands/<name>/<name>_models.dart
- [ ] Core verb:   lib/core/commands/<name>/<name>.dart
- [ ] CLI adapter: lib/cli/adapters/<name>_cli.dart
- [ ] Register case + usage string in bin/fdb.dart
- [ ] fdb_helper handler (if needed): packages/fdb_helper/lib/src/handlers/<name>_handler.dart
- [ ] Register in fdb_binding.dart (if handler added)
- [ ] Test app changes in example/test_app/lib/main.dart (if needed)

Taskfile tests:
- [ ] test:<command> task added following existing pattern
- [ ] Task added to smoke sequence
- [ ] task analyze passes (dart analyze + dart format + flutter analyze)

Docs:
- [ ] README.md — commands table
- [ ] .agents/skills/testing-fdb/SKILL.md — individual test list
- [ ] lib/skill/SKILL.md — usage examples (load creating-opencode-skills skill first)
- [ ] doc/agent-scenarios.md — add scenario for the new/changed command

Agent scenarios (delegated):
- [ ] Spawn scenarios agent with worktree path + scenario IDs to run
- [ ] Agent reports all scenarios pass (semantically correct output)

Review loop (delegated):
- [ ] Spawn reviewing-fixing-loop agent
- [ ] All findings resolved or triaged

Checks (delegated):
- [ ] Spawn checks agent (dart analyze + flutter analyze + dart format)
- [ ] All clean

Platform tests (ALL mandatory before PR):
- [ ] macOS — task test:<command> passes
- [ ] Android physical — task test:<command> passes
- [ ] iOS simulator — task test:<command> passes
- [ ] Full smoke suite: task smoke (Android)

PR:
- [ ] Load humanizing-ai-text skill before writing PR body
- [ ] Load managing-pr-descriptions-global skill
- [ ] Push branch
- [ ] Open PR (gh pr create)
- [ ] CI green (gh pr checks --watch)

Merge:
- [ ] bd close <id> + copy issues.jsonl into worktree + commit + push
- [ ] gh pr merge --squash --delete-branch
- [ ] Remove worktree (mcp_Git-worktree remove <name>)
```

---

## Step 1 — Capture the feature

### 1a — Starting from a chat pitch (no issue yet)

Create the GitHub issue before touching any code:

```bash
gh issue create \
  --title "feat: fdb <command> — <short description>" \
  --body "..." \
  --repo andrzejchm/fdb
```

Issue must include: problem statement, exact CLI interface + flags, stdout output tokens (`THING=value`), stderr error format, implementation notes, test app widget changes (if any), acceptance criteria checkboxes.

Only proceed to Step 2 after the issue is created.

### 1b — Starting from an existing issue

```bash
gh issue view <number> --repo andrzejchm/fdb
bd update <id> --claim
```

Do not deviate from the specified output tokens or CLI flags without updating the issue first.

---

## Step 2 — Create a worktree

```bash
# Via mcp_Git-worktree tool:
mcp_Git-worktree action=create name=<feature-name> ref=main
# Worktree lands at: .worktrees/<feature-name>/
```

Run setup inside the worktree:
```bash
task setup   # dart pub get + flutter pub get
```

---

## Step 3 — Implement

Read these files before writing any code:
- `AGENTS.md` — project overview and directory layout
- `CODE-STYLE.md` — Dart style rules
- `packages/fdb_helper/AGENTS.md` — handler architecture rules
- `lib/core/commands/scroll_to/scroll_to.dart` — canonical core verb
- `lib/cli/adapters/scroll_to_cli.dart` — canonical CLI adapter
- `packages/fdb_helper/lib/src/handlers/scroll_to_handler.dart` — canonical handler

**Core models** (`lib/core/commands/<name>/<name>_models.dart`):
- `<Name>Input` typedef (named record)
- Sealed `<Name>Result` hierarchy — one variant per outcome

**Core verb** (`lib/core/commands/<name>/<name>.dart`):
- One public function: `Future<<Name>Result> verbName(<Name>Input input)`
- Never throws — catch everything, return a sealed result variant
- Re-export models: `export 'package:fdb/core/commands/<name>/<name>_models.dart';`
- VM calls: `vmServiceCall('ext.fdb.yourExt', params: params)`

**CLI adapter** (`lib/cli/adapters/<name>_cli.dart`):
- One public function: `Future<int> runXxxCli(List<String> args)`
- Use `runCliAdapter(parser, args, _execute)` from `lib/cli/args_helpers.dart`
- `package:args` ArgParser — no manual for-loop parsing
- Required option check: `if (results.option('x') == null) { stderr.writeln('ERROR: ...'); return 1; }`
- Success tokens → stdout `UPPER_SNAKE_CASE`; errors → stderr `ERROR: `
- Register in `bin/fdb.dart`: `case 'your-command': return runXxxCli(args);` + usage string

**fdb_helper handler** (`packages/fdb_helper/lib/src/handlers/<name>_handler.dart`) — only if the command needs the Flutter app side:
- One public function: `Future<developer.ServiceExtensionResponse> handleXxx(String method, Map<String, String> params)`
- No classes — top-level functions only; helpers are private
- Register in `fdb_binding.dart`: one `_registerExtension('ext.fdb.xxx', handleXxx)` line

**Docs to update:**
- `README.md` — commands table
- `.agents/skills/testing-fdb/SKILL.md` — add `task test:<command>` to individual test list
- `lib/skill/SKILL.md` — add usage examples with output tokens; load `creating-opencode-skills` skill before editing to follow spec-sheet style rules

---

## Step 4 — Add Taskfile tests

```yaml
test:your-command:
  desc: <short description>
  dir: '{{.TEST_APP}}'
  cmds:
    - |
      echo "==> <scenario>"
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
        echo "FAIL: fdb your-command - YOUR_TOKEN= not found" >&2
        exit 1
      fi
```

- Add to `smoke` task sequence in the right position
- Cover all acceptance criteria from the issue
- Use `mktemp -d` for temp files (macOS + Linux compatible — never `mktemp path/XXXXXX.ext`)

Verify:
```bash
task test:launch DEVICE=<id>
task test:your-command
task analyze
```

---

## Step 4b — Spawn agent scenarios runner (DELEGATE)

Taskfile tests grep for output tokens — binary pass/fail. They cannot catch
semantic regressions (wrong screen scope, elements leaking from other routes,
incorrect visible text, etc.). The scenarios in `doc/agent-scenarios.md` fill
this gap: the subagent runs fdb commands against the live test app and evaluates
the actual output against a semantic checklist.

Decide which scenarios to run:
- Always include `S1` (home screen baseline) as a sanity check.
- Include every scenario that covers the command you added or changed.
- If you added a new command, add its scenario to `doc/agent-scenarios.md`
  first, then include it in the delegation.

```
Spawn a general subagent with this prompt:

You are a scenario runner for the fdb test suite. The app is already running
in the worktree at `.worktrees/<feature-name>/example/test_app`.

Read doc/agent-scenarios.md in full, then execute scenarios <S1, S2, ...>
exactly as written. For each scenario:
1. Run every setup and command step from the worktree's example/test_app dir
   using `dart run ../../bin/fdb.dart <command>`.
2. Read the actual output.
3. Verify every point in the "What to verify" list.
4. Report PASS or FAIL for each scenario with a brief reason.

After all scenarios, return a summary: how many passed, how many failed, and
the full output + verdict for any that failed.
```

Do not proceed to Step 5 until the subagent reports all scenarios passing.

---

## Step 5 — Spawn review-fix loop agent (DELEGATE)

```
Spawn a coding subagent with this prompt:

Run a review-fixing loop on the <feature-name> implementation in the git
worktree at `.worktrees/<feature-name>`.

Review against:
1. GitHub issue acceptance criteria
2. CODE-STYLE.md and packages/fdb_helper/AGENTS.md
3. Edge cases and error handling
4. Output token format
5. Taskfile test coverage
6. Doc completeness (README, testing-fdb/SKILL.md, lib/skill/SKILL.md)

Fix all real findings. Commit and push when the loop converges.
```

---

## Step 6 — Spawn checks agent (DELEGATE)

```
Spawn a coding subagent with this prompt:

Run all static analysis and format checks on the fdb worktree at
`.worktrees/<feature-name>`.

1. dart pub get
2. dart analyze lib/ bin/ test/
3. dart format --page-width 120 --trailing-commas preserve --set-exit-if-changed lib/ bin/ test/
4. cd packages/fdb_helper && flutter analyze --suppress-analytics

Fix ALL issues. Commit and push. Return exact output of each check.
```

---

## Step 7 — Manual platform testing (MANDATORY)

All three platforms must pass before opening a PR. No exceptions.

Devices:
- macOS: `DEVICE_ID=macos`
- Android physical: `DEVICE_ID=b433094a`
- iOS simulator: `DEVICE_ID=C1DE4562-CFBF-45D8-B79E-740A11E86171`

For each platform:
```bash
cd .worktrees/<feature-name>/example/test_app
dart run ../../bin/fdb.dart kill 2>/dev/null || true
dart run ../../bin/fdb.dart launch --device <DEVICE_ID>
# from worktree root:
task test:<command>
dart run bin/fdb.dart kill
```

Platform notes:
- macOS: `fdb restart` (SIGUSR2) is unreliable — use kill + launch between scenarios
- Android: first build is slow (3-5 min); `adb` must be on PATH
- iOS simulator: `xcrun` must be on PATH

**Full smoke suite** (after all three platforms pass):
```bash
task smoke   # runs on Android
```

---

## Step 8 — Open PR

Load `humanizing-ai-text` and `managing-pr-descriptions-global` skills before writing the PR body.

```bash
gh pr create \
  --title "feat: <short summary>" \
  --body "..." \
  --repo andrzejchm/fdb
```

PR body: 1-2 sentences explaining why this exists and what it enables. No file lists. No counts. `Closes #<number>`.

Wait for CI:
```bash
gh pr checks <pr-number> --repo andrzejchm/fdb --watch
```

Do not merge until CI is green.

---

## Step 9 — Merge and clean up

```bash
# Close issue and sync issues.jsonl into the worktree (pre-commit hook writes to
# main repo, not worktree — must copy manually before committing):
bd close <issue-id>
cp <repo-root>/.beads/issues.jsonl .beads/issues.jsonl
git add .beads/issues.jsonl
git commit -m "chore(bd): close <issue-id>"
git push

# Squash-merge
gh pr merge <number> --squash --delete-branch --repo andrzejchm/fdb

# Remove worktree
# Via mcp_Git-worktree tool:
mcp_Git-worktree action=remove name=<feature-name>
```

---

## Key invariants

- `fdb_binding.dart` is registration-only — no handler logic
- Each handler = one file, one public `handleXxx` function, no classes
- CLI adapters use `package:args` via `runCliAdapter` — no manual for-loop parsing
- `fdb_helper` production `dependencies:` must not grow without explicit approval
- All three platforms must pass before PR — no exceptions
- Review-fix loop and checks are always delegated to subagents
- `bd close` must run on the feature branch before merging

## Reference files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Project overview, directory layout |
| `CODE-STYLE.md` | Dart style, architecture rules |
| `packages/fdb_helper/AGENTS.md` | Handler file layout, binding rules |
| `TESTING.md` | Test commands and conventions |
| `doc/agent-scenarios.md` | Semantic scenarios for agent-driven regression testing |
| `Taskfile.yml` | All test tasks and smoke sequence |
| `lib/core/commands/scroll_to/scroll_to.dart` | Canonical core verb |
| `lib/cli/adapters/scroll_to_cli.dart` | Canonical CLI adapter |
| `packages/fdb_helper/lib/src/handlers/scroll_to_handler.dart` | Canonical handler |
| `packages/fdb_helper/lib/src/gesture_dispatcher.dart` | Gesture dispatch primitives |
| `packages/fdb_helper/lib/src/element_tree_finder.dart` | Widget tree search utilities |
| `packages/fdb_helper/lib/src/widget_matcher.dart` | Selector parsing |
