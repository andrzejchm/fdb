import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/log_marker_detector.dart';
import 'package:fdb/process_utils.dart';

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

  final logBefore = File(logFile).existsSync() ? File(logFile).readAsStringSync() : '';

  final stopwatch = Stopwatch()..start();

  // SIGUSR1 triggers hot reload
  Process.killPid(pid, ProcessSignal.sigusr1);

  // Wait for "Reloaded" in log
  while (stopwatch.elapsed.inSeconds < reloadTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final logContent = File(logFile).readAsStringSync();
    if (didLogGainMarker(
      before: logBefore,
      after: logContent,
      marker: 'Reloaded',
    )) {
      stdout.writeln('RELOADED in ${stopwatch.elapsedMilliseconds}ms');
      return 0;
    }
  }

  stdout.writeln('RELOAD_FAILED');
  return 1;
}
