---
name: using-fdb
description: Uses fdb (Flutter Debug Bridge) CLI to interact with running Flutter apps on devices and simulators. Launches, hot reloads, screenshots, reads app logs (`fdb logs`) and native system logs (`fdb syslog` — Android logcat, iOS syslog, macOS log), inspects widget trees, describes screens including off-screen GridView/ListView children, and taps/inputs/scrolls/swipes/navigates. Use when launching a Flutter app on device, hot reloading, taking screenshots, reading app or native system logs, diagnosing native crashes (jetsam, LMK), inspecting or describing the UI, or interacting with widgets via fdb.
license: MIT
compatibility: opencode
---

## Overview - skill version 1.3.0

> **Version check:** Run `fdb --version`. This skill may describe unreleased branch behavior,
> so do not assume the published `1.3.0` release includes every command example below. To use
> the latest behavior from this repository,
> update with `dart pub global activate --source git https://github.com/andrzejchm/fdb.git`
> and refresh this skill with `fdb skill`.

## Install

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Verify: `fdb status`

## fdb_helper setup (required for tap, double-tap, longpress, input, scroll, scroll-to, back)

The `tap`, `double-tap`, `longpress`, `input`, `scroll`, `scroll-to`, and `back` commands require `fdb_helper` to be added to the Flutter app under test.

