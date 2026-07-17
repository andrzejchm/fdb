import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/swipe_path/swipe_path.dart';

/// CLI adapter for `fdb swipe-path`. Accepts --points and --precision.
///
/// Output contract:
///
///   SWIPED_PATH POINTS=n                    (success)
///   ERROR: --points is required             (missing --points)
///   ERROR: Invalid --points value: "...". Expected format: x1,y1;x2,y2;...
///          (at least 2 points).             (malformed / too few points)
///   ERROR: Invalid --precision value: "...". Expected a number.
///   ERROR: fdb_helper not detected in running app. ...  (no helper)
///   ERROR: message                          (relayed error / generic)
///   ERROR: Unexpected response from ext.fdb.swipePath: raw
///   (AppDiedException rethrown for dispatcher's _formatAppDied)
Future<int> runSwipePathCli(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'points',
      help: 'Semicolon-separated list of x,y screen-coordinate pairs (at least 2)',
    )
    ..addOption(
      'precision',
      help: 'Max pixel gap between synthesized move events (default: 8.0)',
    );
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final points = results.option('points');
  if (points == null) {
    stderr.writeln('ERROR: --points is required');
    return 1;
  }

  if (parsePointList(points) == null) {
    stderr.writeln(
      'ERROR: Invalid --points value: "$points". '
      'Expected format: x1,y1;x2,y2;... (at least 2 points).',
    );
    return 1;
  }

  final precisionRaw = results.option('precision');
  double? precision;
  if (precisionRaw != null) {
    precision = double.tryParse(precisionRaw);
    if (precision == null) {
      stderr.writeln('ERROR: Invalid --precision value: "$precisionRaw". Expected a number.');
      return 1;
    }
  }

  final result = await runSwipePath((points: points, precision: precision));
  return _format(result);
}

int _format(SwipePathResult result) {
  switch (result) {
    case SwipePathSuccess(:final pointCount):
      stdout.writeln('SWIPED_PATH POINTS=$pointCount');
      return 0;
    case SwipePathNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case SwipePathRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case SwipePathUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.swipePath: $raw');
      return 1;
    case SwipePathAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case SwipePathError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
