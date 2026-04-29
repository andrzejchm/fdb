import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/longpress.dart';

/// CLI adapter for `fdb longpress`. Accepts widget selector flags, coordinate
/// flags, and an optional `--duration` flag (default 500 ms).
///
/// Emits one of:
///   `LONG_PRESSED=type X=x Y=y`                                  (success)
///   `ERROR: fdb_helper not detected in running app. ...`         (no helper)
///   `ERROR: message`                                              (error)
///   (AppDiedException rethrown for dispatcher's _formatAppDied)  (app died)
Future<int> runLongpressCli(List<String> args) async {
  final parser = ArgParser()
    ..addOption('text', help: 'Match widget by text')
    ..addOption('key', help: 'Match widget by key')
    ..addOption('type', help: 'Match widget by type')
    ..addOption('index', help: 'Index when multiple widgets match')
    ..addOption('x', help: 'Absolute X coordinate')
    ..addOption('y', help: 'Absolute Y coordinate')
    ..addOption('at', help: 'Coordinates as x,y (e.g. 200,400)')
    ..addOption('duration', help: 'Hold duration in milliseconds (default: 500)')
    ..addOption('timeout', help: 'Timeout in seconds (default: 5)');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  String? text = results['text'] as String?;
  String? key = results['key'] as String?;
  String? type = results['type'] as String?;
  int? index;
  double? x;
  double? y;
  var usedAt = false;
  var timeoutSeconds = 5;
  var durationMs = 500;

  // Parse --index
  final rawIndex = results['index'] as String?;
  if (rawIndex != null) {
    index = int.tryParse(rawIndex);
    if (index == null) {
      stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
      return 1;
    }
  }

  // Parse --x
  final rawX = results['x'] as String?;
  if (rawX != null) {
    x = double.tryParse(rawX);
    if (x == null) {
      stderr.writeln('ERROR: Invalid value for --x: $rawX');
      return 1;
    }
  }

  // Parse --y
  final rawY = results['y'] as String?;
  if (rawY != null) {
    y = double.tryParse(rawY);
    if (y == null) {
      stderr.writeln('ERROR: Invalid value for --y: $rawY');
      return 1;
    }
  }

  // Parse --at
  final rawAt = results['at'] as String?;
  if (rawAt != null) {
    final parsed = parseXY(rawAt);
    if (parsed == null) {
      stderr.writeln(
        'ERROR: Invalid --at value: "$rawAt". Expected format: x,y (e.g. 200,400).',
      );
      return 1;
    }
    x = parsed.$1;
    y = parsed.$2;
    usedAt = true;
  }

  // Parse --duration
  final rawDuration = results['duration'] as String?;
  if (rawDuration != null) {
    final parsed = int.tryParse(rawDuration);
    if (parsed == null) {
      stderr.writeln('ERROR: Invalid value for --duration: $rawDuration');
      return 1;
    }
    if (parsed <= 0) {
      stderr.writeln('ERROR: --duration must be a positive integer');
      return 1;
    }
    durationMs = parsed;
  }

  // Parse --timeout
  final rawTimeout = results['timeout'] as String?;
  if (rawTimeout != null) {
    final parsed = int.tryParse(rawTimeout);
    if (parsed == null) {
      stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
      return 1;
    }
    timeoutSeconds = parsed;
  }

  // Cross-flag validation
  final hasCoords = x != null && y != null;
  final hasSelector = text != null || key != null || type != null;

  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together');
    return 1;
  }

  if (usedAt && hasSelector) {
    stderr.writeln('ERROR: --at cannot be combined with --key, --text, or --type.');
    return 1;
  }

  if (!hasSelector && !hasCoords) {
    stderr.writeln('ERROR: Provide --text, --key, --type, --at, or --x/--y');
    return 1;
  }

  final result = await longpressWidget((
    text: text,
    key: key,
    type: type,
    index: index,
    x: x,
    y: y,
    usedAt: usedAt,
    timeoutSeconds: timeoutSeconds,
    durationMs: durationMs,
  ));
  return _format(result);
}

int _format(LongpressResult result) {
  switch (result) {
    case LongpressSuccess(:final widgetType, :final x, :final y):
      stdout.writeln('LONG_PRESSED=$widgetType X=$x Y=$y');
      return 0;
    case LongpressNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case LongpressRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case LongpressUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.longPress: $raw');
      return 1;
    case LongpressAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case LongpressError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
