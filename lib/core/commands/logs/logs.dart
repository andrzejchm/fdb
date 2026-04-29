import 'dart:async';
import 'dart:io';

import 'package:fdb/core/commands/logs/logs_models.dart';

export 'package:fdb/core/commands/logs/logs_models.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Reads filtered app logs from the fdb session log file.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<LogsResult> runLogs(LogsInput input) async {
  final file = File(input.logFilePath);
  if (!file.existsSync()) {
    return const LogsFileNotFound();
  }

  if (input.follow) {
    return _followStream(file: file, tag: input.tag);
  }

  return _snapshotStream(file: file, tag: input.tag, last: input.last);
}

// ---------------------------------------------------------------------------
// Implementations
// ---------------------------------------------------------------------------

/// Returns a [LogsStream] for snapshot mode.
///
/// Reads all lines, filters by [tag], caps to the last [last] lines, and
/// emits them via [Stream.fromIterable] so the CLI adapter can use the same
/// subscription pattern as follow mode.
Future<LogsResult> _snapshotStream({
  required File file,
  required String? tag,
  required int last,
}) async {
  final lines = file.readAsLinesSync();
  var filtered = tag != null ? lines.where((l) => l.contains(tag)).toList() : lines;
  if (filtered.length > last) {
    filtered = filtered.sublist(filtered.length - last);
  }
  return LogsStream(
    lines: Stream.fromIterable(filtered),
    exitCode: Future.value(0),
    cancel: () async {},
  );
}

/// Returns a [LogsStream] for follow mode.
///
/// Emits existing file content first (filtered by [tag]), then polls every
/// 500 ms for new bytes and emits any new lines (filtered by [tag]).
/// The stream runs until [cancel] is called.
LogsResult _followStream({required File file, required String? tag}) {
  final controller = StreamController<String>();
  var cancelled = false;
  final completer = Completer<int>();

  Future<void> cancel() async {
    if (cancelled) return;
    cancelled = true;
    if (!controller.isClosed) await controller.close();
    if (!completer.isCompleted) completer.complete(0);
  }

  // Start the polling loop asynchronously.
  () async {
    // Emit existing content first.
    final existing = file.readAsStringSync();
    if (existing.isNotEmpty) {
      final existingLines = existing.split('\n');
      for (final line in existingLines) {
        if (cancelled) break;
        if (tag == null || line.contains(tag)) {
          controller.add(line);
        }
      }
    }

    var offset = file.lengthSync();

    while (!cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (cancelled) break;

      final currentSize = file.lengthSync();
      if (currentSize > offset) {
        final raf = file.openSync();
        raf.setPositionSync(offset);
        final newBytes = raf.readSync(currentSize - offset);
        raf.closeSync();

        final newContent = String.fromCharCodes(newBytes);
        final newLines = newContent.split('\n');
        for (final line in newLines) {
          if (cancelled) break;
          if (line.isEmpty) continue;
          if (tag == null || line.contains(tag)) {
            controller.add(line);
          }
        }
        offset = currentSize;
      }
    }

    if (!controller.isClosed) await controller.close();
    if (!completer.isCompleted) completer.complete(0);
  }();

  // Wire up SIGINT so the process exits cleanly.
  ProcessSignal.sigint.watch().listen((_) async {
    await cancel();
  });

  return LogsStream(
    lines: controller.stream,
    exitCode: completer.future,
    cancel: cancel,
  );
}
