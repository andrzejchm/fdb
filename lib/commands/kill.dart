import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

Future<int> runKill(List<String> args) async {
  final pid = readPid();
  if (pid == null) {
    stderr.writeln('ERROR: No PID file found. Is the app running?');
    return 1;
  }

  if (!isProcessAlive(pid)) {
    stdout.writeln('APP_KILLED');
    cleanupTempFiles();
    return 0;
  }

  // Send SIGTERM
  Process.killPid(pid, ProcessSignal.sigterm);

  // Wait for process to exit
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed.inSeconds < killTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!isProcessAlive(pid)) {
      cleanupTempFiles();
      stdout.writeln('APP_KILLED');
      return 0;
    }
  }

  // Force kill if still alive
  try {
    Process.killPid(pid, ProcessSignal.sigkill);
  } catch (_) {
    // Process may have already exited
  }

  cleanupTempFiles();

  if (isProcessAlive(pid)) {
    stderr.writeln('KILL_FAILED');
    return 1;
  }

  stdout.writeln('APP_KILLED');
  return 0;
}
