# Testing

Rules and commands for testing fdb changes.

## Contents
- Requirements
- Test Commands
- Native Button Integration
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
task test:tap-custom-button
task test:tap-ref
task test:input
task test:scroll
task test:scroll-to
task test:wait
task test:swipe
task test:swipe-path
task test:back
task test:back-nested
task test:clean
task test:ext
task test:shared-prefs
task test:native-view-tap
task test:simulator
task test:grant-permission
task test:native-tap
task test:native-button
task test:native-button-lock    # explicit sleep/wake test; see below
task test:native-swipe
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

## Native Button Integration

`task test:native-button` and default `task smoke` test Home and app restoration,
starting awake/unlocked. They skip lock sleep/wake explicitly in their output.
Run `task test:native-button-lock` to test Home, sleep, wake and restoration.
For unattended full coverage, choose a disposable simulator or Android emulator
without a secure keyguard, and run that task separately (or set
`LOCK_BUTTON=true` for smoke). An unlocked secure physical Android can become
passcode-locked after the first power press; use the manual S49 scenario for it.
The explicit lock task reports this restoration blocker rather than accepting
Flutter's cached frame. On failure it reports unrestored state and never sends
an automatic cleanup button press. It cannot unlock passcodes.

On a secure physical Android, complete S49 using the documented manual-unlock
checkpoint: retain the observed sleep/wake evidence, have the user unlock the
device, then confirm the keyguard is no longer showing and restore responsive
foreground Flutter. This completes manual button coverage. The explicit lock
task's inability to automatically restore through a secure keyguard is expected
device behavior, not an input-delivery failure. Default smoke can then run
Home-only coverage without repeating the power sequence.

The simulator lock task's restoration swipe defaults to the portrait iPhone 17
Pro fixture used in S48. For another screen size/orientation, explicitly set
`UNLOCK_FROM=x,y UNLOCK_TO=x,y` to valid lock-screen swipe coordinates before
running the lock task. Inspect Home/lock/wake/restored captures for OS semantics;
delivery tokens alone do not prove the final screen state.

For a physical Android already left secure-locked by a test, the minimal
verification is read-only, using its exact serial: inspect
`adb -s <serial> shell dumpsys power` and
`adb -s <serial> shell dumpsys window policy`. Awake plus `secure=true` and
`showing=true` verifies an awake secure keyguard; use an OS screenshot if
available to check the visible screen. Preserve the earlier sleep power dump
and delivery output as evidence of the first press. These reads do not complete
app-restoration coverage. Ask the user to unlock on-device, then relaunch the
app and verify foreground `fdb describe` before resuming smoke. Do not press
power again to resolve uncertain delivery or attempt passcode unlocking.

## Test Output Conventions

Each test task prints:
- `PASS: fdb <command>` on success.
- `FAIL: fdb <command> - <reason>` on failure (to stderr, exits 1).

## Adding Tests for New Commands

1. Add a `test:your-command` task to `Taskfile.yml` following the existing pattern.
2. Add the new task to the `smoke` task sequence.
3. Run `task test:your-command` and confirm `PASS` before opening a PR.
