## fdb skill: launch

Session lifecycle commands — devices, launch, attach, doctor, reload, status, kill, deeplinks, and state files.

## Contents
- Best practices
- List devices
- Launch app
- Launch error categories
- Attach to a running app
- Doctor pre-flight check
- Hot reload / restart
- Status / Kill
- Deep links
- State files

## Best practices

- Always run `fdb doctor` at the start of an interaction session to confirm the app is alive, the VM service is reachable, and `fdb_helper` is registered.
- `fdb kill` before re-launching to avoid stale PID / URI files from a previous session.
- Use `fdb attach` (not `fdb launch`) whenever the app must be started by native tooling (Xcode, Android Studio, Firebase DebugView, `simctl`, `adb shell am start`). Launching from fdb in those cases fights the native tooling.
- Add `fdb_helper` to the app for reliable `fdb attach` auto-discovery — without it, fdb must parse Flutter's raw log output, whose format has changed across SDK versions.
- Use a custom URL scheme (not Universal Links) for `fdb deeplink` tests — `https://` links may open Safari on the iOS simulator.

## List devices

```bash
fdb devices
```

Output (one line per device):
```
DEVICE_ID=<id> NAME=<name> PLATFORM=<targetPlatform> EMULATOR=<true|false>
```

Lists all devices Flutter can target: physical phones, emulators, simulators, desktop, and web.

## Launch app

```bash
fdb launch --device <device_id> --project <path> [--flavor <flavor>] [--target <target>]
```

Output on success: `APP_STARTED`, `VM_SERVICE_URI=...`, `PID=...`, `LOG_FILE=...`

Output on failure (process exited before VM service appeared):
```
ERROR: flutter process exited unexpectedly
LAUNCH_ERROR=<CATEGORY>
LAUNCH_ERROR_CAUSE=<one-line description>
HINT: <remediation hint>          # omitted when category is UNKNOWN
--- log context ---
L42: <most informative log lines>
---
```

## Launch error categories

| Category | Meaning |
|---|---|
| `IOS_BUNDLE_ID_CLAIMED` | Bundle ID registered to a different team — change or reclaim it |
| `IOS_NO_ACCOUNT_FOR_TEAM` | Apple ID for the Xcode team is not signed in on this Mac |
| `IOS_CODESIGN_PROVISIONING` | Code signing or provisioning profile failure (may include keychain issues) |
| `IOS_BUILD_SCRIPT` | An Xcode build script phase failed (CocoaPods embed, etc.) |
| `ANDROID_INSTALL_ADB` | ADB install failed — incompatible signatures, storage, or device offline |
| `SDK_TOOLCHAIN` | Flutter SDK, Android SDK, or Xcode toolchain is missing or misconfigured |
| `FLUTTER_BUILD` | Dart/Gradle compile error — fix the first error and retry |
| `UNKNOWN` | No recognised pattern matched — open LOG_FILE for full output |

Find device IDs: `fdb devices`

## Attach to a running app

```bash
fdb attach --device <device_id> --project <path> [--app-id <bundle_or_package>] [--debug-url <vm_service_url>]
```

Output on success: `APP_ATTACHED`, `VM_SERVICE_URI=...`, `PID=...`, `LOG_FILE=...`

Use `attach` when the app must be started by native tooling first, such as Xcode, Android Studio, `simctl`, or `adb`. The target app must be a debug/profile Flutter app exposing the Dart VM service.

**Auto-discovery** — when `--debug-url` is omitted fdb scans device logs to find the VM service URI automatically:

| Platform | Discovery method |
|---|---|
| **Android** (physical + emulator) | `adb logcat` + automatic `adb forward` for the VM port |
| **iOS Simulator** | `xcrun simctl spawn <udid> log show --last 5m` |
| **Physical iOS** | `idevicesyslog archive --age-limit 300` + `log show --archive` — looks back up to 5 minutes (`brew install libimobiledevice` required) |
| **macOS / Linux / Windows** | Not supported — pass `--debug-url` manually |

