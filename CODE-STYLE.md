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

Each command file exports: `<Cmd>Input` typedef + sealed `<Cmd>Result` + `Future<<Cmd>Result> verb<Cmd>(<Cmd>Input)`.

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

## Doc comments

- `///` on non-trivial public functions only.
- Avoid `<angle brackets>` in doc comments — wrap in backticks (`` `like this` ``) to avoid `unintended_html_in_doc_comment` lints.

## Adding a new command

1. Create `lib/core/commands/<name>.dart`: input typedef + sealed result + verb function.
2. Create `lib/cli/adapters/<name>_cli.dart`: ArgParser + `runCliAdapter` + result→token formatting.
3. Add the `case` in `bin/fdb.dart:_runCommand` calling `run<Name>Cli`.
4. Add the command to the `usage` string in `bin/fdb.dart`.
5. Update the commands table in `README.md`.

For a full worked example, see [`doc/adding-a-command.md`](doc/adding-a-command.md).

## fdb_helper

`packages/fdb_helper/` has its own conventions — see [`packages/fdb_helper/AGENTS.md`](packages/fdb_helper/AGENTS.md).
