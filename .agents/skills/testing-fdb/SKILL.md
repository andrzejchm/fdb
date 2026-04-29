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
task test:launch-verbose DEVICE=iPhone-16
task test:devices
task test:status
task test:status-after-interrupted-launch
task test:reload
task test:restart
task test:logs
task test:logs-tag
task test:syslog
task test:tree
task test:describe
task test:describe-grid
task test:screenshot
task test:native-view-tap
task test:deeplink
task test:native-tap
task test:select
task test:tap
task test:double-tap
task test:longpress
task test:tap-at
task test:input
task test:scroll
task test:scroll-to
task test:wait
task test:swipe
task test:back
task test:clean
task test:shared-prefs
task test:app-died
task test:kill
task test:status-stopped
task test:session-dir
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

1. Create `lib/core/commands/<name>/<name>.dart` (verb function) and `lib/core/commands/<name>/<name>_models.dart` (Input typedef + sealed Result).
2. Create `lib/cli/adapters/<name>_cli.dart` with `Future<int> runXxxCli(List<String> args)` using `runCliAdapter`.
3. Add a `case` to the `switch` in `bin/fdb.dart` calling `runXxxCli(args)`.
4. Add the command to the usage string in `bin/fdb.dart`.
5. Add a `test:your-command` task to `Taskfile.yml` following the existing pattern.
6. Add the new task to the `smoke` task's command sequence.
7. Update `README.md` commands table.
8. Update `doc/README.agents.md` commands reference table.
9. Update `.agents/skills/testing-fdb/SKILL.md` individual test list.
