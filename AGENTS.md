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
    kill.dart                 # Stop running app
    launch.dart               # Launch Flutter app detached
    logs.dart                 # Filtered log viewing + follow mode
    reload.dart               # Hot reload via SIGUSR1
    restart.dart              # Hot restart via SIGUSR2
    screenshot.dart           # Device screenshot (adb / xcrun)
    select.dart               # Toggle widget selection mode
    selected.dart             # Get selected widget info
    status.dart               # Check if app is running
    tree.dart                 # Widget tree inspection
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

### Testing (quick reference)

- Every change must be tested before a PR is opened.
- `task smoke` — full end-to-end test of all commands.
- `task test:<command>` — individual command test.
- `task analyze` — lint + format check.

**Full details**: [TESTING.md](TESTING.md)

### Code style (quick reference)

- No classes — top-level functions only.
- No third-party packages.
- Each command: `lib/commands/<name>.dart` exporting `Future<int> runXxx(List<String> args)`.
- Errors to `stderr` prefixed with `ERROR: `, status tokens to `stdout` in `UPPER_SNAKE_CASE`.
- Manual arg parsing with `for` loop + `switch`.

**Full details**: [CODE-STYLE.md](CODE-STYLE.md)
