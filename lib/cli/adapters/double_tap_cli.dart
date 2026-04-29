import 'dart:io';

import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/double_tap/double_tap.dart';

/// CLI adapter for `fdb double-tap`.
///
/// Output contract:
/// - `DOUBLE_TAPPED=type X=x Y=y` on success
/// - `ERROR: fdb_helper not detected in running app. ...` when no helper
/// - `ERROR: message` for relayed / generic errors
/// - `ERROR: Unexpected response from ext.fdb.doubleTap: raw` for bad response
/// - AppDiedException rethrown for dispatcher's `_formatAppDied`
Future<int> runDoubleTapCli(List<String> args) async {
  String? text;
  String? key;
  String? type;
  int? index;
  double? x;
  double? y;
  var timeoutSeconds = 5;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: fdb double-tap [--text <text>] [--key <key>] [--type <type>] '
          '[--index <n>] [--x <x> --y <y>] [--at x,y] [--timeout <seconds>]',
        );
        return 0;
      case '--text':
        text = args[++i];
      case '--key':
        key = args[++i];
      case '--type':
        type = args[++i];
      case '--index':
        final rawIndex = args[++i];
        index = int.tryParse(rawIndex);
        if (index == null) {
          stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
          return 1;
        }
      case '--x':
        final rawX = args[++i];
        x = double.tryParse(rawX);
        if (x == null) {
          stderr.writeln('ERROR: Invalid value for --x: $rawX');
          return 1;
        }
      case '--y':
        final rawY = args[++i];
        y = double.tryParse(rawY);
        if (y == null) {
          stderr.writeln('ERROR: Invalid value for --y: $rawY');
          return 1;
        }
      case '--at':
        final rawAt = args[++i];
        final coords = parseXY(rawAt);
        if (coords == null) {
          stderr.writeln('ERROR: Invalid value for --at: $rawAt. Expected format: x,y');
          return 1;
        }
        x = coords.$1;
        y = coords.$2;
      case '--timeout':
        final rawTimeout = args[++i];
        final parsed = int.tryParse(rawTimeout);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
          return 1;
        }
        timeoutSeconds = parsed;
      default:
        stderr.writeln('ERROR: Unknown flag: ${args[i]}');
        return 1;
    }
  }

  // Cross-flag validation.
  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together');
    return 1;
  }

  final hasCoords = x != null && y != null;
  final hasSelector = text != null || key != null || type != null;
  final selectorCount = [text, key, type].where((v) => v != null).length;

  if (selectorCount > 1 || hasSelector == hasCoords) {
    stderr.writeln(
      'ERROR: Provide exactly one target: --text, --key, --type, --x/--y, or --at',
    );
    return 1;
  }

  final result = await doubleTap((
    text: text,
    key: key,
    type: type,
    index: index,
    x: x,
    y: y,
    timeoutSeconds: timeoutSeconds,
  ));

  return _format(result);
}

int _format(DoubleTapResult result) {
  switch (result) {
    case DoubleTapSuccess(:final widgetType, :final x, :final y):
      stdout.writeln('DOUBLE_TAPPED=$widgetType X=$x Y=$y');
      return 0;
    case DoubleTapNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case DoubleTapRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case DoubleTapUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.doubleTap: $raw');
      return 1;
    case DoubleTapAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case DoubleTapError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
