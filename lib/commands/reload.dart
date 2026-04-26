import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';
import 'package:fdb/vm_lifecycle_events.dart';

Future<int> runReload(List<String> args) async {
  final pid = readPid();
  if (pid == null) {
    stderr.writeln('ERROR: No PID file found. Is the app running?');
    return 1;
  }

  if (!isProcessAlive(pid)) {
    stderr.writeln('ERROR: Process $pid is not running');
    return 1;
  }

  final stopwatch = Stopwatch()..start();

  final completed = await waitForVmEventAfterSignal(
    streamIds: const ['Extension'],
    matches: isFlutterFrameEvent,
    signal: () => Process.killPid(pid, ProcessSignal.sigusr1),
    timeout: const Duration(seconds: reloadTimeoutSeconds),
  );
  if (completed) {
    stdout.writeln('RELOADED in ${stopwatch.elapsedMilliseconds}ms');
    return 0;
  }

  stdout.writeln('RELOAD_FAILED');
  return 1;
}
