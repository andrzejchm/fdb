---
name: testing-fdb
description: Testing and developing fdb (Flutter Debug Bridge). Covers running the smoke test suite, individual command tests, static analysis, and the test app. Use when running fdb tests, adding new commands, verifying fdb behavior, or preparing a release.
metadata:
  internal: true
---

## Prerequisites

- Dart SDK >= 3.0.0
- Flutter SDK
- [Task](https://taskfile.dev) (`brew install go-task`)
- A running iOS Simulator or Android emulator

## Test App

A minimal Flutter app lives in `example/test_app/` and is used as the target for all integration tests.

## Setup

```bash
task setup    # dart pub get + flutter pub get in test app
```

## Running Tests

### Full smoke test

Runs all fdb commands end-to-end: launch, status, reload, restart, logs, tree, screenshot, select, kill.

```bash
task smoke                    # auto-detect device
task smoke DEVICE=iPhone-16   # specific device
```

### Individual command tests

The app must already be running (via `task test:launch`) before running individual tests:

```bash
task test:launch DEVICE=iPhone-16
task test:status
task test:status-after-interrupted-launch
task test:reload
task test:restart
task test:logs
task test:logs-tag
task test:tree
task test:screenshot
task test:select
task test:tap
task test:input
task test:scroll
task test:kill
task test:status-stopped
```

### Static analysis

```bash
task analyze    # dart analyze + dart format --set-exit-if-changed
```

### Unit tests

```bash
task test:unit    # dart test (when tests exist)
```

### Cleanup

```bash
task cleanup    # kill app, remove .fdb/ session directory
```

## Test output conventions

Each test task prints:
- `PASS: fdb <command>` on success
- `FAIL: fdb <command> - <reason>` on failure (to stderr, exits 1)

## Adding a new command

1. Create `lib/commands/your_command.dart` with `Future<int> runYourCommand(List<String> args)`.
2. Write errors to `stderr` prefixed with `ERROR: `, status tokens to `stdout`.
3. Add a `case` to the `switch` in `bin/fdb.dart:_runCommand`.
4. Add the command to the `usage` string in `bin/fdb.dart`.
5. Add a `test:your-command` task to `Taskfile.yml` following the existing pattern.
6. Add the new task to the `smoke` task's command sequence.
7. Update `README.md` commands table.
8. Update `skills/using-fdb/SKILL.md` with the new command.
9. Update `doc/README.agents.md` commands reference table.
