# AGENTS.md

Guide for AI coding agents working in this repository.

## Project Overview

**fdb (Flutter Debug Bridge)** — a pure Dart CLI tool that lets AI agents interact
with running Flutter apps on physical devices and simulators. It launches Flutter apps
as detached processes, communicates via POSIX signals and the VM Service Protocol
over WebSocket, and stores all state in `/tmp/fdb_*` files.

- **Language:** Dart 3.x (SDK `>=3.0.0 <4.0.0`)
- **Runtime:** Dart VM (standalone — not a Flutter app)
- **External dependencies:** none — only `dart:io`, `dart:async`, `dart:convert`
- **Architecture:** flat, procedural — no classes, no DI, no frameworks
- **Entry point:** `bin/fdb.dart` dispatches to command functions via `switch`

### Directory layout

```
bin/fdb.dart                  # CLI entry point — command dispatcher
lib/
  constants.dart              # File paths and timeout constants
  process_utils.dart          # PID/process helper functions
  vm_service.dart             # WebSocket JSON-RPC to Flutter VM service
  commands/
    devices.dart              # List connected devices
    input.dart                # Enter text into a widget
    kill.dart                 # Stop running app
    launch.dart               # Launch Flutter app detached
    logs.dart                 # Filtered log viewing + follow mode
    reload.dart               # Hot reload via SIGUSR1
    restart.dart              # Hot restart via SIGUSR2
    screenshot.dart           # Screenshot (all platforms: adb, xcrun, screencapture, CDP, fdb_helper)
    scroll.dart               # Scroll / swipe gesture
    select.dart               # Toggle widget selection mode
    selected.dart             # Get selected widget info
    status.dart               # Check if app is running
    tap.dart                  # Tap a widget by selector or coordinates
    tree.dart                 # Widget tree inspection
packages/
  fdb_helper/                 # Flutter package — registers VM service extensions
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

- No classes — top-level functions only.
- Each command: `lib/commands/<name>.dart` exporting `Future<int> runXxx(List<String> args)`.
- Errors to `stderr` prefixed with `ERROR: `, status tokens to `stdout` in `UPPER_SNAKE_CASE`.
- Manual arg parsing with `for` loop + `switch`.

**Full details**: [CODE-STYLE.md](CODE-STYLE.md)

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracker (`bd`)

This repo uses `bd` (Beads) as its issue tracker. Issues live in `.beads/embeddeddolt/` (gitignored) and are auto-exported to `.beads/issues.jsonl` (git-tracked) after every write.

**Collaboration flow:** write issues → commit `issues.jsonl` alongside code → teammates `git pull` + `bd bootstrap`.

### Quick reference

```bash
bd prime                                                          # Load session context (run at session start)
bd ready                                                          # List available issues
bd show <id>                                                      # View issue details
bd update <id> --claim                                            # Claim an issue
bd create --title="..." --description="..." --type=task --priority=2  # Create an issue
bd close <id>                                                     # Close an issue
bd bootstrap                                                      # Rebuild local DB after git pull
bd github sync                                                    # Bidirectional sync with GitHub Issues
bd github sync --pull-only                                        # Pull from GitHub only
bd github sync --push-only                                        # Push to GitHub only
```

### Rules

- Commit `issues.jsonl` together with the code changes it tracks.
- Run `bd bootstrap` after `git pull` on a machine that already has a local DB.
- Run `bd prime` at the start of every session — not at compaction.
- `bd` is the source of truth; GitHub Issues are a mirror via `bd github sync`.
<!-- END BEADS INTEGRATION -->
