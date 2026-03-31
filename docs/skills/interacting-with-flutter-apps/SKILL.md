---
name: interacting-with-flutter-apps
description: Interacts with running Flutter apps on physical devices and simulators via fdb (Flutter Debug Bridge) CLI. Launches apps, hot reloads/restarts, takes screenshots, reads logs, inspects widget trees, toggles widget selection, taps widgets, enters text, and scrolls. Use when launching a Flutter app on device, hot reloading after code changes, taking device screenshots, reading app logs, inspecting the widget hierarchy, debugging UI on device, tapping widgets, entering text into fields, scrolling the screen, or killing a running Flutter app.
license: MIT
compatibility: opencode
---

## Install

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Verify: `fdb status`

## fdb_helper setup (required for tap, input, scroll)

The `tap`, `input`, and `scroll` commands require `fdb_helper` to be added to the Flutter app under test.

**`pubspec.yaml`:**
```yaml
dev_dependencies:
  fdb_helper:
    git:
      url: https://github.com/andrzejchm/fdb.git
      path: packages/fdb_helper
```

**`main.dart`:**
```dart
import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/foundation.dart';

void main() {
  if (!kReleaseMode) {
    FdbBinding.ensureInitialized();
  }
  runApp(MyApp());
}
```

After adding `fdb_helper`, run `flutter pub get` and relaunch the app.

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

Output tokens:
```
WAITING...          (repeated heartbeat while waiting for the app to start)
APP_STARTED
VM_SERVICE_URI=<uri>
PID=<pid>
LOG_FILE=<path>
```

On failure: `ERROR: Launch timed out after N seconds` (stderr).

Find device IDs: `fdb devices`

The `--device` flag is accepted by all commands that need to identify the active session. When only one session is active it can be omitted.

### Hot reload / restart

```bash
fdb reload    # SIGUSR1 - preserves state
fdb restart   # SIGUSR2 - resets state
```

Output tokens on success: `RELOADED in <ms>ms` / `RESTARTED in <ms>ms`

On failure: `ERROR: RELOAD_FAILED` / `ERROR: RESTART_FAILED` (stderr).

### Screenshot

```bash
fdb screenshot [--output <path>]
```

Auto-detects the platform and uses the appropriate native tool:
- Android: `adb screencap`
- iOS simulator: `xcrun simctl io screenshot`
- macOS desktop: `screencapture`
- Linux X11: `xdotool` + `import`
- Web/Chrome: Chrome DevTools Protocol (CDP)
- Physical iOS, Windows, Linux Wayland: `fdb_helper` VM service extension (requires `fdb_helper` in the app)

Default output: `~/.fdb/sessions/<hash>/screenshot.png`. Read the file with the Read tool to view it.

Output tokens on success:
```
SCREENSHOT_SAVED=<path>
SIZE=<size>
```

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

`fdb selected` output tokens:
```
SELECTED: <widget description> (<file>:<line>)   # when creation location is known
SELECTED: <widget description>                    # when creation location is unknown
NO_WIDGET_SELECTED                                # when no widget has been tapped yet
```

### Tap a widget

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb tap --key "increment_button"      # tap by widget key
fdb tap --text "Submit"               # tap by visible text
fdb tap --type "FloatingActionButton" # tap by widget type
```

Output: `TAPPED=<type> X=<x> Y=<y>`

### Enter text

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb input --key "search_field" "flutter"   # type into field by key
fdb input --text "Search" "query text"     # type into field by label text
fdb input "fallback text"                  # type into focused field
```

Output: `INPUT=<type> VALUE=<text>`

### Scroll

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb scroll down              # scroll down
fdb scroll up                # scroll up
fdb scroll left              # scroll left
fdb scroll right             # scroll right
fdb scroll down --at 200,400 # scroll at specific screen coordinates
```

Output: `SCROLLED=<DIR> DISTANCE=<n>`

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up session files
```

## Deep links

```bash
fdb deeplink <url>
```

Opens a deep link URL on the connected device. Works with Android devices and iOS simulators only.

```bash
# Custom scheme
fdb deeplink "myapp://products/123"

# Universal Link / App Link
fdb deeplink "https://example.com/products/123?ref=home"
```

Output on success: `DEEPLINK_OPENED=<url>`

**Limitations:**
- Physical iOS devices are not supported (Apple does not expose a CLI for opening URLs on physical devices)
- On iOS simulator, Universal Links (`https://`) may open Safari instead of the app. Use a custom URL scheme for reliable testing

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

## Agent patterns

```bash
# Standard launch + inspect workflow
DEVICE=$(fdb devices 2>/dev/null | grep '^DEVICE_ID=' | head -1 | sed 's/DEVICE_ID=\([^ ]*\).*/\1/')
fdb launch --device "$DEVICE" --project /path/to/flutter/app
fdb tree --depth 5 --user-only
fdb screenshot

# Widget interaction workflow (requires fdb_helper in the app)
fdb tap --key "submit_button"              # tap a button
fdb screenshot                             # verify result visually
fdb input --key "search_field" "flutter"   # type into a text field
fdb tap --text "Search"                    # tap the search button
fdb scroll down                            # scroll to reveal more content
fdb logs --tag "fdb_test" --last 20        # check logs after interaction

# Form fill workflow
fdb tap --key "username_field"
fdb input --key "username_field" "testuser"
fdb tap --key "password_field"
fdb input --key "password_field" "secret"
fdb tap --text "Login"
fdb screenshot
```

## State files

All state lives in `~/.fdb/`:
- `~/.fdb/sessions/<hash>/session.json` - active session state (PID, VM URI, device, project)
- `~/.fdb/sessions/<hash>/logs.txt` - full app output
- `~/.fdb/sessions/<hash>/screenshot.png` - last screenshot
- `~/.fdb/devices.json` - cached device list
