import 'dart:async';

import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [runSyslog].
typedef SyslogInput = ({
  String since,
  bool sinceExplicit,
  String? predicate,
  int? last,
  bool follow,
});

// ---------------------------------------------------------------------------
// Result hierarchy
// ---------------------------------------------------------------------------

sealed class SyslogResult extends CommandResult {
  const SyslogResult();
}

/// The subprocess was started successfully.
///
/// [lines] emits one log line per event, already filtered by [predicate].
/// For non-follow mode, lines are also capped by [last] — the stream is finite
/// and completes after the subprocess exits.
/// For follow mode, the stream is infinite until [cancel] is called or the
/// subprocess exits.
///
/// [exitCode] resolves to the subprocess exit code when the process terminates
/// (0 if terminated via [cancel]).
///
/// [cancel] terminates the underlying subprocess (SIGTERM/kill). Safe to call
/// multiple times.
class SyslogStream extends SyslogResult {
  const SyslogStream({
    required this.lines,
    required this.exitCode,
    required this.cancel,
  });

  final Stream<String> lines;
  final Future<int> exitCode;
  final Future<void> Function() cancel;
}

/// A required platform tool was not found on PATH.
class SyslogToolMissing extends SyslogResult {
  const SyslogToolMissing({required this.tool, required this.hint});

  final String tool;
  final String hint;
}

/// A platform-level or validation error prevented syslog from running.
class SyslogError extends SyslogResult {
  const SyslogError(this.message);

  final String message;
}
