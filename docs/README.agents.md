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
mkdir -p ~/.config/opencode/skills/interacting-with-flutter-apps
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.config/opencode/skills/interacting-with-flutter-apps/SKILL.md
```

**Claude Code:**
```bash
mkdir -p ~/.claude/skills/interacting-with-flutter-apps
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.claude/skills/interacting-with-flutter-apps/SKILL.md
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
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.config/opencode/skills/interacting-with-flutter-apps/SKILL.md

# Update the skill file (Claude Code)
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.claude/skills/interacting-with-flutter-apps/SKILL.md
```

## Prerequisites

- Dart SDK >= 3.0.0
- Flutter SDK (for `flutter devices`, `flutter run`)
- A running iOS Simulator or Android emulator (or physical device)
- `adb` for Android screenshots, `xcrun` for iOS simulator screenshots

## Commands Reference

| Command | Description |
|---------|-------------|
| `fdb devices` | List connected devices |
| `fdb deeplink <url>` | Open deep link on device |
| `fdb launch --device <id> --project <path>` | Launch app, wait for start |
| `fdb reload` | Hot reload (SIGUSR1) |
| `fdb restart` | Hot restart (SIGUSR2) |
| `fdb screenshot [--output <path>]` | Device screenshot |
| `fdb logs --tag <tag> --last <n>` | Filtered logs |
| `fdb tree --depth <n> [--user-only]` | Widget tree |
| `fdb select on/off` | Widget selection mode |
| `fdb selected` | Get selected widget |
| `fdb tap --text/--key/--type <selector>` | Tap a widget |
| `fdb longpress --text/--key/--type <selector> [--duration <ms>]` | Long-press a widget |
| `fdb input [--text/--key/--type <selector>] <text>` | Enter text into field |
| `fdb scroll <direction> [--at x,y]` | Scroll screen |
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

### Hot reload / restart

```bash
fdb reload    # SIGUSR1 - preserves state
fdb restart   # SIGUSR2 - resets state
```

### Screenshot

```bash
fdb screenshot [--output <path>]
```

Auto-detects Android (`adb screencap`) vs iOS simulator (`xcrun simctl io screenshot`). Default output: `/tmp/fdb_screenshot.png`.

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
  fdb_helper:
    git:
      url: https://github.com/andrzejchm/fdb.git
      path: packages/fdb_helper
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

fdb longpress --key "photo_card"          # long-press by widget key (default 500ms)
fdb longpress --text "Hold me"            # long-press by visible text
fdb longpress --key "item" --duration 1000  # long-press for 1 second

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

Output tokens: `TAPPED=<type> X=<x> Y=<y>`, `LONG_PRESSED=<type> X=<x> Y=<y>`, `INPUT=<type> VALUE=<text>`, `SCROLLED=<DIR> DISTANCE=<n>`, `SWIPED=<DIR> DISTANCE=<n>`

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up temp files
```

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
fdb tap --key "submit_button"             # tap a button by key
fdb input --key "search_field" "flutter"  # type into a text field
fdb screenshot                            # verify the result visually
fdb scroll down                           # scroll to reveal more content
fdb logs --tag "fdb_test" --last 20       # check logs after interaction
```

## Troubleshooting

**fdb: command not found** -- Ensure `~/.pub-cache/bin` is in your `PATH`.

**Launch hangs** -- Check that the device ID is correct (`flutter devices`) and the project path is valid.

**Empty widget tree** -- Fall back to raw websocat commands (see the skill file for details).

**Screenshot fails** -- Ensure `adb` (Android) or `xcrun` (iOS) is available and the device is connected.

**Status shows RUNNING=false after launch** -- The Flutter process may have crashed. Check `fdb logs --last 50` for errors.
