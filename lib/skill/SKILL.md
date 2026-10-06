---
name: using-fdb
description: Uses fdb (Flutter Debug Bridge) CLI to interact with running Flutter apps on devices and simulators. Launches or attaches to apps, hot reloads, screenshots, reads app logs (`fdb logs`) and native system logs (`fdb syslog` — Android logcat, iOS syslog, macOS log), fetches OS-level crash records (`fdb crash-report` — jetsam, LMK, native .ips), inspects widget trees, describes screens including off-screen GridView/ListView children, taps/inputs/scrolls/swipes/navigates, forces garbage collection (`fdb gc`), and grants/revokes/resets runtime permissions (`fdb grant-permission`). Use when launching or attaching to a Flutter app on device (including apps started outside fdb via Xcode/simctl/adb), hot reloading, taking screenshots, reading app or native system logs, diagnosing native crashes (jetsam, LMK), fetching post-mortem crash reports, inspecting or describing the UI, interacting with widgets via fdb, forcing a GC to disambiguate live-retained vs unreachable-but-uncollected memory, or pre-granting runtime permissions before automated tests.
license: MIT
compatibility: opencode
---

## Overview - skill version 1.12.0

> **Version check:** Run `fdb --version`. Expected: `fdb 1.12.0`. This skill may describe unreleased branch behavior.
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
  fdb_helper: ^1.12.0
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
| **interact** | `screenshot`, `tree`, `describe`, `select`, `selected`, `native-tap`, `tap`, `longpress`, `double-tap`, `input` (any text input incl. flutter_quill; `--action send`), `scroll`, `scroll-to`, `swipe`, `swipe-path`, `back` | `fdb skill interact` |
| **data** | `shared-prefs`, `clean`, `ext`, `grant-permission` | `fdb skill data` |
| **diagnostics** | `logs`, `syslog`, `crash-report` + websocat fallback | `fdb skill diagnostics` |
| **memory** | `mem`, `gc`, `heap` | `fdb skill memory` |
| **simulator** | `simulator` (appearance, text-size, status-bar, location, push, defaults) | `fdb skill simulator` |

## Session directory

All state lives in `<project>/.fdb/`. fdb auto-resolves by walking up from CWD — no need to `cd` to the project root. Key files: `logs.txt`, `vm_uri.txt`, `platform.txt`, `app_id.txt`, `screenshot.png`. Full reference: `fdb skill launch`.

## Caveats

- `--session-dir` is a global option and goes BEFORE the command: `fdb --session-dir $S input "x"`. `fdb input --session-dir $S "x"` fails with `ERROR: Could not find an option named "--session-dir".` (or `ERROR: No .fdb/ session found.` if CWD has no session).
- `fdb doctor` takes no options, so no `--device`; it reads the device from the session. `fdb doctor --device X` fails with `ERROR: Could not find an option named "--device".`
- Use fdb before raw `xcrun simctl`, `idb`, or `adb`: `fdb grant-permission` (privacy grant/revoke/reset), `fdb simulator push|location|appearance|text-size|status-bar|defaults`, `fdb clean` (app files), `fdb deeplink <url>`. See `fdb skill data`, `fdb skill simulator`, `fdb skill launch`.
- `fdb native-tap` on the iOS simulator injects the touch in-process (`UIApplication.sendEvent`). It can't reach system dialogs (e.g. the paste prompt "would like to paste from CoreSimulator-Bridge") or the software keyboard, so it can't type. Use `fdb input` for text entry.
- fdb can't tap iOS simulator system prompts (support is planned). Avoid them: pre-grant with `fdb grant-permission` before the app asks (location, photos, camera, contacts, microphone, calendar, ...; NOT notifications, which `simctl privacy` doesn't cover), use `fdb input` instead of pasting, and use an app test hook instead of the system photo picker. Details: `fdb skill simulator`.
- The iOS simulator connects the Mac keyboard as a hardware keyboard by default, so no software keyboard appears and `MediaQuery.viewInsets.bottom` stays 0. Layouts that react to keyboard insets look different from a device. `fdb input` doesn't need a keyboard. To show it: Simulator menu I/O > Keyboard > Toggle Software Keyboard (Cmd+K).
- `@N` refs from `fdb describe` are IDs: a ref names one widget while it stays mounted, survives scrolling and rebuilds, and is never reused. When the widget is removed or replaced (navigation, a rebuilt list), the ref fails with `ERROR: @N is stale: ... Run fdb describe again.` and taps nothing. Run `fdb describe` again after navigation. Numbers are not 1..n.
- `Can't load Kernel binary: Invalid kernel binary format version` before fdb output, followed by `WARNING: fdb was activated with Dart X but 'dart' on PATH is Y`, means fdb was activated with a different Dart SDK than the `dart` on PATH (common with FVM). The command still ran; ignore the line. The user can remove it by running `dart pub global activate fdb` with the Dart they use. fdb doesn't change files in `~/.pub-cache`.
- `WARNING: App is not in the foreground (lifecycle=paused)` on `describe`/`screenshot` means another app (or the home screen) is in front. Output reflects the app's last frame, not the screen.