**`pubspec.yaml`:**
```yaml
dev_dependencies:
  fdb_helper: ^1.3.0
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

### Doctor pre-flight check

```bash
fdb doctor
```

Run this before an interaction session when you need to validate that the app is running and the environment is usable. It checks the fdb installation health, app process, VM service, `fdb_helper`, platform tools, and stored device state, then prints `DOCTOR_SUMMARY=pass|fail CHECKS=<n> FAILED=<n>`.

Example output:
```
DOCTOR_CHECK=fdb_install STATUS=pass
DOCTOR_CHECK=app_running STATUS=pass
DOCTOR_CHECK=vm_service STATUS=pass VM_SERVICE_URI=ws://127.0.0.1:56789/ws
DOCTOR_CHECK=fdb_helper STATUS=pass
DOCTOR_CHECK=platform_tools STATUS=warn TOOLS=xcrun,screencapture MISSING=adb HINT=adb missing — Android screenshots and interactions will fail. Install Android platform-tools.
DOCTOR_CHECK=device STATUS=pass DEVICE_ID=macos PLATFORM=darwin-x64
DOCTOR_SUMMARY=pass CHECKS=6 FAILED=0
```

Warnings do not make the summary fail. Failed checks include `HINT=...` remediation text. The command always exits `0`, so parse the summary instead of relying on the process exit code.

### Hot reload / restart

```bash
fdb reload    # SIGUSR1 - preserves state
fdb restart   # SIGUSR2 - resets state
```

### Screenshot

```bash
fdb screenshot [--output <path>] [--full]
```

Dispatches to the right capture tool per platform: `adb` (Android), `xcrun simctl` (iOS simulator), `screencapture` (macOS), `xdotool`+`import` (Linux X11), Chrome DevTools Protocol (web), or `fdb_helper` VM extension (physical iOS, Windows, Wayland). Default output: `<project>/.fdb/screenshot.png`. Output is downscaled so the longest side fits within 1200px — pass `--full` to skip. Read the file with the Read tool to view it.

### Logs

```bash
fdb logs --tag "MyTag" --last 50
fdb logs --tag "DEBUG" --last 100
```

Reads from the tee'd log file. Use `--tag` to grep for specific tags.

### Native system logs (Android logcat / iOS syslog / macOS log)

```bash
fdb syslog --since 5m --last 50            # last 50 lines from the past 5 minutes
fdb syslog --predicate jetsam              # filter by substring
fdb syslog --follow                        # stream live, exits on Ctrl-C
```

Use this to diagnose native crashes that don't reach Crashlytics or appear in `fdb logs` — iOS jetsam kills, Android low-memory-killer events, kernel-level errors. Dispatches per platform: `adb logcat` (Android), `xcrun simctl spawn <udid> log` (iOS simulator), `idevicesyslog` (iOS physical, requires `brew install libimobiledevice`), or host `log` (macOS).

Flags:
- `--since <duration>` — time window (`30s`, `5m`, `1h`); default `5m`. Not valid with `--follow`.
- `--predicate <substring>` — substring match across platforms (post-filtered for adb / idevicesyslog, native NSPredicate for `log show`).
- `--last <n>` — cap output to last N lines. Not valid with `--follow`.
- `--follow` — stream live, exit cleanly on Ctrl-C.

Output is the raw native log format — not parsed into fdb tokens. Errors print `ERROR: ...` (e.g. `ERROR: idevicesyslog not found. Install: brew install libimobiledevice`).

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

### Tap native UI (system dialogs, permission sheets)

Use this when a native OS dialog is blocking the Flutter UI — iOS permission
prompts, Android runtime-permission sheets. Unlike `fdb tap`, this command
does NOT go through Flutter's GestureBinding.

```bash
fdb native-tap --at 200,400    # tap at device coordinates (x,y)
fdb native-tap --x 200 --y 400 # same, two-flag form
```

Output: `NATIVE_TAPPED=<platform> X=<x> Y=<y>`

Platform dispatch:
- **Android** — `adb shell input tap X Y`. Coordinates in Android dp (= Flutter logical pixels). No extra setup needed.
- **iOS simulator** — IndigoHID via SimulatorKit private framework. No extra tools required.
- **iOS physical** — **not yet supported.** Out-of-process tap injection on physical iOS requires WebDriverAgent (signed XCUITest runner installed on the device). Use `fdb tap --at` instead — it performs in-process tap injection via `fdb_helper` and reaches in-app native overlays (UIAlertController, etc.) on physical iOS devices.
- **macOS** — **not supported.** Out-of-process click injection on macOS requires Accessibility permission, which the system only grants to signed `.app` bundles. Homebrew CLIs (cliclick, opencode, tmux) are unsigned binaries and cannot receive Accessibility permission on macOS Sequoia/Tahoe. Use `fdb tap --at` instead — it performs in-process tap injection via `fdb_helper` and does not require any system permissions.

Workflow for dismissing an iOS permission prompt:
```bash
fdb screenshot                          # see where the "Allow" button is
fdb native-tap --at 196,600            # tap "Allow" at its coordinates
fdb screenshot                          # confirm dialog dismissed
```

### Tap a widget

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb tap --key "increment_button"      # tap by widget key
fdb tap --text "Submit"               # tap by visible text
fdb tap --type "FloatingActionButton" # tap by widget type
fdb tap --at 200,400                   # tap absolute screen coordinates
fdb tap @3                            # tap by describe ref (from fdb describe)
```

Output: `TAPPED=<type|coordinates> X=<x> Y=<y>`

### Long-press a widget

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb longpress --key "photo_card"              # long-press by widget key (default 500ms)
fdb longpress --text "Hold me"               # long-press by visible text
fdb longpress --type "GestureDetector"       # long-press by widget type
fdb longpress --key "item" --duration 1000   # long-press for 1 second
fdb longpress --at 200,400 --duration 1000   # long-press coordinates for 1 second
```

Output: `LONG_PRESSED=<type|coordinates> X=<x> Y=<y>`

### Double-tap a widget

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb double-tap --key "map_widget"         # double-tap by widget key
fdb double-tap --text "Zoom here"         # double-tap by visible text
fdb double-tap --type "InteractiveViewer" # double-tap by widget type
fdb double-tap --type "InteractiveViewer" --index 1 # choose a specific match
fdb double-tap --x 200 --y 400             # double-tap at screen coordinates
fdb double-tap --at 200,400                # shorthand for --x/--y
```

