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
| **Progressive disclosure** | Ships a [skill file](skills/interacting-with-flutter-apps/SKILL.md) -- agent loads best practices on demand, not upfront | All tools exposed at once |
| **Device interaction** | Launch, hot reload, screenshot, logs, widget tree, widget selection | Limited runtime introspection |
| **Setup** | `dart pub global activate` -- done | Per-client MCP config (JSON, YAML, or GUI depending on client) |

**tl;dr:** Use the Flutter MCP server for code analysis and package management. Use fdb when your agent needs to *run the app, see it, and interact with it*.

## Install

**Tell your AI agent:**

```
Fetch and follow instructions from https://raw.githubusercontent.com/andrzejchm/fdb/main/doc/README.agents.md
```

**Or install manually:**

```bash
# From pub.dev (recommended)
dart pub global activate fdb

# Or from git (latest main)
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
| `fdb devices` | List connected devices |
| `fdb deeplink <url>` | Open deep link on device |
| `fdb launch --device <id> --project <path>` | Launch app, wait for start |
| `fdb reload` | Hot reload |
| `fdb restart` | Hot restart |
| `fdb screenshot [--output <path>]` | Device screenshot |
| `fdb logs --tag <tag> --last <n>` | Filtered logs |
| `fdb tree --depth <n> [--user-only]` | Widget tree |
| `fdb describe` | Compact screen snapshot: interactive elements + visible text |
| `fdb select on/off` | Widget selection mode |
| `fdb selected` | Get selected widget info |
| `fdb tap --text/--key/--type <selector>` or `fdb tap @N` | Tap a widget or describe ref |
| `fdb longpress --text/--key/--type <selector> [--duration <ms>]` | Long-press a widget |
| `fdb input [--text/--key/--type <selector>] <text>` | Enter text into field |
| `fdb scroll <direction> [--at x,y] [--distance px]` | Scroll screen in a direction |
| `fdb scroll --from x,y --to x,y` | Drag gesture between two points |
| `fdb swipe <direction> [--key/--text/--type <selector>]` | Swipe widget (PageView, Dismissible) |
| `fdb back` | Navigate back (Navigator.maybePop) |
| `fdb clean` | Clear app cache and data directories |
| `fdb shared-prefs get\|get-all\|set\|remove\|clear` | Read/write SharedPreferences |
| `fdb status` | Check if app is running |
| `fdb kill` | Stop app, clean up |
| `fdb skill` | Print the AI agent skill file (SKILL.md) |
| `fdb --version` | Print the fdb version |

## How It Works

![How fdb works - sequence diagram](https://raw.githubusercontent.com/andrzejchm/fdb/main/doc/how-it-works-light.svg)

- All state in `/tmp/fdb_*` files -- no config, no database, no daemon
- Screenshots auto-detect Android (`adb`) vs iOS (`xcrun`)
- Widget inspection via VM Service Protocol over WebSocket

### Widget Interaction (tap, input, scroll)

These commands require adding `fdb_helper` to your Flutter app:

```yaml
# pubspec.yaml
dev_dependencies:
  fdb_helper: ^1.1.3
```

```dart
// main.dart
import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/foundation.dart';

void main() {
  if (!kReleaseMode) {
    FdbBinding.ensureInitialized();
  }
  runApp(MyApp());
}
```

## Contributing

Contributions welcome. See [AGENTS.md](AGENTS.md) for coding conventions and the [testing skill](.agents/skills/testing-fdb/SKILL.md) for how to run the test suite.

## License

MIT
