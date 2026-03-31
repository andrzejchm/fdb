import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

Future<int> runKill(List<String> args) async {
  String? deviceId;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
    }
  }

  final session = resolveSession(deviceId);
  if (session == null) return 1;
  final device = session['deviceId'] as String;

  final pidRaw = session['pid'];
  final pid =
      pidRaw is int ? pidRaw : (pidRaw is String ? int.tryParse(pidRaw) : null);
  if (pid == null) {
    stderr.writeln('ERROR: No PID found in session. Is the app running?');
    return 1;
  }

  if (!isProcessAlive(pid)) {
    stdout.writeln('APP_KILLED');
    cleanupSession(device);
    return 0;
  }

  // Send SIGTERM
  Process.killPid(pid, ProcessSignal.sigterm);

  // Wait for process to exit
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed.inSeconds < killTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!isProcessAlive(pid)) {
      cleanupSession(device);
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

  cleanupSession(device);

  if (isProcessAlive(pid)) {
    stderr.writeln('ERROR: KILL_FAILED');
    return 1;
  }

  stdout.writeln('APP_KILLED');
  return 0;
}
