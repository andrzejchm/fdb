import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_lifecycle_events.dart';

Future<int> runRestart(List<String> args) async {
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
    matches: isFlutterFirstFrameEvent,
    signal: () => Process.killPid(pid, ProcessSignal.sigusr2),
    timeout: const Duration(seconds: restartTimeoutSeconds),
  );
  if (completed) {
    stdout.writeln('RESTARTED in ${stopwatch.elapsedMilliseconds}ms');
    return 0;
  }

  stdout.writeln('RESTART_FAILED');
  return 1;
}
