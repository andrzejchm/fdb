# fdb - Flutter Debug Bridge

> Give your AI agent eyes and hands on your Flutter app.

**fdb** is a CLI that lets AI coding agents launch, hot reload, screenshot, inspect, and kill Flutter apps running on real devices and simulators -- all from the terminal, no IDE required.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [OpenCode](https://opencode.ai), and any AI agent that can run bash commands.

## Why fdb?

AI agents are great at writing Flutter code. But they can't *see* what the app looks like, *read* runtime logs, or *inspect* the widget tree -- unless you give them the tools.

fdb bridges that gap:

- **Launch** a Flutter app on any connected device or simulator
- **Hot reload / restart** after code changes, without restarting the session
- **Screenshot** the device screen so the agent can see the UI
- **Read logs** filtered by tag, so the agent can debug runtime issues
- **Inspect the widget tree** to understand the live UI hierarchy
- **Select widgets** by tapping on device, then retrieve the widget info

Zero dependencies. Pure Dart. Works on macOS and Linux.

### Why not the official Flutter MCP server?

The [Dart & Flutter MCP server](https://docs.flutter.dev/ai/mcp-server) is a great tool for code analysis, pub.dev search, and formatting. fdb solves a different problem -- **running and interacting with apps on real devices** -- and takes a fundamentally different approach:

| | fdb | Flutter MCP server |
|---|---|---|
| **Architecture** | CLI -- plain bash commands | MCP protocol -- requires a compatible client |
| **Context cost** | Minimal. Agent runs a command, gets text output. | MCP tool schemas and responses are injected into context on every call, eating tokens even when unused. |
| **Works with** | Any agent that can run bash (Claude Code, OpenCode, Cursor, custom scripts, CI) | Only MCP-compatible clients |
| **Progressive disclosure** | Ships a [skill file](docs/skills/interacting-with-flutter-apps/SKILL.md) -- agent loads best practices on demand, not upfront | All tools exposed at once |
| **Device interaction** | Launch, hot reload, screenshot, logs, widget tree, widget selection | Limited runtime introspection |
| **Setup** | `dart pub global activate` -- done | Per-client MCP config (JSON, YAML, or GUI depending on client) |

**tl;dr:** Use the Flutter MCP server for code analysis and package management. Use fdb when your agent needs to *run the app, see it, and interact with it*.

## Install

**Tell your AI agent:**

```
Fetch and follow instructions from https://raw.githubusercontent.com/andrzejchm/fdb/main/docs/README.agents.md
```

**Or install manually:**

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Requires Dart SDK >= 3.0.0. Make sure `~/.pub-cache/bin` is in your `PATH`.

## Quick Start

```bash
# Launch your app on a connected device
fdb launch --device <device_id> --project /path/to/your/flutter/app

# See what it looks like
fdb screenshot

# Make a code change, then hot reload
fdb reload

# Check the widget hierarchy
fdb tree --depth 5 --user-only

# Read filtered logs
fdb logs --tag "MyFeature" --last 30

# Done? Kill the app
fdb kill
```

## Commands

| Command | Description |
|---------|-------------|
| `fdb launch --device <id> --project <path>` | Launch app, wait for start |
| `fdb reload` | Hot reload (SIGUSR1) |
| `fdb restart` | Hot restart (SIGUSR2) |
| `fdb screenshot [--output <path>]` | Device screenshot |
| `fdb logs --tag <tag> --last <n>` | Filtered logs |
| `fdb tree --depth <n> [--user-only]` | Widget tree |
| `fdb select on/off` | Widget selection mode |
| `fdb selected` | Get selected widget info |
| `fdb status` | Check if app is running |
| `fdb kill` | Stop app, clean up |

## How It Works

```
AI Agent                    fdb                         Device/Simulator
   |                         |                               |
   |-- fdb launch ---------->|-- flutter run (detached) ---->|
   |                         |   saves PID, VM URI to /tmp   |
   |-- fdb reload ---------->|-- SIGUSR1 ------------------->|
   |-- fdb screenshot ------>|-- adb/xcrun --------------->  |
   |<- SCREENSHOT_SAVED=/tmp/fdb_screenshot.png              |
   |-- fdb tree ------------>|-- VM Service (WebSocket) ---->|
   |<- widget tree output    |                               |
   |-- fdb kill ------------>|-- SIGTERM ------------------->|
```

- Launches `flutter run` as a detached process with `--pid-file`
- Hot reload/restart via POSIX signals (SIGUSR1/SIGUSR2)
- Screenshots via `adb screencap` (Android) or `xcrun simctl io` (iOS)
- Widget inspection via VM Service Protocol over WebSocket
- All state in `/tmp/fdb_*` files -- no config, no database, no daemon

## Development & Testing

A minimal Flutter app lives in `example/test_app/` and is used as the target
for integration testing. All test scripts are defined in `Taskfile.yml`
(requires [Task](https://taskfile.dev)).

```bash
# Full smoke test -- launches the app, runs every fdb command, then kills it
task smoke

# Or pass a specific device ID
task smoke DEVICE=iPhone-16

# Static analysis
task analyze

# Individual command tests (app must already be running via test:launch)
task test:launch DEVICE=iPhone-16
task test:status
task test:reload
task test:restart
task test:logs
task test:tree
task test:screenshot
task test:select
task test:kill
```

## Contributing

Contributions welcome. The codebase is intentionally simple: pure Dart, no classes, no frameworks, no dependencies. See [AGENTS.md](AGENTS.md) for coding conventions.

## License

MIT
