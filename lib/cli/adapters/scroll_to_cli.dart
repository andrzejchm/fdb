import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/scroll_to/scroll_to.dart';

/// CLI adapter for `fdb scroll-to`. Accepts --text, --key, --type, --index.
///
/// Output contract:
///
///   SCROLLED_TO=widgetType X=x Y=y        (success)
///   ERROR: Provide --text, --key, or --type  (no selector)
///   ERROR: fdb_helper not detected in running app. ...  (no helper)
///   ERROR: Unexpected response from ext.fdb.scrollTo: missing x or y  (missing coords)
///   ERROR: message                          (relayed error / generic)
///   ERROR: Unexpected response from ext.fdb.scrollTo: raw  (unexpected response)
///   (AppDiedException rethrown for dispatcher's _formatAppDied)
Future<int> runScrollToCli(List<String> args) {
  final parser = ArgParser()
    ..addOption('text', help: 'Match widget by text content')
    ..addOption('key', help: 'Match widget by ValueKey label')
    ..addOption('type', help: 'Match widget by type name')
    ..addOption('index', help: 'When multiple widgets match, pick the Nth (0-based)');
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final rawIndex = results['index'] as String?;
  int? index;
  if (rawIndex != null) {
    index = int.tryParse(rawIndex);
    if (index == null) {
      stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
      return 1;
    }
  }

  final text = results['text'] as String?;
  final key = results['key'] as String?;
  final type = results['type'] as String?;

  if (text == null && key == null && type == null) {
    stderr.writeln('ERROR: Provide --text, --key, or --type');
    return 1;
  }

  final result = await scrollTo((text: text, key: key, type: type, index: index));
  return _format(result);
}

int _format(ScrollToResult result) {
  switch (result) {
    case ScrollToSuccess(:final widgetType, :final x, :final y):
      stdout.writeln('SCROLLED_TO=$widgetType X=$x Y=$y');
      return 0;
    case ScrollToNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case ScrollToMissingCoordinates():
      stderr.writeln(
        'ERROR: Unexpected response from ext.fdb.scrollTo: missing x or y',
      );
      return 1;
    case ScrollToRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case ScrollToUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.scrollTo: $raw');
      return 1;
    case ScrollToAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case ScrollToError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
