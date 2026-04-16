---
name: interacting-with-flutter-apps
description: Interacts with running Flutter apps on physical devices and simulators via fdb (Flutter Debug Bridge) CLI. Launches apps, hot reloads/restarts, takes screenshots, reads logs, inspects widget trees, toggles widget selection, taps widgets, long-presses widgets, enters text, scrolls, and navigates back. Use when launching a Flutter app on device, hot reloading after code changes, taking device screenshots, reading app logs, inspecting the widget hierarchy, debugging UI on device, tapping widgets, long-pressing widgets, entering text into fields, scrolling the screen, navigating back to a previous screen, or killing a running Flutter app.
license: MIT
compatibility: opencode
---

## Overview - skill version 1.1.1

> **Version check:** Run `fdb --version`. If your installed version is older than 1.1.1,
> update with `dart pub global activate --source git https://github.com/andrzejchm/fdb.git`
> and refresh this skill with `fdb skill`.

## Install

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Verify: `fdb status`

## fdb_helper setup (required for tap, longpress, input, scroll, back)

The `tap`, `longpress`, `input`, and `scroll` commands require `fdb_helper` to be added to the Flutter app under test.

**`pubspec.yaml`:**
```yaml
dev_dependencies:
  fdb_helper: ^1.1.1
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

### Describe the current screen

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb describe
```

Returns a compact, text-based snapshot of what's on screen — interactive elements with stable refs and all visible text. Use this instead of a screenshot when you need to understand the UI and interact with it.

Example output:
```
SCREEN: HomeScreen
ROUTE: /home

INTERACTIVE:
  @1 ElevatedButton "Start" key=start_btn
  @2 IconButton key=nav_back
  @3 TextField "Search" key=search_field
  @4 FloatingActionButton key=fab_add

TEXT:
  "Welcome"
  "3 items"
```

Refs are NOT stable across navigation changes — re-run `fdb describe` after navigating.

### Widget selection

```bash
fdb select on     # enable tap-to-select overlay on device
fdb select off    # disable overlay
fdb selected      # get what widget was tapped
```

### Tap a widget

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb tap --key "increment_button"      # tap by widget key
fdb tap --text "Submit"               # tap by visible text
fdb tap --type "FloatingActionButton" # tap by widget type
fdb tap @3                            # tap by describe ref (from fdb describe)
```

Output: `TAPPED=<type> X=<x> Y=<y>`

### Long-press a widget

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb longpress --key "photo_card"              # long-press by widget key (default 500ms)
fdb longpress --text "Hold me"               # long-press by visible text
fdb longpress --type "GestureDetector"       # long-press by widget type
fdb longpress --key "item" --duration 1000   # long-press for 1 second
```

Output: `LONG_PRESSED=<type> X=<x> Y=<y>`

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

### Swipe (PageView, Dismissible)

Requires `fdb_helper` in the app (see setup section above).

Use `swipe` when you need to trigger PageView page changes, Dismissible dismissals, or any gesture that requires crossing a snap/dismiss threshold. Unlike `scroll`, `swipe` can target a specific widget and automatically uses 60% of the widget's dimension as the default distance — enough to cross most snap thresholds.

```bash
fdb swipe left --key "photo_card"         # swipe widget left by key
fdb swipe right --text "Next"             # swipe widget right by text
fdb swipe up --type "Dismissible"         # swipe widget up by type
fdb swipe left                            # swipe from screen center (fallback)
fdb swipe left --at 200,400              # swipe from specific coordinates
fdb swipe left --distance 400            # swipe with custom pixel distance
```

Output: `SWIPED=<DIR> DISTANCE=<n>`

### Navigate back

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb back
```

Calls `Navigator.maybePop()` on the root navigator. Returns `POPPED` on success, or an error if already at the root route.

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up temp files
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
- Desktop and web targets are not supported
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
fdb describe                               # compact screen snapshot — preferred over screenshot for navigation
fdb tree --depth 5 --user-only
fdb screenshot

# Describe-driven interaction workflow (requires fdb_helper in the app)
fdb describe                               # see what's on screen + get refs
fdb tap @1                                 # tap the first interactive element by ref
fdb tap @3                                 # tap the third interactive element by ref
fdb describe                               # re-describe after navigation to get fresh refs

# Widget interaction workflow (requires fdb_helper in the app)
fdb tap --key "submit_button"              # tap a button
fdb longpress --key "photo_card"           # long-press to open context menu
fdb screenshot                             # verify result visually
fdb input --key "search_field" "flutter"   # type into a text field
fdb tap --text "Search"                    # tap the search button
fdb scroll down                            # scroll to reveal more content
fdb swipe left --key "photo_card"          # swipe a PageView card left
fdb swipe right                            # swipe from screen center right
fdb back                                   # navigate back to previous screen
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

All state lives in `/tmp/`:
- `/tmp/fdb.pid` - flutter run process ID
- `/tmp/fdb_logs.txt` - full app output
- `/tmp/fdb_vm_uri.txt` - VM service websocket URI
- `/tmp/fdb_screenshot.png` - last screenshot
