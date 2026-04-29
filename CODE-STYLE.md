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
4. Do not add new third-party packages to `packages/fdb_helper/pubspec.yaml` under `dependencies:` unless the developer has explicitly approved it AND it is mandatory to implement the given feature. Dev dependencies in `fdb_helper` and any dependencies in the `fdb` CLI are not subject to this restriction.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/process_utils.dart';
```

### Layered import rules (enforced by convention)

- `lib/core/**` files MUST NOT import `package:args/...` or anything under `lib/cli/...`.
  Core is interface-agnostic: it knows nothing about CLI argument parsing or stdout/stderr token formatting.
- `lib/cli/adapters/<name>_cli.dart` MUST import the corresponding `lib/core/commands/<name>.dart`
  and translate sealed `*Result` cases into stdout/stderr writes.
- `bin/fdb.dart` imports CLI adapters only (never `lib/core/...` directly).

## Naming Conventions

| Element                | Convention      | Example                        |
|------------------------|-----------------|--------------------------------|
| Files                  | `snake_case`    | `process_utils.dart`           |
| Top-level functions    | `camelCase`     | `tapWidget`, `readPid`         |
| Private functions      | `_camelCase`    | `_extractVmUri`, `_isAlive`    |
| Constants              | `camelCase`     | `pidFile`, `launchTimeoutSeconds` |
| Variables              | `camelCase`     | `vmUri`, `launcherPid`         |
| Core command function  | verb            | `tapWidget`, `killApp`, `reloadApp` |
| Core input typedef     | `<Cmd>Input`    | `TapInput`, `KillInput`        |
| Core sealed result     | `<Cmd>Result`   | `TapResult`, `KillResult`      |
| Core result variants   | `<Cmd><Outcome>`| `TapSuccess`, `KillNoSession`  |
| CLI adapter entry point| `run<Cmd>Cli`   | `runTapCli`, `runKillCli`      |

## Formatting

- 2-space indentation (Dart default).
- Single quotes for strings.
- Trailing commas on multi-line parameter lists.
- String interpolation: `'$variable'` / `'${expression}'`.
- `final` for all local variables that are not reassigned.
- `var` only when the variable is reassigned later.
- `const` for compile-time constants (top-level and in constructors).

## Dart 3.x Features

- Sealed classes for command results — exhaustive pattern matching at every adapter:
  ```dart
  sealed class KillResult { const KillResult(); }
  class KillSuccess extends KillResult { const KillSuccess(); }
  class KillNoSession extends KillResult { const KillNoSession(); }
  class KillFailed extends KillResult { const KillFailed(); }
  ```
- Switch expressions on sealed types (compile-time exhaustiveness):
  ```dart
  switch (result) {
    case KillSuccess(): stdout.writeln('APP_KILLED');
    case KillNoSession(): stderr.writeln('ERROR: No PID file found.');
    case KillFailed(): stderr.writeln('KILL_FAILED');
  }
  ```
- Records for typed inputs: `typedef KillInput = ();` or `typedef TapInput = ({String? text, String? key, ...});`
- Collection `if` / spread: `if (flavor != null) ...['--flavor', flavor]`
- Type casts with `as` on JSON maps: `response['result'] as Map<String, dynamic>?`

## Types

- Use explicit types for function signatures and return types.
- Use `var` / `final` for local variable inference when the type is obvious.
- JSON values are typed as `Map<String, dynamic>` or `List<dynamic>`.
- Nullable types with `?` — always null-check before use.

## Architecture

The codebase has two layers: a **core** layer (interface-agnostic business logic) and a **CLI adapter** layer (argument parsing + token formatting). The split is enforced by directory convention.

```
lib/
  core/                            # Interface-agnostic business logic
    commands/<name>.dart           # runXxx(<Name>Input) → <Name>Result (sealed)
    models/command_result.dart     # Marker base for sealed result hierarchies
    app_died_exception.dart        # Domain exception (used by VM service)
    process_utils.dart             # Shared I/O helpers (PID files, etc.)
    vm_service.dart                # WebSocket VM service client
    vm_lifecycle_events.dart
    launch_failure_analyzer.dart
  cli/                             # CLI adapter — translates results to UPPER_SNAKE_CASE tokens
    adapters/<name>_cli.dart       # runXxxCli(args) — ArgParser + format
    args_helpers.dart              # runCliAdapter, runSimpleCliAdapter, parseXY
  constants.dart                   # File paths, timeouts (used by both layers)
bin/
  fdb.dart                         # Dispatcher — wires command names to runXxxCli
```

### Core layer rules

- **No classes for behavior.** Sealed classes for command results AND data-only abstract base classes for sealed hierarchies are permitted — they carry no behavior, just typed data shapes.
- **No `dart:io` write to stdout/stderr.** Core never prints. Errors and outcomes flow back via the sealed result type.
- **No throws across the public API.** `runXxx` catches every exception and translates to a result variant. Domain exceptions like `AppDiedException` may be re-thrown in narrow scenarios where the dispatcher has special handling.
- **No `package:args` import.** ArgParser is a CLI concern.
- Each command file exports: a `<Name>Input` typedef (record), a sealed `<Name>Result` hierarchy, and a `Future<<Name>Result> <verbName>(<Name>Input input)` function.

### CLI adapter rules

- Each adapter file exports `Future<int> run<Cmd>Cli(List<String> args)`.
- Build an `ArgParser`, parse via `runCliAdapter` (which handles `--help` + `FormatException`), call the corresponding core function, pattern-match the sealed result, write tokens.
- Cross-flag validation (mutually exclusive, "exactly one of") happens in the adapter, NOT core.
- Required-option validation: explicit null-check on `results.option('name')`, NOT `mandatory: true`. Preserves verbatim `ERROR: --x is required` wording.
- The CLI adapter is the only layer that writes to stdout/stderr.

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

1. **Core**: Create `lib/core/commands/your_command.dart`:
   - `typedef YourCommandInput = ({...});` (or `()` if no input)
   - `sealed class YourCommandResult extends CommandResult { const YourCommandResult(); }` plus one variant per distinct outcome
   - `Future<YourCommandResult> yourCommandVerb(YourCommandInput input)` — pure logic, no stdio, no throws (catch and translate to a result variant)

2. **CLI adapter**: Create `lib/cli/adapters/your_command_cli.dart`:
   - Import `package:args/args.dart` and `package:fdb/cli/args_helpers.dart`
   - `Future<int> runYourCommandCli(List<String> args) => runCliAdapter(_buildParser(), args, _execute)`
   - `_buildParser()` declares all options (no `--help` — `runCliAdapter` handles that)
   - `_execute(ArgResults)`: cross-flag validation, build the typed input, call the core function, pattern-match the sealed result, write tokens, return exit code

3. **Dispatcher**: Add the case to `bin/fdb.dart:_runCommand` calling `runYourCommandCli`.

4. **Usage**: Add the command to the `usage` string in `bin/fdb.dart`.

5. **Docs**: Update `README.md` commands table.

### Tokens

- Machine-readable status tokens to `stdout`, UPPER_SNAKE_CASE:
  `APP_STARTED`, `APP_KILLED`, `RELOADED in <ms>ms`, `SCREENSHOT_SAVED=<path>`.
- Errors to `stderr` prefixed with `ERROR: `:
  ```dart
  stderr.writeln('ERROR: No PID file found. Is the app running?');
  return 1;
  ```
- Key=value pairs on stdout for structured output: `PID=12345`, `VM_SERVICE_URI=ws://...`.
- AI agents grep for these tokens — preserve byte-identically across refactors.

## fdb_helper architecture

`packages/fdb_helper/` is a Flutter package that runs inside the target app and exposes VM service extensions. It has its own architecture rules — see [`packages/fdb_helper/AGENTS.md`](packages/fdb_helper/AGENTS.md) for full details.

**Key rules (never violate these):**

- `fdb_binding.dart` is **registration-only** — no handler logic, no imports of `dart:io`, `dart:ui`, `path_provider`, or `shared_preferences`. It only calls `_registerExtension(...)`.
- Every VM service extension lives in its own file under `lib/src/handlers/`. The file exports exactly **one public function** `handleXxx(String method, Map<String, String> params)`.
- **No classes** in handler files — top-level functions only.
- Shared helpers (`errorResponse`, `findHittableElement`, `dispatchTap`, etc.) live in the existing `src/` utility files — not in the binding, not duplicated across handlers.
- Adding a new extension means: create `handlers/your_handler.dart`, add one `_registerExtension` line to `fdb_binding.dart`. Nothing else changes in the binding.
