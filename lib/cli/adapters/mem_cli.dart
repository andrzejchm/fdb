import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/mem/mem.dart';

const _memUsage = '''
Usage: fdb mem [subcommand] [options]

Subcommands:
  (none)       Print per-isolate heap totals
  profile      Capture a full allocation profile to a JSON file
  diff         Diff two allocation profile files

Options (fdb mem):
  --json       Output machine-readable JSON

Options (fdb mem profile):
  --output <file>    (required) Path for the output JSON file
  --isolate <id>     Target a specific isolate (default: Flutter UI isolate)
  --all-isolates     Capture all isolates (one file per isolate)

Options (fdb mem diff <before.json> <after.json>):
  --sort count|bytes   Sort by instance count delta or byte delta (default: count)
  --top <n>            Show top N classes (default: 20)
  --all                Show all changed classes (overrides --top)
  --json               Output machine-readable JSON
''';

/// CLI entry point for `fdb mem [subcommand]`.
Future<int> runMemCli(List<String> args) async {
  if (args.isNotEmpty && (args[0] == '--help' || args[0] == '-h')) {
    stdout.writeln(_memUsage);
    return 0;
  }

  if (args.isEmpty) return _runMemTotals(args);

  switch (args[0]) {
    case 'profile':
      return _runMemProfile(args.sublist(1));
    case 'diff':
      return _runMemDiff(args.sublist(1));
    default:
      if (args[0].startsWith('-')) return _runMemTotals(args);
      stderr.writeln('ERROR: Unknown subcommand for fdb mem: ${args[0]}');
      stderr.writeln('Run `fdb mem --help` for usage.');
      return 1;
  }
}

// ---------------------------------------------------------------------------
// fdb mem — heap totals
// ---------------------------------------------------------------------------

Future<int> _runMemTotals(List<String> args) {
  final parser = ArgParser()..addFlag('json', negatable: false);
  return runCliAdapter(parser, args, (results) async {
    final result = await getHeapUsage(());
    return _formatMemResult(result, jsonMode: results['json'] as bool);
  });
}

