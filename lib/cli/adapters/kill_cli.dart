import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/kill/kill.dart';

/// CLI adapter for `fdb kill`. Accepts no flags; emits one of:
///
///   APP_KILLED                                    (success)
///   ERROR: No PID file found. Is the app running? (no session)
///   KILL_FAILED                                   (force-kill failed)
Future<int> runKillCli(List<String> args) =>
    runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await killApp(());
  return _format(result);
}

int _format(KillResult result) {
  switch (result) {
    case KillSuccess():
      stdout.writeln('APP_KILLED');
      return 0;
    case KillNoSession():
      stderr.writeln('ERROR: No PID file found. Is the app running?');
      return 1;
    case KillFailed():
      stderr.writeln('KILL_FAILED');
      return 1;
  }
}
