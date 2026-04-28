# fdb_helper — Agent Guide

`fdb_helper` is the Flutter package that runs **inside the target app** and exposes VM service extensions that the fdb CLI calls. It is a Flutter package (not pure Dart), so Flutter/widget APIs are available.

## Package layout

```
lib/
  fdb_helper.dart              # Public export — re-exports FdbBinding only
  src/
    fdb_binding.dart           # THIN: singleton binding, extension registration only
    handlers/
      handler_utils.dart       # Shared: errorResponse()
      back_handler.dart        # ext.fdb.back
      clean_handler.dart       # ext.fdb.clean
      describe_handler.dart    # ext.fdb.describe + ext.fdb.elements
      input_handler.dart       # ext.fdb.enterText
      screenshot_handler.dart  # ext.fdb.screenshot
      scroll_handler.dart      # ext.fdb.scroll
      scroll_to_handler.dart   # ext.fdb.scrollTo
      shared_prefs_handler.dart# ext.fdb.sharedPrefs
      swipe_handler.dart       # ext.fdb.swipe
      tap_handler.dart         # ext.fdb.tap + ext.fdb.longPress
    element_tree_finder.dart   # findHittableElement, findScrollTargetElement, findInteractiveElements
    gesture_dispatcher.dart    # dispatchTap, dispatchScroll
    hit_test_utils.dart        # isElementHittable
    text_input_simulator.dart  # enterText
    widget_matcher.dart        # WidgetMatcher and subtypes
```

## Architecture rules

### FdbBinding is registration-only

`fdb_binding.dart` must contain **only**:
- The `FdbBinding` class and its singleton setup
- `initServiceExtensions` — registers extensions by name, delegates to handler functions
- `_registerExtension` — the hot-reload-safe wrapper around `developer.registerExtension`

**No handler logic, no helper functions, no imports of `dart:io`, `dart:ui`, `path_provider`, or `shared_preferences` belong in `fdb_binding.dart`.** If you find yourself adding logic there, you are in the wrong file.

### One file per command

Every VM service extension has its own file under `lib/src/handlers/`. The file exports **exactly one public function**:

```dart
Future<developer.ServiceExtensionResponse> handleXxx(
  String method,
  Map<String, String> params,
) async { ... }
```

All helpers and constants used only by that handler are **private** (`_prefixed`) and live in the same file. Do not share logic between handlers via the binding.

### Adding a new VM service extension

1. Create `lib/src/handlers/your_command_handler.dart` with a single public `handleYourCommand` function.
2. Add private helpers and constants to that same file.
3. Import only what the handler needs — do not import the entire `fdb_binding.dart`.
4. Register it in `fdb_binding.dart:initServiceExtensions` with one line: `_registerExtension('ext.fdb.yourCommand', handleYourCommand);`
5. Update the doc comment on `FdbBinding` listing the new extension.

### Shared utilities

Logic reused across handlers belongs in the existing `src/` helpers:

| File | What it provides |
|------|-----------------|
| `handler_utils.dart` | `errorResponse(String)` — standard error response |
| `element_tree_finder.dart` | `findHittableElement`, `findScrollTargetElement`, `findInteractiveElements`, `extractWidgetText` |
| `gesture_dispatcher.dart` | `dispatchTap`, `dispatchNativeTap`, `dispatchScroll` — all gesture dispatch helpers, including the Pigeon-bridged native tap path |
| `hit_test_utils.dart` | `isElementHittable` |
| `text_input_simulator.dart` | `enterText` |
| `widget_matcher.dart` | `WidgetMatcher` and all subtypes |

Add new shared helpers to the appropriate existing file. Only create a new shared file if it serves ≥ 2 handlers and clearly doesn't belong in any existing file.

`gesture_dispatcher.dart` is the home for all gesture-dispatch helpers
regardless of caller count — its purpose is to centralise the Flutter↔native
gesture boundary, including the Pigeon-bridged `dispatchNativeTap`. Single-
caller helpers there are acceptable when they belong to that boundary
conceptually (e.g. native-tap fallback handling, platform detection).

### No classes in handler files

Handler files use top-level functions only — no classes, no mixins, no inheritance. This matches the architecture of the CLI layer (`lib/commands/`).

### Imports per handler file

Each handler file imports only what it uses. Typical imports:

```dart
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../element_tree_finder.dart';
import '../gesture_dispatcher.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';
```

Platform-specific packages (`dart:io`, `path_provider`, `shared_preferences`) belong only in the handler that needs them — `clean_handler.dart` and `shared_prefs_handler.dart` respectively.
