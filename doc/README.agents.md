# fdb for AI Agents

Guide for using fdb (Flutter Debug Bridge) with AI coding agents.

fdb is a CLI that lets AI agents launch, reload, screenshot, inspect, and kill Flutter apps running on physical devices and simulators.

## Installation

### 1. Install the CLI

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Requires Dart SDK >= 3.0.0. Ensure `~/.pub-cache/bin` is in your `PATH`.

### 2. Install the skill file (optional)

If your agent supports skill files (OpenCode, Claude Code, or similar), install for automatic discoverability:

**OpenCode:**
```bash
mkdir -p ~/.config/opencode/skills/using-fdb
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.config/opencode/skills/using-fdb/SKILL.md
```

**Claude Code:**
```bash
mkdir -p ~/.claude/skills/using-fdb
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.claude/skills/using-fdb/SKILL.md
```

Alternatively, run `fdb skill` to print the skill file contents directly.

For other agents, place the SKILL.md file wherever your agent reads skill definitions from, or simply use the commands below directly.

### 3. Verify

```bash
fdb status   # CLI installed and on PATH
```

Restart your agent after installing the skill file.

## Updating

```bash
# Update the CLI
dart pub global activate --source git https://github.com/andrzejchm/fdb.git

# Update the skill file (OpenCode)
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.config/opencode/skills/using-fdb/SKILL.md

# Update the skill file (Claude Code)
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/using-fdb/SKILL.md \
  -o ~/.claude/skills/using-fdb/SKILL.md
```

## Prerequisites

- Dart SDK >= 3.0.0
- Flutter SDK (for `flutter devices`, `flutter run`)
- A running iOS Simulator or Android emulator (or physical device)
- `adb` (Android), `xcrun` (iOS simulator), `screencapture` (macOS) on PATH for screenshots
- `xdotool` + ImageMagick `import` for Linux X11 screenshots (optional)
- Physical iOS / Windows / Linux Wayland screenshots use `fdb_helper` (no extra tool needed)

## Commands Reference

| Command | Description |
|---------|-------------|
| `fdb devices` | List connected devices |
| `fdb deeplink <url>` | Open deep link on device |
| `fdb launch --device <id> --project <path>` | Launch app, wait for start |
| `fdb doctor` | Pre-flight check for app, VM service, fdb_helper, platform tools, and device state |
| `fdb reload` | Hot reload (SIGUSR1) |
| `fdb restart` | Hot restart (SIGUSR2) |
| `fdb screenshot [--output <path>] [--full]` | Screenshot (all platforms; `--full` skips downscaling) |
| `fdb logs --tag <tag> --last <n>` | Filtered logs |
| `fdb tree --depth <n> [--user-only]` | Widget tree |
| `fdb describe` | Compact screen snapshot: interactive elements + visible text |
| `fdb select on/off` | Widget selection mode |
| `fdb selected` | Get selected widget |
| `fdb double-tap --text/--key/--type <selector> [--index N]` \| `--x X --y Y` \| `--at X,Y` | Double-tap a widget or screen coordinates |
| `fdb native-tap --at x,y` | Tap native (non-Flutter) UI — system dialogs, permission sheets (Android: adb; iOS sim: IndigoHID). **Physical iOS and macOS not supported** — use `fdb tap --at` instead. |
| `fdb tap --text/--key/--type <selector>`, `--at x,y`, or `@N` | Tap a widget, coordinates, or describe ref |
| `fdb longpress --text/--key/--type <selector> [--duration <ms>]` or `--at x,y` | Long-press a widget or coordinates |
| `fdb input [--text/--key/--type <selector>] <text>` | Enter text into field |
| `fdb scroll <direction> [--at x,y]` | Scroll screen |
| `fdb scroll-to --text/--key/--type <selector> [--index N]` | Scroll until widget is visible |
| `fdb wait --key/--text/--type/--route <selector> --present\|--absent [--timeout <ms>]` | Wait for UI state changes without manual polling loops |
| `fdb swipe <direction> [--key/--text/--type <selector>]` | Swipe widget (PageView, Dismissible) |
| `fdb back` | Navigate back (Navigator.maybePop) |
| `fdb status` | Check if app is running |
| `fdb kill` | Stop app |
| `fdb skill` | Print the AI agent skill file (SKILL.md) |
| `fdb --version` | Print the fdb version |

### Launch

```bash
fdb launch --device <device_id> --project <path> [--flavor <flavor>] [--target <target>]
```

Output: `APP_STARTED`, `VM_SERVICE_URI=...`, `PID=...`, `LOG_FILE=...`

Find device IDs: `fdb devices`

### Doctor

```bash
fdb doctor
```

Runs pre-flight checks for the app process, VM service, `fdb_helper`, platform tools, and stored device state. Always exits `0`; inspect `DOCTOR_SUMMARY=pass|fail CHECKS=<n> FAILED=<n>` and per-check `DOCTOR_CHECK=<name> STATUS=pass|fail|warn` lines.

### Hot reload / restart

```bash
fdb reload    # SIGUSR1 - preserves state
fdb restart   # SIGUSR2 - resets state
```

### Screenshot

```bash
fdb screenshot [--output <path>] [--full]
```

Dispatches to the right tool per platform: `adb` (Android), `xcrun simctl` (iOS simulator), `screencapture` (macOS), `xdotool`+`import` (Linux X11), Chrome DevTools Protocol (web), or `fdb_helper` VM extension (physical iOS, Windows, Wayland). Output is downscaled so the longest side fits within 1200px — pass `--full` to get native resolution. Default output: `<project>/.fdb/screenshot.png`.

