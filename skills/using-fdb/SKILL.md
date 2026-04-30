---
name: using-fdb
description: Uses fdb (Flutter Debug Bridge) CLI to interact with running Flutter apps on devices and simulators. Launches, hot reloads, screenshots, reads app logs (`fdb logs`) and native system logs (`fdb syslog` — Android logcat, iOS syslog, macOS log), fetches OS-level crash records (`fdb crash-report` — jetsam, LMK, native .ips), inspects widget trees, describes screens including off-screen GridView/ListView children, taps/inputs/scrolls/swipes/navigates, forces garbage collection (`fdb gc`), and grants/revokes/resets runtime permissions (`fdb grant-permission`). Use when launching a Flutter app on device, hot reloading, taking screenshots, reading app or native system logs, diagnosing native crashes (jetsam, LMK), fetching post-mortem crash reports, inspecting or describing the UI, interacting with widgets via fdb, forcing a GC to disambiguate live-retained vs unreachable-but-uncollected memory, or pre-granting runtime permissions (camera, microphone, location, etc.) before running automated tests.
license: MIT
compatibility: opencode
---

Run `fdb skill` and read its full stdout output before doing anything with fdb.
That output is the authoritative, version-matched reference for every command, flag, and output token.

## grant-permission

Grant, revoke, or reset a runtime permission for the running Flutter app.

```bash
# Grant a permission (iOS simulator or Android)
fdb grant-permission camera
# stdout: PERMISSION_GRANTED=camera

# Revoke a permission
fdb grant-permission --revoke camera
# stdout: PERMISSION_REVOKED=camera

# Reset a single permission (re-prompts on next access)
fdb grant-permission --reset camera
# stdout: PERMISSION_RESET=camera

# Reset ALL permissions for the app
fdb grant-permission --reset-all
# stdout: PERMISSION_RESET_ALL=true

# Override bundle ID / package name
fdb grant-permission --bundle com.example.app camera
```

Supported tokens: `camera`, `microphone`, `location`, `location-always`, `contacts`, `contacts-read`, `photos`, `photos-add`, `calendar`, `reminders`, `motion`, `media-library`, `siri` (iOS), `notifications` (Android), `screen-capture` (macOS).

Notes:
- iOS simulator only — physical iOS devices are not supported.
- macOS supports `--reset` only; grant/revoke emit `WARNING:` and exit 1.
- On iOS simulator, a successful grant emits `WARNING: Permission change may have terminated the app. Run \`fdb reload\` or \`fdb launch\` to restart.` on stderr.
