import 'dart:io';

import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/select.dart';

/// CLI adapter for `fdb select on|off`.
///
/// Output contract:
///   SELECTION_MODE=ON   (success, enabled)
///   SELECTION_MODE=OFF  (success, disabled)
///   ERROR: Usage: fdb select on|off  (no args or invalid arg)
///   ERROR: No Flutter isolate found   (no isolate)
///   (AppDiedException rethrown for dispatcher's _formatAppDied) (app died)
///   ERROR: `<message>`                 (generic error)
Future<int> runSelectCli(List<String> args) => runSimpleCliAdapter(
      args,
      _execute,
      helpText: 'Usage: fdb select on|off',
    );

Future<int> _execute(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ERROR: Usage: fdb select on|off');
    return 1;
  }

  final mode = args[0].toLowerCase();
  if (mode != 'on' && mode != 'off') {
    stderr.writeln('ERROR: Usage: fdb select on|off');
    return 1;
  }

  final result = await toggleSelection((enabled: mode == 'on'));
  return _format(result);
}

int _format(SelectResult result) {
  switch (result) {
    case SelectSuccess(:final enabled):
      stdout.writeln('SELECTION_MODE=${enabled ? "ON" : "OFF"}');
      return 0;
    case SelectNoIsolate():
      stderr.writeln('ERROR: No Flutter isolate found');
      return 1;
    case SelectAppDied(:final logLines, :final reason):
      // Reconstruct and rethrow so bin/fdb.dart's existing _formatAppDied
      // handler produces the byte-identical output.
      throw AppDiedException(logLines: logLines, reason: reason);
    case SelectError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
