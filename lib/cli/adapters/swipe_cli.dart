import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/swipe.dart';

const _directions = ['up', 'down', 'left', 'right'];

const _usageMessage =
    'ERROR: Usage: fdb swipe <left|right|up|down> '
    '[--key KEY] [--text TEXT] [--type TYPE] [--at x,y] [--distance PIXELS]';

/// CLI adapter for `fdb swipe`.
Future<int> runSwipeCli(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(_usageMessage);
    return Future.value(1);
  }

  final parser =
      ArgParser()
        ..addOption('key')
        ..addOption('text')
        ..addOption('type')
        ..addOption('at')
        ..addOption('distance');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  if (results.rest.isEmpty) {
    stderr.writeln(_usageMessage);
    return 1;
  }

  final direction = results.rest[0].toLowerCase();
  if (!_directions.contains(direction)) {
    stderr.writeln('ERROR: Direction must be one of: up, down, left, right');
    return 1;
  }

  final distanceRaw = results['distance'] as String?;
  int? distance;
  if (distanceRaw != null) {
    distance = int.tryParse(distanceRaw);
    if (distance == null) {
      stderr.writeln('ERROR: Invalid value for --distance: $distanceRaw');
      return 1;
    }
  }

  final input = (
    direction: direction,
    key: results['key'] as String?,
    text: results['text'] as String?,
    type: results['type'] as String?,
    at: results['at'] as String?,
    distance: distance,
  );

  final result = await runSwipe(input);
  return _format(result);
}

int _format(SwipeResult result) {
  switch (result) {
    case SwipeSuccess(:final direction, :final actualDistance):
      stdout.writeln('SWIPED=$direction DISTANCE=$actualDistance');
      return 0;
    case SwipeNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case SwipeRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case SwipeUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.swipe: $raw');
      return 1;
    case SwipeAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case SwipeError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
