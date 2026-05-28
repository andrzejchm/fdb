# Testing

Rules and commands for testing fdb changes.

## Contents
- Requirements
- Test Commands
- Test Output Conventions
- Adding Tests for New Commands

## Requirements

Every change must be tested before work is considered done. Do not
create a pull request until you have verified the change works by
running the appropriate tests and confirming they pass.

## Test Commands

```bash
# Full end-to-end smoke test (all commands)
task smoke
task smoke DEVICE=iPhone-16    # specific device

# Individual command tests (app must be running for most)
task test:devices
task test:launch DEVICE=<id>
task test:launch-verbose DEVICE=<id>
task test:attach DEVICE=<id>
task test:status
task test:doctor
task test:reload
task test:restart
task test:logs
task test:logs-tag
task test:syslog
task test:crash-report
task test:tree
task test:describe
task test:describe-grid
task test:describe-nested-gestures
task test:describe-listtile-button
task test:describe-router
task test:screenshot
task test:deeplink
task test:select
task test:tap
task test:double-tap
task test:longpress
task test:tap-at
task test:tap-disappearing-widget
task test:tap-ignore-pointer-wrapper
task test:tap-cupertino-button
task test:input
task test:scroll
task test:scroll-to
task test:wait
task test:swipe
task test:back
task test:clean
task test:ext
task test:shared-prefs
task test:native-view-tap
task test:simulator
task test:grant-permission
task test:native-tap
task test:app-died
task test:kill
task test:mem
task test:gc
task test:status-stopped
task test:status-after-interrupted-launch
task test:session-dir
task test:fdb-helper-release-stubs

# Static analysis + formatting
task analyze

# Unit tests
task test:unit

# Cleanup
task cleanup
```

## Test Output Conventions

Each test task prints:
- `PASS: fdb <command>` on success.
- `FAIL: fdb <command> - <reason>` on failure (to stderr, exits 1).

## Adding Tests for New Commands

1. Add a `test:your-command` task to `Taskfile.yml` following the existing pattern.
2. Add the new task to the `smoke` task sequence.
3. Run `task test:your-command` and confirm `PASS` before opening a PR.
