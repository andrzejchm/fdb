# AGENTS.md

Guide for AI coding agents working in this repository.

## Project Overview

**fdb (Flutter Debug Bridge)** — a pure Dart CLI tool that lets AI agents interact
with running Flutter apps on physical devices and simulators. It launches Flutter apps
as detached processes, communicates via POSIX signals and the VM Service Protocol
over WebSocket, and stores all session state under a per-project `.fdb/` directory
(PID file, VM service URI, logs, launcher script). The session directory defaults to
`<CWD>/.fdb/` and is overridden by `--project <path>` on `fdb launch`.

- **Language:** Dart 3.x (SDK `>=3.0.0 <4.0.0`)
- **Runtime:** Dart VM (standalone — not a Flutter app)
- **External dependencies:** `package:args` (CLI argument parsing) plus the Dart SDK (`dart:io`, `dart:async`, `dart:convert`).
- **Architecture:** layered. `lib/core/` is interface-agnostic business logic; `lib/cli/` is the CLI adapter that wraps it. The split is enforced by directory convention so a future MCP server, REST API, or library consumer can call the same core functions without going through ArgParser or stdout tokens.
- **Entry point:** `bin/fdb.dart` dispatches to CLI adapter functions (`runXxxCli`) via `switch`. Adapters call into `lib/core/commands/`.

### Directory layout

```
bin/fdb.dart                              # CLI entry point — command dispatcher
lib/
  constants.dart                          # File paths + timeouts (used by both layers)
  core/                                   # Interface-agnostic business logic
    app_died_exception.dart               # Domain exception
    process_utils.dart                    # PID/process helpers
    vm_service.dart                       # WebSocket VM service client
    vm_lifecycle_events.dart
    launch_failure_analyzer.dart
    models/
      command_result.dart                 # Marker base for sealed result hierarchies
    commands/<name>/
      <name>.dart × 28                    # verb function + `export '<name>_models.dart';`
      <name>_models.dart × 28             # <Name>Input typedef + sealed <Name>Result
  cli/                                    # CLI adapter layer
    args_helpers.dart                     # runCliAdapter, runSimpleCliAdapter, parseXY
    adapters/
      <name>_cli.dart × 28                # runXxxCli(args) — ArgParser + token formatting
packages/
  fdb_helper/                             # Flutter package — registers VM service extensions
```

## Build Commands

```bash
dart pub get                          # Install dependencies
dart run bin/fdb.dart <command>       # Run locally
dart pub global activate --source path .  # Install globally (local)
dart analyze                          # Static analysis
dart format .                         # Format
```

## References

| Topic | What it covers | Reference |
|-------|---------------|-----------|
| Testing | Test commands, requirements, output conventions | [TESTING.md](TESTING.md) |
| Code style | Imports, naming, formatting, architecture, error handling | [CODE-STYLE.md](CODE-STYLE.md) |
| fdb_helper architecture | Handler file layout, binding rules, adding new extensions | [packages/fdb_helper/AGENTS.md](packages/fdb_helper/AGENTS.md) |

### Testing (quick reference)

- Every change must be tested before a PR is opened.
- `task smoke` — full end-to-end test of all commands.
- `task test:<command>` — individual command test.
- `task analyze` — lint + format check.

**Full details**: [TESTING.md](TESTING.md)

### Code style (quick reference)

- **Layered architecture**: `lib/core/` is interface-agnostic (no `package:args`, no stdio writes); `lib/cli/` is the CLI adapter.
- Core: each command exports a `<Name>Input` typedef, sealed `<Name>Result` hierarchy, and a `Future<<Name>Result> verbName(<Name>Input)` function. Never throws (catches and translates to a result variant).
- CLI adapter: `Future<int> runXxxCli(List<String> args)` — ArgParser + cross-flag validation + pattern-match the sealed result + write tokens.
- Errors to `stderr` prefixed with `ERROR: `, status tokens to `stdout` in `UPPER_SNAKE_CASE`. Tokens are byte-identical contracts asserted by smoke tests.
- Required options: explicit null-check on `results.option('name')`, NOT `mandatory: true` (preserves verbatim error wording).
- Every command supports `--help` / `-h` (handled centrally by `runCliAdapter` — adapters do not declare their own `--help` flag).

**Full details**: [CODE-STYLE.md](CODE-STYLE.md)

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracker (`bd`)

This repo uses `bd` (Beads) as its issue tracker. Issues live in `.beads/embeddeddolt/` (gitignored) and are auto-exported to `.beads/issues.jsonl` (git-tracked) after every write.

**Collaboration flow:** write issues → commit `issues.jsonl` alongside code → teammates `git pull` + `bd bootstrap`.

### Quick reference

```bash
bd prime                                                          # Load session context (run at session start)
bd ready                                                          # List unclaimed available issues
bd show <id>                                                      # View issue details
bd update <id> --claim                                            # Claim an issue
bd update <id> --status=in-progress                               # Mark issue as in progress
bd create --title="..." --description="..." --type=task --priority=2  # Create an issue
bd close <id>                                                     # Close an issue
bd sync                                                           # Flush pending writes (before compaction)
bd bootstrap                                                      # Rebuild local DB after git pull
bd github sync                                                    # Bidirectional sync with GitHub Issues
bd github sync --pull-only                                        # Pull from GitHub only
bd github sync --push-only                                        # Push to GitHub only
```

### Rules

- Commit `issues.jsonl` together with the code changes it tracks — never in isolation.
- Run `bd bootstrap` after `git pull` on a machine that already has a local DB.
- Run `bd prime` at session start only — not during compaction (`bd sync` handles compaction).
- `bd` is the source of truth; GitHub Issues are a mirror via `bd github sync`.
- Never run `bd doctor --fix` — it can corrupt the local DB.
- Capture any work discovered during implementation as new issues immediately.
<!-- END BEADS INTEGRATION -->
