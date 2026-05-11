import 'dart:io';

import 'package:fdb/cli/cli_command.dart';
import 'package:fdb/core/app_died_exception.dart';

Future<int> runFdbCommand(CliCommand command, List<String> args) {
  final runner = command.runner;
  if (runner == null) {
    stderr.writeln('ERROR: ${command.wireName} is handled by the top-level dispatcher.');
    return Future.value(1);
  }
  return runner(args);
}

Future<int> runFdbCommandName(String command, List<String> args) {
  final parsed = CliCommand.fromWireName(command);
  if (parsed == null) {
    stderr.writeln('ERROR: Unknown command: $command');
    return Future.value(1);
  }
  return runFdbCommand(parsed, args);
}

void formatAppDied(AppDiedException e) {
  final reasonSuffix = e.reason != null ? ' REASON=${e.reason}' : '';
  stderr.writeln('ERROR: APP_DIED$reasonSuffix');

  if (e.logLines.isNotEmpty) {
    stderr.writeln('Last ${e.logLines.length} log lines:');
    for (final line in e.logLines) {
      stderr.writeln('  $line');
    }
  }

  stderr.writeln('See: fdb crash-report');
}
