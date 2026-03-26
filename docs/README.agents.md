# fdb for AI Agents

Complete guide for using fdb (Flutter Debug Bridge) with [OpenCode](https://opencode.ai).

## Quick Install

Tell OpenCode:

```
Fetch and follow instructions from https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/README.agents.md
```

## Installation

### 1. Install the CLI

```bash
# Dart (recommended)
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Requires Dart SDK >= 3.0.0.

### 2. Install the skill file

```bash
mkdir -p ~/.config/opencode/skills/interacting-with-flutter-apps
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.config/opencode/skills/interacting-with-flutter-apps/SKILL.md
```

### 3. Verify

```bash
fdb status   # CLI installed and on PATH
```

Restart OpenCode after installing. The skill is now discoverable via the `skill` tool.

## Updating

```bash
# Update the CLI
dart pub global activate --source git https://github.com/andrzejchm/fdb.git

# Update the skill file
curl -fsSL https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/skills/interacting-with-flutter-apps/SKILL.md \
  -o ~/.config/opencode/skills/interacting-with-flutter-apps/SKILL.md
```

## Prerequisites

- Dart SDK >= 3.0.0
- Flutter SDK (for `flutter devices`, `flutter run`)
- A running iOS Simulator or Android emulator (or physical device)
- `adb` for Android screenshots, `xcrun` for iOS simulator screenshots

## Commands Reference

| Command | Description |
|---------|-------------|
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

Find device IDs: `flutter devices`

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
# Launch app, inspect it, then kill
DEVICE=$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
devices = json.load(sys.stdin)
skip = {"macos", "linux", "windows", "chrome"}
for d in devices:
    if d["id"] not in skip:
        print(d["id"]); sys.exit(0)
sys.exit(1)
')
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

**fdb: command not found** — Ensure `~/.pub-cache/bin` is in your `PATH`.

**Launch hangs** — Check that the device ID is correct (`flutter devices`) and the project path is valid.

**Empty widget tree** — Fall back to raw websocat commands (see the skill file for details).

**Screenshot fails** — Ensure `adb` (Android) or `xcrun` (iOS) is available and the device is connected.

**Status shows RUNNING=false after launch** — The Flutter process may have crashed. Check `fdb logs --last 50` for errors.
