import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/input.dart';

/// CLI adapter for `fdb input`. Accepts optional selector flags and a
/// positional text argument; emits one of:
///
///   `INPUT=<fieldType> VALUE=<textToEnter>`                        (success)
///   `ERROR: No input text provided`                                (no positional)
///   `ERROR: Invalid value for --index: <raw>`                      (bad index)
///   `ERROR: fdb_helper not detected in running app. ...`           (no helper)
///   `ERROR: <message>`                                             (relayed / generic)
///   `ERROR: Unexpected response from ext.fdb.enterText: <raw>`     (unexpected)
///   (AppDiedException rethrown for dispatcher's `_formatAppDied`)  (app died)
Future<int> runInputCli(List<String> args) {
  final parser = ArgParser()
    ..addOption('text', help: 'Select field by its label text')
    ..addOption('key', help: 'Select field by its ValueKey string')
    ..addOption('type', help: 'Select field by widget type name')
    ..addOption('index', help: 'Select the Nth matching field (0-based)');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  // Parse --index manually so we can emit the exact error message.
  int? index;
  final rawIndex = results['index'] as String?;
  if (rawIndex != null) {
    index = int.tryParse(rawIndex);
    if (index == null) {
      stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
      return 1;
    }
  }

  // First positional argument is the text to enter.
  final textToEnter = results.rest.isNotEmpty ? results.rest.first : null;
  if (textToEnter == null) {
    stderr.writeln('ERROR: No input text provided');
    return 1;
  }

  final result = await enterText((
    text: results['text'] as String?,
    key: results['key'] as String?,
    type: results['type'] as String?,
    index: index,
    textToEnter: textToEnter,
  ));

  return _format(result);
}

int _format(InputResult result) {
  switch (result) {
    case InputSuccess(:final fieldType, :final value):
      stdout.writeln('INPUT=$fieldType VALUE=$value');
      return 0;
    case InputNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case InputRelayedError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case InputUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.enterText: $raw');
      return 1;
    case InputAppDied(:final logLines, :final reason):
      throw AppDiedException(logLines: logLines, reason: reason);
    case InputError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
