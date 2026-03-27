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
| `fdb status` | Check if app is running |
| `fdb kill` | Stop app |

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
```

## Troubleshooting

**fdb: command not found** -- Ensure `~/.pub-cache/bin` is in your `PATH`.

**Launch hangs** -- Check that the device ID is correct (`flutter devices`) and the project path is valid.

**Empty widget tree** -- Fall back to raw websocat commands (see the skill file for details).

**Screenshot fails** -- Ensure `adb` (Android) or `xcrun` (iOS) is available and the device is connected.

**Status shows RUNNING=false after launch** -- The Flutter process may have crashed. Check `fdb logs --last 50` for errors.
