import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/heap_dump/heap_dump.dart';

const _heapUsage = '''
Usage: fdb heap [subcommand] [options]

Subcommands:
  dump    Capture a DevTools-loadable heap snapshot (.heapsnapshot)

Options (fdb heap dump):
  --output <file>    (required) Path for the output snapshot file
  --isolate <id>     Target a specific isolate (default: Flutter UI isolate)
  --no-gc            Skip the pre-snapshot garbage collection step
''';

/// CLI adapter for `fdb heap`.
///
/// Output contract:
///
///   SNAPSHOT_SAVED=`path`       (success)
///   Wrote `N MB`. Open in DevTools: Memory tab -> Import snapshot
///
/// Error cases:
///
///   ERROR: --output `path` is required            (missing output)
///   ERROR: No Flutter isolate found in running app  (no isolate)
///   ERROR: `message`                               (generic error)
Future<int> runHeapCli(List<String> args) async {
  if (args.isNotEmpty && (args[0] == '--help' || args[0] == '-h')) {
    stdout.writeln(_heapUsage);
    return 0;
  }

  if (args.isEmpty) {
    stderr.writeln('ERROR: Missing subcommand for fdb heap. Run `fdb heap --help` for usage.');
    return 1;
  }

  switch (args[0]) {
    case 'dump':
      return _runHeapDump(args.sublist(1));
    default:
      stderr.writeln('ERROR: Unknown subcommand for fdb heap: ${args[0]}');
      stderr.writeln('Run `fdb heap --help` for usage.');
      return 1;
  }
}

Future<int> _runHeapDump(List<String> args) {
  final parser = ArgParser()
    ..addOption('output', help: 'Path for the output snapshot file')
    ..addOption('isolate', help: 'Target a specific isolate ID (default: Flutter UI isolate)')
    ..addFlag('no-gc', negatable: false, help: 'Skip the pre-snapshot garbage collection step');

  return runCliAdapter(parser, args, _executeHeapDump);
}

Future<int> _executeHeapDump(ArgResults results) async {
  final outputPath = results.option('output');
  if (outputPath == null) {
    stderr.writeln('ERROR: --output <file> is required');
    return 1;
  }

  // Reject directories.
  final outputFile = File(outputPath);
  if (await outputFile.parent.exists() == false) {
    stderr.writeln('ERROR: Parent directory does not exist: ${outputFile.parent.path}');
    return 1;
  }
  if (await Directory(outputPath).exists()) {
    stderr.writeln('ERROR: --output path is a directory: $outputPath');
    return 1;
  }

  final skipGc = results['no-gc'] as bool;
  final isolateId = results.option('isolate');

  final result = await dumpHeap((outputPath: outputPath, isolateId: isolateId, skipGc: skipGc));
  return _format(result);
}

int _format(HeapDumpResult result) {
  switch (result) {
    case HeapDumpSuccess(:final outputPath, :final bytes):
      stdout.writeln('SNAPSHOT_SAVED=$outputPath');
      stdout.writeln('Wrote ${fmtBytes(bytes)}. Open in DevTools: Memory tab -> Import snapshot');
      return 0;
    case HeapDumpNoIsolate():
      stderr.writeln('ERROR: No Flutter isolate found in running app');
      return 1;
    case HeapDumpAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case HeapDumpError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
