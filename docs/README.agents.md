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
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.config/opencode/skills/interacting-with-flutter-apps/SKILL.md
```

**Claude Code:**
```bash
mkdir -p ~/.claude/skills/interacting-with-flutter-apps
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.claude/skills/interacting-with-flutter-apps/SKILL.md
```

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
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.config/opencode/skills/interacting-with-flutter-apps/SKILL.md

# Update the skill file (Claude Code)
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.claude/skills/interacting-with-flutter-apps/SKILL.md
```

## Prerequisites

- Dart SDK >= 3.0.0
- Flutter SDK (for `flutter devices`, `flutter run`)
- A running iOS Simulator or Android emulator (or physical device)
- `adb` for Android screenshots
- `xcrun` (Xcode Command Line Tools) for iOS simulator screenshots
- `screencapture` (Xcode CLT, macOS only) for macOS desktop screenshots
- `xdotool` + `import` (ImageMagick) for Linux X11 screenshots
- Physical iOS, Windows, and Linux Wayland screenshots use `fdb_helper` fallback (requires `fdb_helper` in the app)

## Commands Reference

| Command | Description |
|---------|-------------|
| `fdb devices` | List connected devices (one `DEVICE_ID=<id> NAME=<name> PLATFORM=<platform> EMULATOR=<true\|false>` line per device) |
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
| `fdb input [--text/--key/--type <selector>] <text>` | Enter text into field |
| `fdb scroll <direction> [--at x,y]` | Scroll screen |
| `fdb status` | Check if app is running |
| `fdb kill` | Stop app |

### Launch

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

Default output: `~/.fdb/sessions/<hash>/screenshot.png`.

Output tokens on success:
```
SCREENSHOT_SAVED=<path>
SIZE=<size>
```

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

`fdb selected` output tokens:
```
SELECTED: <widget description> (<file>:<line>)   # when creation location is known
SELECTED: <widget description>                    # when creation location is unknown
NO_WIDGET_SELECTED                                # when no widget has been tapped yet
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

fdb input --key "test_input" "hello fdb"  # type into a field by key
fdb input --text "Search" "query text"    # type into a field by label text

fdb scroll down                           # scroll down
fdb scroll up                             # scroll up
fdb scroll down --at 200,400              # scroll at specific coordinates
```

Output tokens: `TAPPED=<type> X=<x> Y=<y>`, `INPUT=<type> VALUE=<text>`, `SCROLLED=<DIR> DISTANCE=<n>`

### Status / Kill

```bash
fdb status    # RUNNING=true/false, PID, VM_SERVICE_URI
fdb kill      # stop app, clean up session files
```

Session state is stored in `~/.fdb/sessions/<hash>/session.json`. The device list cache is stored in `~/.fdb/devices.json`.

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

**Screenshot fails** -- Ensure the required tool is available for your platform: `adb` (Android), `xcrun` (iOS simulator / macOS), `xdotool`+`import` (Linux X11). For physical iOS, Windows, or Linux Wayland, ensure `fdb_helper` is added to the app.

**Status shows RUNNING=false after launch** -- The Flutter process may have crashed. Check `fdb logs --last 50` for errors.
