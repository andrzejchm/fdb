import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/clean/clean.dart';

/// CLI adapter for `fdb clean`. Accepts no flags; emits one of:
///
///   CLEANED                                                (success)
///   DIRS=`<comma-separated list>`                          (success, line 2)
///   DELETED_ENTRIES=`<count>`                              (success, line 3)
///   ERROR: fdb_helper not found in the running app. ...  (no helper)
///   ERROR: `<message>`                                     (VM error / generic)
///   ERROR: unexpected response: `<json>`                  (unexpected response)
///   (AppDiedException rethrown for dispatcher's `_formatAppDied`) (app died)
Future<int> runCleanCli(List<String> args) => runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await cleanApp(());
  return _format(result);
}

int _format(CleanResult result) {
  switch (result) {
    case CleanSuccess(:final dirs, :final deletedEntries):
      stdout.writeln('CLEANED');
      stdout.writeln('DIRS=${dirs.join(',')}');
      stdout.writeln('DELETED_ENTRIES=$deletedEntries');
      return 0;
    case CleanNoFdbHelper():
      stderr.writeln(
        'ERROR: fdb_helper not found in the running app. '
        'Add FdbBinding.ensureInitialized() to main().',
      );
      return 1;
    case CleanError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case CleanUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: unexpected response: $raw');
      return 1;
    case CleanAppDied(:final logLines, :final reason):
      // Reconstruct and rethrow so bin/fdb.dart's existing _formatAppDied
      // handler produces the byte-identical output.
      throw AppDiedException(logLines: logLines, reason: reason);
  }
}
