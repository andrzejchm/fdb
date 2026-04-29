import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/scroll/scroll.dart' as core;

const _directions = ['up', 'down', 'left', 'right'];

const _usageMessage =
    'ERROR: Usage:\n'
    '  fdb scroll <up|down|left|right> [--at x,y] [--distance pixels]\n'
    '  fdb scroll --from x,y --to x,y';

/// CLI adapter for `fdb scroll`.
Future<int> runScrollCli(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(_usageMessage);
    return 1;
  }

  final parser =
      ArgParser()
        ..addOption('at')
        ..addOption('distance', defaultsTo: '200')
        ..addOption('from')
        ..addOption('to');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final fromRaw = results['from'] as String?;
  final toRaw = results['to'] as String?;
  final isRawMode = fromRaw != null || toRaw != null;

  final core.ScrollInput input;

  if (isRawMode) {
    // Raw coordinate mode
    if (results.rest.isNotEmpty) {
      final first = results.rest[0];
      if (_directions.contains(first.toLowerCase())) {
        stderr.writeln(
          'ERROR: --from/--to cannot be combined with a direction argument. '
          'Use either "fdb scroll <direction>" or "fdb scroll --from x,y --to x,y".',
        );
        return 1;
      }
      stderr.writeln('ERROR: Unknown flag: $first');
      return 1;
    }

    if (fromRaw == null || toRaw == null) {
      stderr.writeln('ERROR: --from and --to are both required in raw coordinate mode.');
      return 1;
    }

    final from = parseXY(fromRaw);
    if (from == null) {
      stderr.writeln('ERROR: Invalid --from value: "$fromRaw". Expected format: x,y (e.g. 100,400).');
      return 1;
    }

    final to = parseXY(toRaw);
    if (to == null) {
      stderr.writeln('ERROR: Invalid --to value: "$toRaw". Expected format: x,y (e.g. 300,100).');
      return 1;
    }

    input = core.ScrollRawMode(
      fromX: from.$1,
      fromY: from.$2,
      toX: to.$1,
      toY: to.$2,
    );
  } else {
    // Direction mode
    if (results.rest.isEmpty) {
      stderr.writeln(_usageMessage);
      return 1;
    }

    final direction = results.rest[0].toLowerCase();
    if (!_directions.contains(direction)) {
      stderr.writeln('ERROR: Direction must be one of: up, down, left, right');
      return 1;
    }

    final distanceRaw = results['distance'] as String;
    final distance = int.tryParse(distanceRaw);
    if (distance == null) {
      stderr.writeln('ERROR: Invalid value for --distance: $distanceRaw');
      return 1;
    }

    input = core.ScrollDirectionMode(
      direction: direction,
      at: results['at'] as String?,
      distance: distance,
    );
  }

  final result = await core.runScroll(input);
  return _format(result);
}

int _format(core.ScrollResult result) {
  switch (result) {
    case core.ScrollDirectionSuccess(:final direction, :final distance):
      stdout.writeln('SCROLLED=$direction');
      stdout.writeln('DISTANCE=$distance');
      return 0;
    case core.ScrollRawSuccess(:final fromX, :final fromY, :final toX, :final toY):
      stdout.writeln('SCROLLED=RAW');
      stdout.writeln('FROM=$fromX,$fromY');
      stdout.writeln('TO=$toX,$toY');
      return 0;
    case core.ScrollNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case core.ScrollRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case core.ScrollUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.scroll: $raw');
      return 1;
    case core.ScrollAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case core.ScrollError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
