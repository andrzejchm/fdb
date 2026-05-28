import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [dumpHeap].
typedef HeapDumpInput = ({
  /// Path where the heap snapshot file will be written.
  String outputPath,

  /// Specific isolate to snapshot. When null, the main Flutter isolate is used.
  String? isolateId,

  /// When true, skip the pre-snapshot garbage collection step.
  bool skipGc,
});

/// Result of a [dumpHeap] invocation.
sealed class HeapDumpResult extends CommandResult {
  const HeapDumpResult();
}

/// Snapshot captured and written to [outputPath].
class HeapDumpSuccess extends HeapDumpResult {
  const HeapDumpSuccess({required this.outputPath, required this.bytes});

  /// Absolute path of the written snapshot file.
  final String outputPath;

  /// Total bytes written.
  final int bytes;
}

/// No Flutter isolate was found (app not running or no VM service).
class HeapDumpNoIsolate extends HeapDumpResult {
  const HeapDumpNoIsolate();
}

/// App terminated mid-operation.
class HeapDumpAppDied extends HeapDumpResult {
  const HeapDumpAppDied({required this.logLines, required this.reason});

  final List<String> logLines;
  final String? reason;
}

/// Generic or unexpected error.
class HeapDumpError extends HeapDumpResult {
  const HeapDumpError(this.message);

  final String message;
}
