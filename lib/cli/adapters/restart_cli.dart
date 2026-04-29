import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/restart/restart.dart';

/// CLI adapter for `fdb restart`. Accepts no flags; emits one of:
///
///   RESTARTED in `<ms>`ms                            (success)
///   ERROR: No PID file found. Is the app running?   (no session)
///   ERROR: Process `<pid>` is not running            (process dead)
///   RESTART_FAILED                                   (timeout)
Future<int> runRestartCli(List<String> args) => runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await restartApp(());
  return _format(result);
}

int _format(RestartResult result) {
  switch (result) {
    case RestartSuccess():
      stdout.writeln('RESTARTED in ${result.elapsedMs}ms');
      return 0;
    case RestartNoSession():
      stderr.writeln('ERROR: No PID file found. Is the app running?');
      return 1;
    case RestartProcessDead():
      stderr.writeln('ERROR: Process ${result.pid} is not running');
      return 1;
    case RestartFailed():
      stdout.writeln('RESTART_FAILED');
      return 1;
  }
}
