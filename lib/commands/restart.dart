import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

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

  final logBefore = File(logFile).existsSync() ? File(logFile).readAsStringSync() : '';

  final stopwatch = Stopwatch()..start();

  // SIGUSR2 triggers hot restart
  Process.killPid(pid, ProcessSignal.sigusr2);

  // Wait for "Restarted" in log
  while (stopwatch.elapsed.inSeconds < restartTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final logContent = File(logFile).readAsStringSync();
    final newContent = logContent.substring(logBefore.length);
    if (newContent.contains('Restarted')) {
      stdout.writeln('RESTARTED in ${stopwatch.elapsedMilliseconds}ms');
      return 0;
    }
  }

  stderr.writeln('RESTART_FAILED');
  return 1;
}
