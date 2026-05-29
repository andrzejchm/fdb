---
name: using-fdb
description: Uses fdb (Flutter Debug Bridge) CLI to interact with running Flutter apps on devices and simulators. Launches or attaches to apps, hot reloads, screenshots, reads app logs (`fdb logs`) and native system logs (`fdb syslog` — Android logcat, iOS syslog, macOS log), fetches OS-level crash records (`fdb crash-report` — jetsam, LMK, native .ips), inspects widget trees, describes screens including off-screen GridView/ListView children, taps/inputs/scrolls/swipes/navigates, forces garbage collection (`fdb gc`), and grants/revokes/resets runtime permissions (`fdb grant-permission`). Use when launching or attaching to a Flutter app on device (including apps started outside fdb via Xcode/simctl/adb), hot reloading, taking screenshots, reading app or native system logs, diagnosing native crashes (jetsam, LMK), fetching post-mortem crash reports, inspecting or describing the UI, interacting with widgets via fdb, forcing a GC to disambiguate live-retained vs unreachable-but-uncollected memory, or pre-granting runtime permissions before automated tests.
license: MIT
compatibility: opencode
---

Run `fdb skill` and read its full stdout output before doing anything with fdb.
That output is the authoritative, version-matched reference — it covers install,
fdb_helper setup, and the full command index.

For detailed docs on a specific topic, run `fdb skill <topic>`:

| Topic | What it covers |
|-------|---------------|
| `fdb skill launch` | devices, launch, attach, doctor, reload, restart, status, kill, deeplinks, state files, best practices |
| `fdb skill interact` | screenshot, describe, tap, longpress, double-tap, input, scroll, scroll-to, swipe, back, widget key best practices |
| `fdb skill data` | shared-prefs, clean, ext (VM extensions), grant-permission, test setup best practices |
| `fdb skill diagnostics` | logs, syslog, crash-report, websocat fallback, debugPrint best practices |
| `fdb skill memory` | mem, gc, heap dump, leak-hunting workflow, GC-before-profiling best practices |
| `fdb skill simulator` | iOS simulator: appearance, text-size, status-bar, location, push, defaults, screenshot best practices |

Only load the topic you need — each sub-doc is self-contained.
