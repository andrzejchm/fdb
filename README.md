# fdb - Flutter Debug Bridge

CLI for AI agents to interact with running Flutter apps on device.

## For AI Agents

```
Fetch and follow instructions from https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/README.agents.md
```

## Install

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

## Commands

| Command | Description |
|---------|-------------|
| `fdb launch --device <id> --project <path>` | Launch app, wait for start |
| `fdb reload` | Hot reload (SIGUSR1) |
| `fdb restart` | Hot restart (SIGUSR2) |
| `fdb screenshot` | Device screenshot |
| `fdb logs --tag <tag> --last <n>` | Filtered logs |
| `fdb tree --depth <n>` | Widget tree |
| `fdb select on/off` | Widget selection mode |
| `fdb selected` | Get selected widget |
| `fdb status` | Check if app is running |
| `fdb kill` | Stop app |

## Development & Testing

A minimal Flutter app lives in `example/test_app/` and is used as the target
for integration testing. All test scripts are defined in `Taskfile.yml`
(requires [Task](https://taskfile.dev)).

```bash
# Prerequisites: a running iOS Simulator or Android emulator

# Full smoke test — launches the app, runs every fdb command, then kills it
task smoke

# Or pass a specific device ID
task smoke DEVICE=iPhone-16

# Run individual command tests (app must already be running via test:launch)
task test:launch DEVICE=iPhone-16
task test:status
task test:reload
task test:restart
task test:logs
task test:logs-tag
task test:tree
task test:screenshot
task test:select
task test:kill
task test:status-stopped

# Cleanup temp files and kill any leftover app
task cleanup

# Static analysis
task analyze
```

## How it works

- Launches `flutter run` as a detached process with `--pid-file`
- Hot reload/restart via POSIX signals (SIGUSR1/SIGUSR2)
- Screenshots via `adb screencap` (Android) or `xcrun simctl io` (iOS)
- Widget inspection via VM Service Protocol over WebSocket
- All state in `/tmp/fdb_*` files
