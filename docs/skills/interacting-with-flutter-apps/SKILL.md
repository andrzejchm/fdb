---
name: interacting-with-flutter-apps
description: Interacts with running Flutter apps on physical devices and simulators via fdb (Flutter Debug Bridge) CLI. Launches apps, hot reloads/restarts, takes screenshots, reads logs, inspects widget trees, and toggles widget selection. Use when launching a Flutter app on device, hot reloading after code changes, taking device screenshots, reading app logs, inspecting the widget hierarchy, debugging UI on device, or killing a running Flutter app.
license: MIT
compatibility: opencode
---

## Install

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Verify: `fdb status`

## Commands

### List devices

```bash
fdb devices
```

Output (one line per device):
```
DEVICE_ID=<id> NAME=<name> PLATFORM=<targetPlatform> EMULATOR=<true|false>
```

Lists all devices Flutter can target: physical phones, emulators, simulators, desktop, and web.

### Launch app

```bash
fdb launch --device <device_id> --project <path> [--flavor <flavor>] [--target <target>]
```

Output: `APP_STARTED`, `VM_SERVICE_URI=...`, `PID=...`, `LOG_FILE=...`

Find device IDs: `fdb devices`

### Hot reload / restart

```bash
fdb reload    # SIGUSR1 - preserves state
fdb restart   # SIGUSR2 - resets state
```

### Screenshot

```bash
fdb screenshot [--output <path>]
```

Auto-detects Android (`adb screencap`) vs iOS simulator (`xcrun simctl io screenshot`). Default output: `/tmp/fdb_screenshot.png`. Read the file with the Read tool to view it.

### Logs

```bash
fdb logs --tag "MyTag" --last 50
fdb logs --tag "DEBUG" --last 100
```

Reads from the tee'd log file. Use `--tag` to grep for specific tags.

### Widget tree

```bash
fdb tree --depth 5
fdb tree --depth 3 --user-only
```

Connects to VM service, prints indented widget tree. `--user-only` filters to project widgets.

NOTE: If this returns empty/unknown, fall back to raw websocat (see Fallback section).

### Widget selection

```bash
fdb select on     # enable tap-to-select overlay on device
fdb select off    # disable overlay
fdb selected      # get what widget was tapped
```

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up temp files
```

## Deep links

Not part of fdb. Use platform commands directly:

```bash
# Android
adb -s <serial> shell am start -a android.intent.action.VIEW \
  -n <package>/<activity> -d "<url>"

# iOS simulator (may open Safari instead of app)
xcrun simctl openurl <device_uuid> "<url>"
```

Find Android package: `adb shell pm list packages | grep <app_name>`

## Adding investigative logging

When debugging, add `debugPrint()` calls (NOT `log()` from `dart:developer`):
- `debugPrint` goes to stdout (visible in log file)
- `dart:developer` `log()` goes to DevTools only (invisible in log file)

Use consistent tags: `debugPrint('[Feature-DEBUG] message')`, then filter with `fdb logs --tag "Feature-DEBUG"`.

## Webview debugging

For webview issues, inject diagnostic JS via `controller.evaluateJavascript()`:
- In `onWebviewCreated` - runs before page loads
- In `onPageFinishedLoading` - runs after page is ready

Wire up all webview callbacks for logging: `onConsoleMessage`, `onReceivedError`, `onReceivedHttpError`, `onNavigationResponse`, `onCreateWindow`.

Use `agent-browser --headed` for testing webview behavior in a real browser with JS injection.

## Fallback: raw websocat

If fdb's VM service commands fail, use websocat directly:

```bash
# Get VM service URI
VM_URI=$(fdb status 2>/dev/null | grep VM_SERVICE_URI | cut -d= -f2)

# Get isolate IDs
echo '{"jsonrpc":"2.0","method":"getVM","params":{},"id":"1"}' \
  | websocat -n1 -B 10485760 "$VM_URI"

# Widget tree (use the second isolate if first returns null)
echo '{"jsonrpc":"2.0","method":"ext.flutter.inspector.getRootWidgetSummaryTree","params":{"isolateId":"isolates/<ID>","objectGroup":"g"},"id":"2"}' \
  | websocat -n1 -B 10485760 "$VM_URI"

# Enable widget selection
echo '{"jsonrpc":"2.0","method":"ext.flutter.inspector.show","params":{"isolateId":"isolates/<ID>","enabled":"true"},"id":"3"}' \
  | websocat -n1 "$VM_URI"

# Get selected widget
echo '{"jsonrpc":"2.0","method":"ext.flutter.inspector.getSelectedSummaryWidget","params":{"isolateId":"isolates/<ID>","objectGroup":"g"},"id":"4"}' \
  | websocat -n1 -B 1048576 "$VM_URI"
```

Key gotcha: apps have multiple isolates. Try each until one returns a non-null widget tree. Use `-B 10485760` for large responses.

## State files

All state lives in `/tmp/`:
- `/tmp/fdb.pid` - flutter run process ID
- `/tmp/fdb_logs.txt` - full app output
- `/tmp/fdb_vm_uri.txt` - VM service websocket URI
- `/tmp/fdb_screenshot.png` - last screenshot
