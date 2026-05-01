## 1.5.1

### Fixes
- `fdb describe` no longer leaks elements from underlying navigator routes — when navigating to a child screen, the handler previously walked route subtrees kept alive by the Navigator stack; the fix tracks the active `ModalRoute` boundary and prunes any subtree where `isCurrent` is `false`

## 1.5.0

### New commands
- `fdb gc` — force a full garbage collection across all isolates; prints heap before/after delta

### Improvements
- `fdb launch` now surfaces structured `LAUNCH_ERROR=<CATEGORY>` tokens when flutter process exits before the VM service appears, with `LAUNCH_ERROR_CAUSE` and `HINT` for known failure patterns (iOS bundle ID, code signing, Android ADB install, SDK toolchain, build errors)
- `skills/using-fdb/SKILL.md` is now a lean install-once shim; `fdb skill` reads the full reference from the bundled `lib/skill/SKILL.md`

### Fixes
- `fdb tap` on a widget that disappears during or after the tap now returns graceful success instead of an error

## 1.4.0

### New commands
- `fdb crash-report` — fetches OS-level crash and OOM records from the system log (Android logcat, iOS Console, macOS unified log), filtered to the running app
- `fdb ext list` — enumerates all registered VM service extensions across isolates
- `fdb ext call <method>` — invokes any VM service extension and prints the JSON result
- `fdb mem` — shows heap totals (usage, external, capacity) per isolate with human-readable formatting
- `fdb mem --json` — same as above in machine-readable JSON
- `fdb mem profile` — captures an allocation profile snapshot to a file
- `fdb mem diff` — diffs two allocation profile snapshots and reports allocation changes

### Improvements
- `fdb launch` smoke readiness detection now uses `fdb wait` instead of a manual poll loop, making it more reliable and readable

### Fixes
- `fdb describe` now surfaces all `GestureDetector` and `InkWell` widgets at any nesting depth inside `Stack`/`Positioned`; previously the walk stopped at the first interactive ancestor, silently dropping inner buttons
- iOS simulator smoke tests stabilised

## 1.3.0

### New commands
- `fdb syslog` — streams native system logs (iOS Console / Android logcat) for the running app
- `fdb native-tap --at x,y` — taps native OS UI (permission dialogs, system sheets) by injecting events at the OS level, bypassing Flutter entirely (`adb shell input tap` on Android, IndigoHID on iOS simulator)
- `fdb tap --at x,y` — taps by absolute coordinates via in-process native injection through fdb_helper, reaching platform views overlaid on the Flutter surface (WebView, UIAlertController, AlertDialog) without requiring OS-level access

### Improvements
- `fdb describe` now surfaces off-screen children of `GridView` and `ListView` that were previously hidden
- App death is now detected and surfaces an `APP_DIED` error immediately instead of hanging
- `.fdb/` state directory is now auto-located by walking up the directory tree, so fdb commands work from any subdirectory of the project
- `fdb status` returns `RUNNING=true` when a launch was interrupted but the app is still alive via VM URI fallback
- `fdb.app_pid` is now stored separately from `fdb.pid` for accurate app liveness detection

### Fixes
- Session directory walk-up no longer escapes to a parent `.fdb/` that has no `vm_uri.txt` when the local PID is stale
- `fdb status` VM URI fallback works correctly when launch is interrupted

## 1.2.1

### Fixes
- `fdb logs` now keeps recent VM-service log lines readable through unexpected app crashes by running the log collector as a real entrypoint with serialized flushes

## 1.2.0

### New commands
- `fdb doctor` - pre-flight health checks for the app process, VM service, `fdb_helper`, platform tools, and stored device state
- `fdb double-tap` - double-tap widgets by selector or absolute coordinates
- `fdb scroll-to` - scroll until a target widget becomes visible, including lazy lists
- `fdb wait` - wait for widget and route presence or absence without shell polling loops

### Improvements
- `fdb tap` and `fdb longpress` now support absolute coordinate targeting via `--at x,y`
- Reload and restart completion now use VM lifecycle events for more reliable detection, including macOS reload handling
- Test automation gained a stricter verify pipeline plus more robust deep-link and double-tap smoke coverage

### Fixes
- Android test app now registers the `fdbtest://` URL scheme so deep-link smoke tests exercise the real Android flow

## 1.1.7

### New
- `fdb screenshot` now supports all platforms: macOS (`screencapture`), Linux X11 (`xdotool`+`import`), physical iOS / Windows / Linux Wayland (via `fdb_helper` VM extension), and web (Chrome DevTools Protocol)
- `fdb_helper`: new `ext.fdb.screenshot` VM extension — renders the Flutter surface to PNG and returns base64; used as fallback on platforms with no native capture CLI
- Screenshots are automatically downscaled so the longest side fits within 1200px (preserving aspect ratio), using the pure-Dart `image` package; pass `--full` to get native resolution

### Fixes
- Screenshot: `fdb launch` now writes `.fdb/platform.txt` so screenshot dispatches to the correct backend without probing live tools at capture time
- Screenshot: Android and iOS simulator now targeted by explicit device ID (no more `booted` heuristic that breaks with multiple simulators)
- `devices.dart`: safe cast for `emulator` field (`as bool? ?? false`) to avoid crash on unexpected flutter devices output
- `extractDevicesJson` deduplicated into `process_utils.dart` (was copied in both `launch.dart` and `devices.dart`)
- Fix CI release: `fdb_helper/CHANGELOG.md` missing 1.1.6 entry caused GitHub release to not be created despite pub.dev publish succeeding

