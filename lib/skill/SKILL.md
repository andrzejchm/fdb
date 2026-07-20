---
name: using-fdb
description: Uses fdb (Flutter Debug Bridge) CLI to interact with running Flutter apps on devices and simulators. Launches or attaches to apps, hot reloads, screenshots, reads app logs (`fdb logs`) and native system logs (`fdb syslog` — Android logcat, iOS syslog, macOS log), fetches OS-level crash records (`fdb crash-report` — jetsam, LMK, native .ips), inspects widget trees, describes screens including off-screen GridView/ListView children, taps/inputs/scrolls/swipes/navigates, forces garbage collection (`fdb gc`), and grants/revokes/resets runtime permissions (`fdb grant-permission`). Use when launching or attaching to a Flutter app on device (including apps started outside fdb via Xcode/simctl/adb), hot reloading, taking screenshots, reading app or native system logs, diagnosing native crashes (jetsam, LMK), fetching post-mortem crash reports, inspecting or describing the UI, interacting with widgets via fdb, forcing a GC to disambiguate live-retained vs unreachable-but-uncollected memory, or pre-granting runtime permissions before automated tests.
license: MIT
compatibility: opencode
---

## Overview - skill version 1.10.1

> **Version check:** Run `fdb --version`. This skill may describe unreleased branch behavior.
> Update: `dart pub global activate --source git https://github.com/andrzejchm/fdb.git`

## Install

```bash
dart pub global activate --source git https://github.com/andrzejchm/fdb.git
```

Verify: `fdb status`

## fdb_helper setup (required for in-app UI/data commands)

The `describe`, `tap`, `double-tap`, `longpress`, `input`, `scroll`, `scroll-to`, `wait`, `swipe`, `swipe-path`, `back`, `clean`, and `shared-prefs` commands require `fdb_helper` in the Flutter app under test. Some platform screenshot fallbacks also use it. Adding `fdb_helper` also enables automatic VM service URI discovery for `fdb attach` on Android and iOS — no manual `--debug-url` needed.

**`pubspec.yaml`:**
```yaml
dev_dependencies:
  fdb_helper: ^1.10.1
```

**`main.dart`:**
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

After adding `fdb_helper`, run `flutter pub get` and relaunch the app.

## Command index

Run `fdb skill <topic>` to print full docs, flags, output tokens, and best practices for a topic.

| Topic | Commands | Run |
|-------|----------|-----|
| **launch** | `devices`, `launch`, `attach`, `doctor`, `reload`, `restart`, `status`, `kill`, `deeplink` | `fdb skill launch` |
| **interact** | `screenshot`, `tree`, `describe`, `select`, `selected`, `native-tap`, `tap`, `longpress`, `double-tap`, `input`, `scroll`, `scroll-to`, `swipe`, `swipe-path`, `back` | `fdb skill interact` |
| **data** | `shared-prefs`, `clean`, `ext`, `grant-permission` | `fdb skill data` |
| **diagnostics** | `logs`, `syslog`, `crash-report` + websocat fallback | `fdb skill diagnostics` |
| **memory** | `mem`, `gc`, `heap` | `fdb skill memory` |
| **simulator** | `simulator` (appearance, text-size, status-bar, location, push, defaults) | `fdb skill simulator` |

## Session directory

All state lives in `<project>/.fdb/`. fdb auto-resolves by walking up from CWD — no need to `cd` to the project root. Key files: `logs.txt`, `vm_uri.txt`, `platform.txt`, `app_id.txt`, `screenshot.png`. Full reference: `fdb skill launch`.
