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
