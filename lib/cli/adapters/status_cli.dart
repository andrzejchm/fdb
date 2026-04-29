import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/status.dart';

/// CLI adapter for `fdb status`. Accepts no flags; emits:
///
/// ```
///   RUNNING=true|false            (always)
///   PID=<pid>                     (only if PID file present and process alive)
///   VM_SERVICE_URI=<uri>          (only if running and VM URI is known)
/// ```
Future<int> runStatusCli(List<String> args) =>
    runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await getStatus(());
  _format(result);
  return 0;
}

void _format(StatusResult result) {
  stdout.writeln('RUNNING=${result.running}');
  if (result.pid != null) stdout.writeln('PID=${result.pid}');
  if (result.vmServiceUri != null) stdout.writeln('VM_SERVICE_URI=${result.vmServiceUri}');
}
