import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [runGc]. No fields required — GC runs on all isolates.
typedef GcInput = ();

/// Result of a [runGc] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class GcResult extends CommandResult {
  const GcResult();
}

/// GC completed successfully across at least one isolate.
class GcSuccess extends GcResult {
  const GcSuccess({
    required this.heapBefore,
    required this.heapAfter,
    required this.heapDelta,
    this.warnings = const [],
  });

  /// Total heap usage in bytes before GC (summed across all isolates).
  final int heapBefore;

  /// Total heap usage in bytes after GC (summed across all isolates).
  final int heapAfter;

  /// Delta in bytes (heapAfter - heapBefore; negative means reclaimed).
  final int heapDelta;

  /// Per-isolate warning messages for isolates that failed to GC.
  final List<String> warnings;
}

/// No isolates were found in the running VM.
class GcNoIsolates extends GcResult {
  const GcNoIsolates();
}

/// Every isolate failed to GC — nothing succeeded.
class GcAllFailed extends GcResult {
  const GcAllFailed();
}

/// Generic / unrecognised error.
class GcError extends GcResult {
  const GcError(this.message);

  final String message;
}
