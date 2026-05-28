import 'dart:io';

import 'package:fdb/core/commands/heap_dump/heap_dump_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/heap_dump/heap_dump_models.dart';

/// Captures a DevTools-loadable heap snapshot for the running Flutter app.
///
/// Unless [HeapDumpInput.skipGc] is true, calls `_collectAllGarbage` across
/// all isolates before taking the snapshot so the result reflects live state.
/// The leading underscore in `_collectAllGarbage` is intentional — it mirrors
/// the standard DevTools approach where pre-snapshot GC is an internal detail.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<HeapDumpResult> dumpHeap(HeapDumpInput input) async {
  try {
    // Resolve target isolate.
    final resolvedIsolateId = input.isolateId ?? await findFlutterIsolateId();
    if (resolvedIsolateId == null) return const HeapDumpNoIsolate();

    // _collectAllGarbage: force GC on all isolates so the snapshot reflects
    // only live objects. The underscore is intentional (DevTools convention).
    if (!input.skipGc) {
      final allIds = await findAllIsolateIds();
      for (final id in allIds) {
        try {
          await getAllocationProfile(id, gc: true, reset: false);
        } catch (_) {
          // Tolerate per-isolate GC failures (isolate may have already exited).
        }
      }
    }

    // Stream snapshot chunks directly to the output file.
    final outFile = await File(input.outputPath).open(mode: FileMode.write);
    try {
      final bytes = await streamHeapSnapshot(resolvedIsolateId, outFile);
      return HeapDumpSuccess(outputPath: input.outputPath, bytes: bytes);
    } finally {
      await outFile.close();
    }
  } on AppDiedException catch (e) {
    return HeapDumpAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return HeapDumpError(e.toString());
  }
}
