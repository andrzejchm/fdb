import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

Future<int> runRestart(List<String> args) async {
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
    stderr.writeln('ERROR: Process $pid is not running');
    return 1;
  }

  final log = logPath(device);
  var logBefore = File(log).existsSync() ? File(log).readAsStringSync() : '';

  final stopwatch = Stopwatch()..start();

  // SIGUSR2 triggers hot restart
  Process.killPid(pid, ProcessSignal.sigusr2);

  // Wait for "Restarted" in log
  while (stopwatch.elapsed.inSeconds < restartTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Guard the file read against FileSystemException (e.g. log rotated away).
    final String logContent;
    try {
      logContent = File(log).readAsStringSync();
    } on FileSystemException {
      break;
    }
    // If log was rotated, reset baseline and proceed with new content.
    if (logContent.length < logBefore.length) {
      logBefore = '';
    }
    final newContent = logContent.substring(logBefore.length);
    if (newContent.contains('Restarted')) {
      stdout.writeln('RESTARTED in ${stopwatch.elapsedMilliseconds}ms');
      return 0;
    }
  }

  stderr.writeln('ERROR: RESTART_FAILED');
  return 1;
}
