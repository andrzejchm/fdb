## 1.9.0

### Improvements
- `FdbBinding.ensureInitialized()` now calls `broadcastVmUri()` at startup, emitting a `[FDB_VM_URI]` log marker that `fdb attach` uses for reliable auto-discovery on Android and iOS without needing `--debug-url`.
- `broadcastVmUri()` calls `Service.controlWebServer(enable: true)` when `getInfo()` returns null, enabling discovery in profile builds launched without Flutter tooling.

## 1.8.0

### Improvements
- Added native long-press support for coordinate-based fdb interactions on supported platforms.

## 1.7.3

No functional changes. Version bumped in lockstep with fdb 1.7.3.

## 1.7.2

No functional changes. Version bumped in lockstep with fdb 1.7.2.

## 1.7.1

No functional changes. Version bumped in lockstep with fdb 1.7.1.

## 1.7.0

No functional changes. Version bumped in lockstep with fdb 1.7.0.

## 1.6.4

### Fixes
- iOS and macOS profile builds now compile the real native tap implementation again. Only release compiles the safe stub. The previous release stubbed both profile and release on Apple, which broke `fdb native-tap` for profile-mode binaries shipped via internal/dev channels.

## 1.6.3

### Fixes
- iOS/macOS release builds now compile a safe Swift stub instead of the private-API native tap implementation. Debug builds keep the real implementation. (Profile builds were also stubbed in this release; see 1.6.4.)
- Android release builds compile a stub `FdbHelperNativeTapImpl` via Gradle `src/release` source sets. Debug and profile keep the real implementation. The Android plugin no longer depends on the debug-only `flutter_embedding_debug` artifact.

## 1.6.2

### Fixes
- `ext.fdb.swipe` now uses finer-grained synthetic pointer movement to better match native touch behavior when parent drag recognizers compete with child scale recognizers.

## 1.6.1

### Fixes
- `findHittableElement` now always walks ancestors when the matched element is non-interactive, so `fdb tap --text` resolves to the enclosing button rather than the `Text` leaf (fdb-xdh)
- Pass-through wrappers (`IgnorePointer`, `AbsorbPointer`) are excluded as fallback tap targets so route-level `IgnorePointer(ignoring: false)` no longer leaks as the resolved widget (fdb-gfk)
- The closed list of interactive widget types now covers Cupertino (`CupertinoButton`, `CupertinoSwitch`, `CupertinoTextField`, `CupertinoSlider`, `CupertinoListTile`, etc.) and the Material widgets that were missing (`Chip` family, `MenuItemButton`, `ListTile`, `BackButton`, `RangeSlider`, `InkResponse`, navigation widgets, `DropdownMenu`, `ToggleButtons`)

## 1.6.0

No functional changes.

## 1.5.1

### Fixes
- `ext.fdb.describe` no longer leaks elements from underlying navigator routes — prunes subtrees where the enclosing `ModalRoute.isCurrent` is `false`

## 1.5.0

No functional changes.

## 1.4.0

### Fixes
- `ext.fdb.describe` now walks the full subtree of `GestureDetector` and `InkWell` widgets, surfacing nested interactive children that were previously silently dropped

## 1.3.0

### New
- `ext.fdb.doubleTap` now correctly invokes the callback when the target widget is hittable

### Fixes
- No functional changes to fdb_helper API — version bump to match fdb 1.3.0

## 1.2.1

### Improvements
- No functional changes — version bump to match fdb 1.2.1

## 1.2.0

### New
- `ext.fdb.doubleTap` - double-tap widgets by selector or coordinates
- `ext.fdb.scrollTo` - scroll the nearest scrollable until a target widget becomes visible
- `ext.fdb.wait` - wait for widget and route presence or absence from the VM service

### Improvements
- Tap and long-press handlers now support absolute coordinate targeting through the CLI `--at x,y` flow
- Double-tap test surfaces now expose visible counters so smoke tests verify UI state instead of log timing

## 1.1.7

### New
- `ext.fdb.screenshot` — renders the Flutter surface to PNG at physical pixel resolution and returns it as base64; used by `fdb screenshot` as a fallback on platforms with no native capture CLI (physical iOS, Windows, Linux Wayland)

## 1.1.6

### Improvements
- No functional changes — version bump to match fdb 1.1.6

## 1.1.5

### Improvements
- No functional changes — version bump to match fdb 1.1.5

## 1.1.4

### Improvements
- No functional changes — version bump to match fdb 1.1.4

## 1.1.3

### Improvements
- First pub.dev release — package now published to pub.dev as `fdb_helper`

## 1.1.2

### New
- `ext.fdb.sharedPrefs` — read/write/clear SharedPreferences (get, get-all, set, remove, clear; supports string, bool, int, double types)
- `ext.fdb.clean` — delete all entries in the app's temporary, support, and documents directories via path_provider

## 1.1.1

### Improvements
- Initial pub.dev release preparation (README, CHANGELOG, LICENSE)

## 1.1.0

### New
- `ext.fdb.back` — trigger Navigator.maybePop() on the root navigator

## 1.0.1

### Fixes
- Remove unnecessary flutter/rendering.dart import

## 1.0.0

### New
- `ext.fdb.elements` — list all interactive elements with bounds
- `ext.fdb.describe` — compact screen snapshot for agent navigation
- `ext.fdb.tap` — tap a widget by key, text, type, or @N ref
- `ext.fdb.longPress` — long-press a widget
- `ext.fdb.enterText` — enter text into a text field
- `ext.fdb.scroll` — perform a swipe/scroll gesture
- `ext.fdb.swipe` — swipe widgets (PageView, Dismissible)
- `ext.fdb.selectionMode` — toggle widget selection overlay
