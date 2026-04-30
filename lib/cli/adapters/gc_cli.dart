import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/gc/gc.dart';

/// CLI adapter for `fdb gc`.
///
/// Output contract (human-readable):
///
///   GC_COMPLETE HEAP_BEFORE=`bytes` HEAP_AFTER=`bytes` HEAP_DELTA=`bytes`
///
/// Output contract (`--json` / KEY=value):
///
///   HEAP_BEFORE=`bytes`
///   HEAP_AFTER=`bytes`
///   HEAP_DELTA=`bytes`
///
/// Error cases:
///
///   ERROR: No app is running.                     (no session / no isolates)
///   ERROR: All isolates failed to GC.             (all isolates errored)
///   ERROR: `message`                              (generic error)
Future<int> runGcCli(List<String> args) {
  final parser = ArgParser()
    ..addFlag('json', negatable: false, help: 'Output KEY=value tokens instead of human-readable summary');
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final jsonMode = results['json'] as bool;
  final result = await runGc(());
  return _format(result, jsonMode: jsonMode);
}

int _format(GcResult result, {required bool jsonMode}) {
  switch (result) {
    case GcSuccess(:final heapBefore, :final heapAfter, :final heapDelta, :final warnings):
      for (final w in warnings) {
        stderr.writeln('WARNING: $w');
      }
      if (jsonMode) {
        stdout.writeln('HEAP_BEFORE=$heapBefore');
        stdout.writeln('HEAP_AFTER=$heapAfter');
        stdout.writeln('HEAP_DELTA=$heapDelta');
      } else {
        final beforeStr = fmtBytes(heapBefore);
        final afterStr = fmtBytes(heapAfter);
        final deltaStr = fmtBytes(heapDelta.abs());
        final sign = heapDelta <= 0 ? '-' : '+';
        stdout.writeln('GC_COMPLETE HEAP_BEFORE=$beforeStr HEAP_AFTER=$afterStr HEAP_DELTA=$sign$deltaStr');
      }
      return 0;
    case GcNoIsolates():
      stderr.writeln('ERROR: No app is running.');
      return 1;
    case GcAllFailed():
      stderr.writeln('ERROR: All isolates failed to GC.');
      return 1;
    case GcError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