For more reliable discovery, add `fdb_helper` to the app — it emits a stable `[FDB_VM_URI]` log marker at startup that fdb prefers over Flutter's own output (whose format has changed several times across versions).

**Firebase Analytics DebugView / GA4 workflow:**

```text
Xcode -> Product -> Scheme -> Edit Scheme -> Run -> Arguments
Add: -FIRDebugEnabled
Optional console logging: -FIRAnalyticsDebugEnabled
```

Launch from Xcode, then run:

```bash
fdb attach --device <ios_device_or_simulator_id> --project <path> --app-id <bundle_id>
```

fdb will auto-discover the VM service URI from the simulator/device log.

If auto-discovery fails or the platform is unsupported, copy the Dart VM service URL from Xcode, `flutter logs`, or `fdb status`. Both `http://.../` and `ws://.../ws` forms are accepted:

```bash
fdb attach --device <device_id> --project <path> --debug-url <vm_service_url>
```

## Doctor pre-flight check

```bash
fdb doctor
```

Run this before an interaction session to validate that the app is running, the VM service is reachable, `fdb_helper` is registered, and platform tools are present. Prints `DOCTOR_SUMMARY=pass|fail CHECKS=<n> FAILED=<n>`.

Example output:
```
DOCTOR_CHECK=app_running STATUS=pass
DOCTOR_CHECK=vm_service STATUS=pass VM_SERVICE_URI=ws://127.0.0.1:56789/ws
DOCTOR_CHECK=fdb_helper STATUS=pass
DOCTOR_CHECK=platform_tools STATUS=warn TOOLS=xcrun,screencapture MISSING=adb HINT=adb missing — Android screenshots and interactions will fail. Install Android platform-tools.
DOCTOR_CHECK=device STATUS=pass DEVICE_ID=macos PLATFORM=darwin-x64
DOCTOR_SUMMARY=pass CHECKS=5 FAILED=0
```

Warnings do not make the summary fail. Failed checks include `HINT=...` remediation text. The command always exits `0` — parse the summary token instead of the exit code.

## Hot reload / restart

```bash
fdb reload    # SIGUSR1 - preserves state
fdb restart   # SIGUSR2 - resets state
```

Use `reload` to pick up Dart code changes without losing widget state. Use `restart` after changing `initState` or app startup logic.

## Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up temp files
```

fdb auto-locates the active `.fdb/` session by walking up from the current directory — no need to `cd` to the project root. Use `--session-dir` to override:

```bash
fdb --session-dir /path/to/project/.fdb status
```

## Deep links

```bash
fdb deeplink <url>
```

Opens a deep link URL on the connected device. Works with Android and iOS simulators only.

```bash
fdb deeplink "myapp://products/123"
fdb deeplink "https://example.com/products/123?ref=home"
```

Output on success: `DEEPLINK_OPENED=<url>`

**Limitations:**
- Physical iOS not supported (Apple has no CLI for this)
- Desktop and web not supported
- On iOS simulator, Universal Links (`https://`) may open Safari — use a custom URL scheme for reliable testing

## State files

All state lives in `<project>/.fdb/`. fdb resolves this automatically by walking up from CWD. Pass `--session-dir <path>` to bypass.

- `.fdb/fdb.pid` — flutter-tools process ID (fallback for teardown)
- `.fdb/fdb.app_pid` — app VM process ID from `getVM` (used for liveness detection)
- `.fdb/controller.pid` — long-lived fdb controller process ID
- `.fdb/controller.port` — loopback port for controller requests
- `.fdb/controller.token` — per-session controller auth token
- `.fdb/log_collector.pid` — detached log collector process ID
- `.fdb/logs.txt` — full app output
- `.fdb/vm_uri.txt` — VM service websocket URI
- `.fdb/device.txt` — device ID used at launch
- `.fdb/platform.txt` — target platform + emulator flag (read by screenshot, syslog, crash-report, grant-permission)
- `.fdb/app_id.txt` — bundle id / package name (read by crash-report, simulator, grant-permission)
- `.fdb/screenshot.png` — last screenshot
