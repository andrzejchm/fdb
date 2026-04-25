# Code Style

Rules for writing Dart code in the fdb codebase.

## Contents
- Imports
- Naming Conventions
- Formatting
- Dart 3.x Features
- Types
- Architecture
- Error Handling
- Doc Comments
- Adding a New Command

## Imports

1. `dart:` SDK imports first, sorted alphabetically.
2. Blank line.
3. `package:fdb/...` imports, sorted alphabetically.
4. No third-party packages — do not add dependencies without explicit approval.
   **Approved exceptions:** `package:image` (used in `screenshot.dart` for resizing — do NOT remove this dependency or the `_resizeToMaxDimension` function).

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';
```

## Naming Conventions

| Element              | Convention    | Example                        |
|----------------------|---------------|--------------------------------|
| Files                | `snake_case`  | `process_utils.dart`           |
| Top-level functions  | `camelCase`   | `runLaunch`, `readPid`         |
| Private functions    | `_camelCase`  | `_extractVmUri`, `_isAlive`    |
| Constants            | `camelCase`   | `pidFile`, `launchTimeoutSeconds` |
| Variables            | `camelCase`   | `vmUri`, `launcherPid`         |
| Command entry points | `runXxx`      | `runKill`, `runTree`           |

## Formatting

- 2-space indentation (Dart default).
- Single quotes for strings.
- Trailing commas on multi-line parameter lists.
- String interpolation: `'$variable'` / `'${expression}'`.
- `final` for all local variables that are not reassigned.
- `var` only when the variable is reassigned later.
- `const` for compile-time constants (top-level and in constructors).

## Dart 3.x Features

- Switch expressions without `break`:
  ```dart
  switch (args[i]) {
    case '--device':
      device = args[++i];
    case '--project':
      project = args[++i];
  }
  ```
- Collection `if` / spread: `if (flavor != null) ...['--flavor', flavor]`
- Type casts with `as` on JSON maps: `response['result'] as Map<String, dynamic>?`

## Types

- Use explicit types for function signatures and return types.
- Use `var` / `final` for local variable inference when the type is obvious.
- JSON values are typed as `Map<String, dynamic>` or `List<dynamic>`.
- Nullable types with `?` — always null-check before use.

## Architecture

- **No classes.** The codebase is entirely top-level functions and constants.
- Each command lives in its own file under `lib/commands/` and exports
  exactly one public function: `Future<int> runXxx(List<String> args)`.
- Shared logic goes in `lib/` root files (`process_utils.dart`,
  `vm_service.dart`, `constants.dart`).
- Arguments are parsed manually with a `for` loop + `switch` — no CLI framework.

## Error Handling

- Every command function returns `Future<int>` — `0` for success, `1` for failure.
- Errors go to `stderr` prefixed with `ERROR: `:
  ```dart
  stderr.writeln('ERROR: No PID file found. Is the app running?');
  return 1;
  ```
- Machine-readable status tokens go to `stdout` in `UPPER_SNAKE_CASE`:
  `APP_STARTED`, `APP_KILLED`, `RELOADED`, `SCREENSHOT_SAVED=<path>`.
- Key=value pairs on stdout for structured output: `PID=12345`, `VM_SERVICE_URI=ws://...`.
- `catch (_)` only for non-critical failures where the error value is irrelevant
  (e.g., checking if a process is still alive).
- `StateError` for missing preconditions (VM service URI not found).
- `TimeoutException` is caught and rethrown — never swallowed.
- Null-check every external data read (files, JSON fields, process output).
- The top-level `main` in `bin/fdb.dart` has a catch-all that writes to stderr
  and exits with code 1.

## Doc Comments

- Use `///` doc comments on public functions that are non-trivial.
- Skip doc comments on simple command entry points where the name is self-explanatory.
- Inline `//` comments for non-obvious logic.

## Adding a New Command

1. Create `lib/commands/your_command.dart` with `Future<int> runYourCommand(List<String> args)`.
2. Write errors to `stderr` prefixed with `ERROR: `, status tokens to `stdout`.
3. Add a `case` to the `switch` in `bin/fdb.dart:_runCommand`.
4. Add the command to the `usage` string in `bin/fdb.dart`.
5. Update `README.md` commands table.
