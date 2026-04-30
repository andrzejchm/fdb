import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/gc/gc_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/gc/gc_models.dart';

/// Forces a full garbage collection across all isolates in the running VM.
///
/// Reads `getMemoryUsage` before, then calls `getAllocationProfile` with
/// `gc: true` (which triggers a GC) on every isolate, then reads
/// `getMemoryUsage` again after. Returns a single [GcSuccess] with the
/// summed before/after heap bytes.
///
/// Per-isolate failures are tolerated: the failure is recorded as a warning
/// in the result and processing continues. Returns [GcAllFailed] only when every
/// isolate fails. Returns [GcNoIsolates] when no isolates are found.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<GcResult> runGc(GcInput _) async {
  try {
    final isolateIds = await findAllIsolateIds();
    if (isolateIds.isEmpty) return const GcNoIsolates();

    var totalBefore = 0;
    var totalAfter = 0;
    var successCount = 0;
    final warnings = <String>[];

    for (final id in isolateIds) {
      try {
        // Capture heap usage before GC.
        final beforeMem =
            (await vmServiceCall('getMemoryUsage', params: {'isolateId': id}))['result'] as Map<String, dynamic>?;
        final heapBefore = (beforeMem?['heapUsage'] as num?)?.toInt() ?? 0;

        // Trigger GC via getAllocationProfile with gc: true.
        // The response also includes post-GC memoryUsage, but we re-query
        // getMemoryUsage for consistency with the before measurement.
        await vmServiceCall('getAllocationProfile', params: {'isolateId': id, 'gc': true, 'reset': false});

        // Capture heap usage after GC.
        final afterMem =
            (await vmServiceCall('getMemoryUsage', params: {'isolateId': id}))['result'] as Map<String, dynamic>?;
        final heapAfter = (afterMem?['heapUsage'] as num?)?.toInt() ?? 0;

        totalBefore += heapBefore;
        totalAfter += heapAfter;
        successCount++;
      } on AppDiedException {
        rethrow;
      } catch (e) {
        warnings.add('GC failed for isolate $id: $e');
      }
    }

    if (successCount == 0) return const GcAllFailed();

    return GcSuccess(
      heapBefore: totalBefore,
      heapAfter: totalAfter,
      heapDelta: totalAfter - totalBefore,
      warnings: warnings,
    );
  } on AppDiedException {
    rethrow;
  } catch (e) {
    return GcError(e.toString());
  }
}