## 1.1.6

### Fixes
- `SKILL.md` state files section corrected: paths are `<project>/.fdb/` (not `/tmp/`) since 1.1.0
- `SKILL.md` screenshot default path corrected to `<project>/.fdb/screenshot.png`
- `doc/README.agents.md` screenshot default path corrected to `<project>/.fdb/screenshot.png`

### Improvements
- README: updated Flutter MCP server description to accurately reflect its current capabilities (runtime introspection, not just static analysis)
- README: comparison table "Device interaction" row now enumerates fdb's full interactive command set and correctly characterises the MCP server as read-only
- README: `fdb describe` command annotated with `(requires fdb_helper)` in the commands table

## 1.1.5

### Fixes
- Fix CI publish: fdb 1.1.4 was published but fdb_helper was not due to missing CHANGELOG entry

## 1.1.4

### Improvements
- Renamed skill from `interacting-with-flutter-apps` to `using-fdb` for better discoverability on skills.sh

## 1.1.3

### Improvements
- `fdb_helper` is now published to pub.dev — add it as `fdb_helper: ^1.1.3` instead of a git path reference

## 1.1.2

### New commands
- `fdb shared-prefs get|get-all|set|remove|clear` — read/write/clear SharedPreferences from the CLI via a VM service extension in fdb_helper

### Fixes
- `fdb deeplink` now uses the session device ID to detect platform instead of probing all connected devices — fixes misrouting to Android when both Android and iOS are connected but the session is on iOS

### Improvements
- Smoke test extended with `test:clean` and `test:shared-prefs` tasks covering all sub-commands

## 1.1.1

### Improvements
- `fdb_helper` install instructions now reference pub.dev (`fdb_helper: ^X.Y.Z`) instead of a git path reference
- Releasing skill updated to track all 9 version-bearing files

## 1.1.0

### Fixes
- Fix `developer.log()` output not appearing in `fdb logs` — `flutter run` never forwards `developer.log()` to stdout; a background log collector now subscribes to the VM service `Logging` stream and appends events directly to the log file

### Improvements
- Session state moved from `/tmp/fdb_*.txt` to `<project>/.fdb/` — multiple projects can run simultaneously without interfering with each other
- `.fdb/` is automatically added to the project's `.gitignore` on first launch
- FVM support: `launch` auto-detects `.fvm/flutter_sdk/bin/flutter`; override with `--flutter-sdk <path>`
- `--project` flag on `launch` is now optional — defaults to CWD (agents running from the project directory need not pass it)
- Log collector self-cleans on SIGTERM, SIGINT, and when flutter run exits

## 1.0.1

### Fixes
- Fix dartdoc angle bracket warnings in `describe.dart` and `vm_service.dart`
- Fix deeplink smoke test — register `fdbtest://` URL scheme in test app Info.plist
- Fix back smoke test — restart app to reset UI state before navigation test

### Improvements
- Add `example/example.md` for pub.dev Example tab
- Replace mermaid code block with pre-rendered SVG diagram (renders on pub.dev)
- Add `dart pub global activate fdb` install option to README
- Add release skill and CI publish workflow

## 1.0.0

### New commands
- `fdb back` — navigate back via Navigator.maybePop(), handles dialogs and root detection
- `fdb longpress` — long-press widgets, reuses tap infrastructure with configurable duration
- `fdb swipe` — swipe gestures for PageView/Dismissible with widget targeting and smart defaults
- `fdb describe` — compact screen snapshot with interactive element refs (@1, @2...) for agent navigation
- `fdb devices` — list connected devices
- `fdb deeplink` — open deep link URLs on device
- `fdb skill` — print SKILL.md for AI agent consumption

### Describe command
- Shows only hittable, topmost-layer widgets (filters obscured/background route elements)
- Gesture info on GestureDetector/InkWell: `(tap)`, `(tap,horizontalDrag)`, `(tap,longPress)`
- Extracts text from all children, tooltips, and icon semantic labels
- Filters framework widgets and Unicode PUA icon codepoints
- Ref-based tapping: `fdb tap @3` taps the 3rd interactive element from last describe
- Shows deepest route name and Scaffold title

### Fixes
- Error propagation: specific error messages instead of "Server error"
- `--text` tap: walks to hittable ancestor when Text widget itself isn't in hit-test path
- `--index` ordering: user widgets before framework widgets (Overlay, IndexedStack, _Theater)
- `--key` tap: ancestor walk for KeyMatcher/TypeMatcher, not just TextMatcher
- `--help` / `-h`: prints to stdout with exit 0, no "ERROR:" prefix
- Swipe velocity: process-relative Stopwatch timestamps for VelocityTracker fling detection
- Screenshot: defaults to 1x logical resolution (~180KB vs ~1MB), `--full` for native
- Screenshot: supports `--output=path` equals syntax, fixes Android shell escaping
- Skill command: resolves SKILL.md via package URI for global installs

## 0.1.0

- Initial release
- CLI commands: launch, status, reload, restart, kill, logs, tree, screenshot, select, selected, tap, input, scroll
- fdb_helper package for Flutter app integration