int _formatMemResult(MemResult result, {required bool jsonMode}) {
  switch (result) {
    case MemSuccess(:final isolates):
      if (jsonMode) {
        stdout.writeln(jsonEncode({
          'isolates': [
            for (final i in isolates)
              {
                'isolateId': i.id,
                'name': i.name,
                'heapUsage': i.heapUsage,
                'externalUsage': i.externalUsage,
                'heapCapacity': i.heapCapacity,
              },
          ],
        }));
      } else {
        _printHeapTable(isolates);
      }
      return 0;
    case MemAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case MemError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

void _printHeapTable(List<IsolateHeapInfo> isolates) {
  if (isolates.isEmpty) {
    stdout.writeln('No isolates found.');
    return;
  }

  const nameW = 30;
  const numW = 12;
  String nameCol(String s) => s.padRight(nameW);
  String numCol(String s) => s.padLeft(numW);

  final header = '${nameCol('isolate')}${numCol('heapUsage')}${numCol('external')}${numCol('capacity')}';
  final divider = '-' * header.length;
  stdout.writeln(header);
  stdout.writeln(divider);

  var totalHeap = 0;
  var totalExternal = 0;
  var totalCapacity = 0;

  for (final iso in isolates) {
    stdout.writeln(
      '${nameCol(iso.name)}${numCol(fmtBytes(iso.heapUsage))}${numCol(fmtBytes(iso.externalUsage))}${numCol(fmtBytes(iso.heapCapacity))}',
    );
    totalHeap += iso.heapUsage;
    totalExternal += iso.externalUsage;
    totalCapacity += iso.heapCapacity;
  }

  stdout.writeln(divider);
  stdout.writeln(
    '${nameCol('TOTAL')}${numCol(fmtBytes(totalHeap))}${numCol(fmtBytes(totalExternal))}${numCol(fmtBytes(totalCapacity))}',
  );
}

// ---------------------------------------------------------------------------
// fdb mem profile — capture allocation profile
// ---------------------------------------------------------------------------

Future<int> _runMemProfile(List<String> args) {
  final parser = ArgParser()
    ..addOption('output')
    ..addOption('isolate')
    ..addFlag('all-isolates', negatable: false);

  return runCliAdapter(parser, args, (results) async {
    final outputPath = results.option('output');
    if (outputPath == null) {
      stderr.writeln('ERROR: --output <file> is required');
      return 1;
    }
    final allIsolates = results['all-isolates'] as bool;
    if (allIsolates && results.option('isolate') != null) {
      stderr.writeln('ERROR: --all-isolates and --isolate are mutually exclusive');
      return 1;
    }
    final result = await captureMemProfile((
      isolateId: results.option('isolate'),
      outputPath: outputPath,
      allIsolates: allIsolates,
    ));
    return _formatMemProfileResult(result);
  });
}

int _formatMemProfileResult(MemProfileResult result) {
  switch (result) {
    case MemProfileSuccess(:final outputPath, :final classCount, :final isolateName):
      stdout.writeln('MEM_PROFILE_SAVED=$outputPath');
      stdout.writeln('CLASSES=$classCount');
      stdout.writeln('ISOLATE=$isolateName');
      return 0;
    case MemProfileMultiSuccess(:final outputPaths, :final isolateNames, :final classCount):
      for (var i = 0; i < outputPaths.length; i++) {
        stdout.writeln('MEM_PROFILE_SAVED=${outputPaths[i]}');
        stdout.writeln('ISOLATE=${isolateNames[i]}');
      }
      stdout.writeln('TOTAL_CLASSES=$classCount');
      return 0;
    case MemProfileIsolateNotFound(:final requestedId):
      stderr.writeln(
        'ERROR: Isolate "$requestedId" not found. '
        'Run `fdb mem --json` and use the "isolateId" field as the --isolate value.',
      );
      return 1;
    case MemProfileAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case MemProfileError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

// ---------------------------------------------------------------------------
// fdb mem diff — diff two allocation profiles
// ---------------------------------------------------------------------------

Future<int> _runMemDiff(List<String> args) {
  final parser = ArgParser()
    ..addOption('sort', defaultsTo: 'count', allowed: ['count', 'bytes'])
    ..addOption('top', defaultsTo: '20')
    ..addFlag('all', negatable: false)
    ..addFlag('json', negatable: false);

  return runCliAdapter(parser, args, (results) async {
    final positional = results.rest;
    if (positional.length < 2) {
      stderr.writeln(
        'ERROR: fdb mem diff requires two positional arguments: <before.json> <after.json>',
      );
      return 1;
    }

    final showAll = results['all'] as bool;
    int? topN;
    if (!showAll) {
      final rawTop = results.option('top') ?? '20';
      topN = int.tryParse(rawTop);
      if (topN == null || topN < 1) {
        stderr.writeln('ERROR: --top must be a positive integer, got "$rawTop"');
        return 1;
      }
    }

    final result = await diffMemProfiles((
      beforePath: positional[0],
      afterPath: positional[1],
      topN: topN,
      sort: results.option('sort') == 'bytes' ? MemDiffSort.bytes : MemDiffSort.count,
    ));
    return _formatMemDiffResult(result, jsonMode: results['json'] as bool, topN: topN);
  });
}

int _formatMemDiffResult(MemDiffResult result, {required bool jsonMode, int? topN}) {
  switch (result) {
    case MemDiffSuccess(:final diffs, :final beforeIsolateName, :final afterIsolateName, :final sort):
      if (jsonMode) {
        stdout.writeln(jsonEncode({
          'beforeIsolate': beforeIsolateName,
          'afterIsolate': afterIsolateName,
          'diffs': [
            for (final d in diffs)
              {
                'className': d.className,
                'libraryUri': d.libraryUri,
                'instancesBefore': d.instancesBefore,
                'instancesAfter': d.instancesAfter,
                'instanceDelta': d.instanceDelta,
                'bytesBefore': d.bytesBefore,
                'bytesAfter': d.bytesAfter,
                'bytesDelta': d.bytesDelta,
              },
          ],
        }));
      } else {
        _printDiffTable(diffs, sort: sort, topN: topN);
      }
      return 0;
    case MemDiffReadError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case MemDiffIsolateMismatch(:final beforeIsolateName, :final afterIsolateName):
      stderr.writeln(
        'ERROR: Profiles come from different isolates '
        '("$beforeIsolateName" vs "$afterIsolateName"). '
        'Capture both profiles from the same isolate to diff them.',
      );
      return 1;
    case MemDiffError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

void _printDiffTable(List<ClassDiff> diffs, {required MemDiffSort sort, int? topN}) {
  if (diffs.isEmpty) {
    stdout.writeln('No allocation changes between the two profiles.');
    return;
  }
  final countLabel = topN == null ? 'All ${diffs.length}' : 'Top ${diffs.length}';
  final sortLabel = sort == MemDiffSort.bytes ? 'byte delta' : 'instance count delta';
  stdout.writeln('$countLabel changed classes (by $sortLabel):');

  for (final d in diffs) {
    if (sort == MemDiffSort.bytes) {
      final sign = d.bytesDelta >= 0 ? '+' : '';
      stdout.writeln(
        '  ${'$sign${d.bytesDelta}'.padLeft(12)}  ${d.className.padRight(40)}  ${fmtBytes(d.bytesBefore)} -> ${fmtBytes(d.bytesAfter)}',
      );
    } else {
      final sign = d.instanceDelta >= 0 ? '+' : '';
      stdout.writeln(
        '  ${'$sign${d.instanceDelta}'.padLeft(5)}  ${d.className.padRight(40)}  ${d.instancesBefore} -> ${d.instancesAfter}',
      );
    }
  }
}
