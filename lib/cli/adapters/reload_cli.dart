import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/reload.dart';

/// CLI adapter for `fdb reload`. Accepts no flags; emits one of:
///
///   `RELOADED in <ms>ms`                             (success)
///   `ERROR: No PID file found. Is the app running?`  (no session)
///   `ERROR: Process <pid> is not running`            (process dead)
///   `RELOAD_FAILED`                                  (timeout)
Future<int> runReloadCli(List<String> args) =>
    runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await reloadApp(());
  return _format(result);
}

int _format(ReloadResult result) {
  switch (result) {
    case ReloadSuccess(:final durationMs):
      stdout.writeln('RELOADED in ${durationMs}ms');
      return 0;
    case ReloadNoSession():
      stderr.writeln('ERROR: No PID file found. Is the app running?');
      return 1;
    case ReloadProcessDead(:final pid):
      stderr.writeln('ERROR: Process $pid is not running');
      return 1;
    case ReloadFailed():
      stdout.writeln('RELOAD_FAILED');
      return 1;
  }
}
