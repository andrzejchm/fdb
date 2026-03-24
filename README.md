# fdb - Flutter Debug Bridge

CLI for AI agents to interact with running Flutter apps on device.

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

## How it works

- Launches `flutter run` as a detached process with `--pid-file`
- Hot reload/restart via POSIX signals (SIGUSR1/SIGUSR2)
- Screenshots via `adb screencap` (Android) or `xcrun simctl io` (iOS)
- Widget inspection via VM Service Protocol over WebSocket
- All state in `/tmp/fdb_*` files
