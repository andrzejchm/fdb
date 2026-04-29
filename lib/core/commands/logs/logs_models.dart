import 'dart:async';

import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [runLogs].
typedef LogsInput = ({String? tag, int last, bool follow, String logFilePath});

// ---------------------------------------------------------------------------
// Result hierarchy
// ---------------------------------------------------------------------------

sealed class LogsResult extends CommandResult {
  const LogsResult();
}

/// Lines are available for consumption.
///
/// For snapshot mode, [lines] is a finite [Stream.fromIterable] and
/// [exitCode] resolves immediately to 0. [cancel] is a no-op.
///
/// For follow mode, [lines] is a live [StreamController] that polls the
/// log file every 500 ms. [cancel] stops polling and closes the controller.
/// [exitCode] resolves to 0 after [cancel] is called.
class LogsStream extends LogsResult {
  const LogsStream({
    required this.lines,
    required this.exitCode,
    required this.cancel,
  });

  final Stream<String> lines;
  final Future<int> exitCode;
  final Future<void> Function() cancel;
}

/// The log file was not found on disk.
class LogsFileNotFound extends LogsResult {
  const LogsFileNotFound();
}