Output: `DOUBLE_TAPPED=<type> X=<x> Y=<y>`

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

### Scroll to widget

Requires `fdb_helper` in the app (see setup section above).

Scrolls the nearest Scrollable until the target widget becomes visible. Works for lazy lists (ListView.builder) where off-screen widgets don't exist in the element tree yet.

```bash
fdb scroll-to --key "list_item_42"        # scroll until widget with key is visible
fdb scroll-to --text "Item 42"            # scroll until widget with text is visible
fdb scroll-to --type "MyListItemWidget"   # scroll until widget of type is visible
fdb scroll-to --type "ListTile" --index 5 # scroll to the 6th ListTile (0-based)
```

Output: `SCROLLED_TO=<type> X=<x> Y=<y>`

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

### Clean app data

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb clean
```

Deletes all files inside the app's temporary directory (cache) and application support/documents directories. Useful before running a test scenario that requires a clean slate. The app keeps running — no restart needed.

Output: `CLEANED`, `DIRS=<comma-separated paths>`, `DELETED_ENTRIES=<count>`

### SharedPreferences

Requires `fdb_helper` in the app (see setup section above).

```bash
fdb shared-prefs get <key>                          # read one key
fdb shared-prefs get-all                            # dump all keys+values as JSON
fdb shared-prefs set <key> <value>                  # write string (default)
fdb shared-prefs set <key> <value> --type bool      # write bool
fdb shared-prefs set <key> <value> --type int       # write int
fdb shared-prefs set <key> <value> --type double    # write double
fdb shared-prefs remove <key>                       # delete one key
fdb shared-prefs clear                              # delete all keys
```

Output tokens: `PREF_VALUE=<v>`, `PREF_NOT_FOUND`, `PREF_ALL=<json>`, `PREF_ENTRY=<key>=<value>`, `PREF_SET=<key>`, `PREF_REMOVED=<key>`, `PREF_CLEARED`

Use `get-all` to inspect current state before a test. Use `set` to seed feature flags or skip onboarding. Use `clear` to reset app state to first-run.

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up temp files
```

fdb auto-locates the active `.fdb/` session by walking up from the current directory, so you can run any command from a subdirectory without switching to the project root. Use `--session-dir` to override:

```bash
fdb --session-dir /path/to/project/.fdb status   # explicit session directory
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
fdb wait --key "loading_spinner" --absent  # wait in-app instead of shell sleep loops
fdb scroll down                            # scroll to reveal more content
fdb scroll-to --key "list_item_42"         # scroll until a specific item is visible
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

## Troubleshooting

**Cryptic `directory does not exist` on every fdb invocation** — fdb was installed via `dart pub global activate --source path <dir>` and the source directory was later deleted (e.g. a removed git worktree). Dart cannot load the script before fdb's `main()` runs. Fix:

```bash
dart pub global deactivate fdb
dart pub global activate fdb
# or for latest: dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

## State files

All state lives in `<project>/.fdb/`. fdb resolves this directory automatically by walking up from the current working directory to the nearest ancestor that contains a live `.fdb/` — so you never need to `cd` to the project root before running a command. Pass `--session-dir <path>` to bypass auto-resolution entirely.
- `<project>/.fdb/fdb.pid` - flutter-tools process ID (the `flutter run` Dart VM, used for SIGUSR1/SIGUSR2 hot reload/restart and to tear down the session)
- `<project>/.fdb/fdb.app_pid` - app VM process ID from `getVM` (the actual Dart VM hosting your app, used for liveness detection on a macOS desktop target)
- `<project>/.fdb/logs.txt` - full app output
- `<project>/.fdb/vm_uri.txt` - VM service websocket URI
- `<project>/.fdb/device.txt` - device ID used at launch
- `<project>/.fdb/platform.txt` - target platform + emulator flag (written at launch, read by screenshot and syslog)
- `<project>/.fdb/screenshot.png` - last screenshot
