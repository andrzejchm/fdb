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
