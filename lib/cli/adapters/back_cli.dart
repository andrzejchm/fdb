import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/back/back.dart';

/// CLI adapter for `fdb back`. Accepts no flags; emits one of:
///
///   POPPED                                                       (success)
///   ERROR: fdb_helper not detected in running app. ...          (no helper)
///   ERROR: Navigator could not pop — already at root            (at root)
///   ERROR: `<message>`                                           (VM error / generic)
///   (AppDiedException rethrown for dispatcher's `_formatAppDied`) (app died)
Future<int> runBackCli(List<String> args) => runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await navigateBack(());
  return _format(result);
}

int _format(BackResult result) {
  switch (result) {
    case BackPopped():
      stdout.writeln('POPPED');
      return 0;
    case BackNoHelper():
      stderr.writeln(
        'ERROR: fdb_helper not detected in running app. '
        'Add fdb_helper package to your Flutter app and call '
        'FdbBinding.ensureInitialized() in main()',
      );
      return 1;
    case BackAtRoot():
      stderr.writeln('ERROR: Navigator could not pop — already at root');
      return 1;
    case BackVmError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case BackUnexpectedResponse(:final raw):
      stderr.writeln('ERROR: Unexpected response from ext.fdb.back: $raw');
      return 1;
    case BackAppDied(:final logLines, :final reason):
      // Reconstruct and rethrow so bin/fdb.dart's existing _formatAppDied
      // handler produces the byte-identical output.
      throw AppDiedException(logLines: logLines, reason: reason);
    case BackError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