### Logs

```bash
fdb logs --tag "MyTag" --last 50
```

Reads from the tee'd log file. Use `--tag` to grep for specific tags.

### Widget tree

```bash
fdb tree --depth 5
fdb tree --depth 3 --user-only
```

### Widget selection

```bash
fdb select on     # enable tap-to-select overlay on device
fdb select off    # disable overlay
fdb selected      # get what widget was tapped
```

### Widget interaction (tap, input, scroll)

These commands require `fdb_helper` to be added to your Flutter app. Add it to `pubspec.yaml`:

```yaml
dev_dependencies:
  fdb_helper: ^1.2.1
```

Initialize it in `main.dart`:

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

Then use the commands:

```bash
fdb tap --key "increment_button"          # tap by widget key
fdb tap --text "Submit"                   # tap by visible text
fdb tap --type "FloatingActionButton"     # tap by widget type
fdb tap --at 200,400                       # tap absolute screen coordinates

fdb double-tap --key "photo_viewer"       # double-tap by widget key
fdb double-tap --type "InteractiveViewer" --index 1 # choose a specific match
fdb double-tap --x 200 --y 400             # double-tap at screen coordinates
fdb double-tap --at 200,400                # shorthand for --x/--y

fdb longpress --key "photo_card"          # long-press by widget key (default 500ms)
fdb longpress --text "Hold me"            # long-press by visible text
fdb longpress --key "item" --duration 1000  # long-press for 1 second
fdb longpress --at 200,400 --duration 1000  # long-press coordinates for 1 second

fdb input --key "test_input" "hello fdb"  # type into a field by key
fdb input --text "Search" "query text"    # type into a field by label text

fdb scroll down                           # scroll down
fdb scroll up                             # scroll up
fdb scroll down --at 200,400              # scroll at specific coordinates

fdb swipe left --key "photo_card"         # swipe a widget left (PageView, Dismissible)
fdb swipe right --text "Next"             # swipe by visible text
fdb swipe left                            # swipe from screen center
fdb swipe up --distance 400              # swipe with custom distance
```

Output tokens: `TAPPED=<type> X=<x> Y=<y>`, `DOUBLE_TAPPED=<type> X=<x> Y=<y>`, `LONG_PRESSED=<type> X=<x> Y=<y>`, `INPUT=<type> VALUE=<text>`, `SCROLLED=<DIR> DISTANCE=<n>`, `SCROLLED_TO=<type> X=<x> Y=<y>`, `SWIPED=<DIR> DISTANCE=<n>`

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up temp files
```

### SharedPreferences (requires fdb_helper)

```bash
fdb shared-prefs get-all                            # inspect current state
fdb shared-prefs set onboarding_done true --type bool  # seed a flag
fdb shared-prefs set launch_count 0 --type int     # reset a counter
fdb shared-prefs remove <key>                       # delete one key
fdb shared-prefs clear                              # wipe all prefs
```

Output: `PREF_VALUE=<v>` / `PREF_NOT_FOUND` / `PREF_ALL=<json>` / `PREF_SET=<key>` / `PREF_REMOVED=<key>` / `PREF_CLEARED`

### Clean app data (requires fdb_helper)

```bash
fdb clean
```

Deletes all files in the app's temporary, support, and documents directories. The app keeps running. Output: `CLEANED`, `DIRS=...`, `DELETED_ENTRIES=<n>`.

## Agent Patterns

```bash
# List available devices
fdb devices

# Pick a device ID from the output and launch
DEVICE=$(fdb devices 2>/dev/null | grep '^DEVICE_ID=' | head -1 | sed 's/DEVICE_ID=\([^ ]*\).*/\1/')
fdb launch --device "$DEVICE" --project /path/to/flutter/app
fdb tree --depth 5 --user-only
fdb screenshot
fdb logs --tag "ERROR" --last 50
fdb kill

# Hot reload after code changes
fdb reload

# Add debug logging, then filter
# In Dart code: debugPrint('[MyTag] some message');
fdb logs --tag "MyTag" --last 20

# Widget inspection workflow
fdb select on        # enable tap-to-select on device
# (user taps a widget on the device)
fdb selected         # get what was tapped
fdb select off       # disable overlay

# Widget interaction workflow (requires fdb_helper in the app)
fdb shared-prefs clear                    # wipe all SharedPreferences
fdb clean                                 # reset app data before test
fdb tap --key "submit_button"             # tap a button by key
fdb input --key "search_field" "flutter"  # type into a text field
fdb screenshot                            # verify the result visually
fdb scroll down                           # scroll to reveal more content
fdb scroll-to --key "list_item_42"        # scroll until a specific item is visible
fdb logs --tag "fdb_test" --last 20       # check logs after interaction
```

## Troubleshooting

**fdb: command not found** -- Ensure `~/.pub-cache/bin` is in your `PATH`.

**Launch hangs** -- Check that the device ID is correct (`flutter devices`) and the project path is valid.

**Empty widget tree** -- Fall back to raw websocat commands (see the skill file for details).

**Screenshot fails** -- Check the tool for your platform is on PATH: `adb` (Android), `xcrun` (iOS simulator), `screencapture` (macOS), `xdotool`+`import` (Linux X11). Physical iOS, Windows, and Wayland use `fdb_helper` — add it to your app and call `FdbBinding.ensureInitialized()`.

**Status shows RUNNING=false after launch** -- The Flutter process may have crashed. Check `fdb logs --last 50` for errors.
