# Code Style

Rules for fdb's Dart codebase. For the layered architecture overview, see [`AGENTS.md`](AGENTS.md). For a worked example of adding a new command, see [`doc/adding-a-command.md`](doc/adding-a-command.md).

## Imports

- `dart:` first, blank line, `package:fdb/...` next, both alphabetised.
- `lib/core/**` MUST NOT import `package:args/...` or `package:fdb/cli/...`.
- `lib/cli/adapters/<name>_cli.dart` MUST import `package:fdb/core/commands/<name>.dart`.
- `bin/fdb.dart` imports CLI adapters only.
- Do NOT add new dependencies to `packages/fdb_helper/pubspec.yaml` without explicit approval.

## Naming

| Element                | Convention      | Example                            |
|------------------------|-----------------|------------------------------------|
| Files                  | `snake_case`    | `process_utils.dart`               |
| Top-level functions    | `camelCase`     | `tapWidget`, `readPid`             |
| Private functions      | `_camelCase`    | `_extractVmUri`                    |
| Constants              | `camelCase`     | `pidFile`, `launchTimeoutSeconds`  |
| Core verb function     | verb            | `tapWidget`, `killApp`             |
| Core input typedef     | `<Cmd>Input`    | `TapInput`, `KillInput`            |
| Core sealed result     | `<Cmd>Result`   | `TapResult`                        |
| Result variants        | `<Cmd><Outcome>`| `TapSuccess`, `KillNoSession`      |
| CLI adapter entry      | `run<Cmd>Cli`   | `runTapCli`                        |

## Formatting

- 2-space indent. Single quotes. Trailing commas on multi-line params.
- `final` for non-reassigned locals; `var` only when reassigned; `const` for compile-time constants.

## Architecture

Two layers, enforced by directory:

- `lib/core/**` — interface-agnostic. No `dart:io` writes to stdout/stderr. No `package:args`. Functions take typed inputs (records) and return sealed `<Cmd>Result` hierarchies. Never throw across the public API — catch and translate to a result variant. `AppDiedException` is the one allowed re-throw (dispatcher has special handling).
- `lib/cli/**` — translates results to UPPER_SNAKE_CASE stdout tokens and `ERROR:` stderr lines. Owns `package:args`. Cross-flag validation lives here, not in core.

### Per-command file split

Each command lives in its own directory with two files:

```
lib/core/commands/<name>/
  <name>.dart            # verb function + `export '<name>_models.dart';`
  <name>_models.dart     # <Cmd>Input typedef + sealed <Cmd>Result + variants
```

The verb file re-exports the models so adapters import only `<name>.dart` and get both. Adapters never import `<name>_models.dart` directly.

### Controller command files

Prefer one file per controller command under `lib/src/controller/commands/`.

Keep the request model, response model, and runner in the same file when the file stays readable. Do not create `request.dart`, `response.dart`, and `runner.dart` for every command by default.

Keep controller command files under 400 lines. If a command grows beyond that, split by responsibility:

- `<command>.dart` for orchestration and runner logic
- `<command>_request.dart` for request parsing and serialization
- `<command>_response.dart` for response parsing and serialization

Split files only when the consolidated command file becomes hard to read.

## CLI rules

- Use `runCliAdapter(parser, args, execute)` from `lib/cli/args_helpers.dart`. It handles `--help`/`-h` and `FormatException`. Adapters do NOT declare a `--help` flag themselves.
- Required options: explicit `if (results.option('x') == null) { stderr.writeln('ERROR: --x is required'); return 1; }`. NOT `mandatory: true` — preserves verbatim error wording.
- Use `runSimpleCliAdapter` for commands with no flags (only positional args).

## Output tokens

- stdout: UPPER_SNAKE_CASE machine-readable tokens (`APP_STARTED`, `TAPPED=<type> X=<x> Y=<y>`, `RELOADED in <ms>ms`).
- stderr: `ERROR: <message>` for failures; `WARNING: <message>` for non-fatal issues.
- AI agents grep for these — preserve byte-identically across refactors. Smoke tests in `Taskfile.yml` assert the exact strings.

## Error handling

- Every CLI adapter returns `Future<int>` — 0 success, 1 failure.
- Catch `FormatException` is centralised in `runCliAdapter`. Don't catch it per-command.
- `catch (_)` only for genuinely non-critical failures (e.g., probing process liveness).
- Null-check every external read (files, JSON fields, process output).
- `bin/fdb.dart` has a top-level catch-all for unexpected exceptions.

## Cross-platform host support

fdb runs as a host process on macOS, Linux, and Windows (separate from the *target device
platform*, which is read from `.fdb/platform.txt`). Do not shell out directly to POSIX-only
tools or assume POSIX signal semantics:

- Checking whether a tool is on `PATH`: use `isToolOnPath()` from `lib/core/process_utils.dart`
  (dispatches to `where` on Windows, `which` elsewhere). Do not add another private
  `_isToolOnPath`/`Process.runSync('which', ...)` copy.
- Checking whether a PID is alive: use `isProcessAlive()` from `lib/core/process_utils.dart`
  (dispatches to `tasklist` on Windows, `kill -0` elsewhere). Do not shell out to `kill -0`
  directly.
- `ProcessSignal.sigterm.watch()` (and `sigusr1`/`sigusr2`/`sigwinch`) throws a synchronous,
  unhandled exception on Windows — the Dart VM does not support watching them there. Guard any
  new `.watch()` call on one of these signals with `if (!Platform.isWindows)`. `sigint` (Ctrl-C)
  is watchable on all three platforms.

## Doc comments

- `///` on non-trivial public functions only.
- Avoid `<angle brackets>` in doc comments — wrap in backticks (`` `like this` ``) to avoid `unintended_html_in_doc_comment` lints.

## Adding a new command

1. Create `lib/core/commands/<name>/<name>_models.dart`: input typedef + sealed result.
2. Create `lib/core/commands/<name>/<name>.dart`: verb function + `export '<name>_models.dart';`.
3. Create `lib/cli/adapters/<name>_cli.dart`: ArgParser + `runCliAdapter` + result→token formatting.
4. Add the `case` in `bin/fdb.dart:_runCommand` calling `run<Name>Cli`.
5. Add the command to the `usage` string in `bin/fdb.dart`.
6. Update the commands table in `README.md`.

For a full worked example, see [`doc/adding-a-command.md`](doc/adding-a-command.md).

## fdb_helper

`packages/fdb_helper/` has its own conventions — see [`packages/fdb_helper/AGENTS.md`](packages/fdb_helper/AGENTS.md).
