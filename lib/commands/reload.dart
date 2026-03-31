import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

Future<int> runReload(List<String> args) async {
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

  // SIGUSR1 triggers hot reload
  Process.killPid(pid, ProcessSignal.sigusr1);

  // Wait for "Reloaded" in log
  while (stopwatch.elapsed.inSeconds < reloadTimeoutSeconds) {
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
    if (newContent.contains('Reloaded')) {
      stdout.writeln('RELOADED in ${stopwatch.elapsedMilliseconds}ms');
      return 0;
    }
  }

  stderr.writeln('ERROR: RELOAD_FAILED');
  return 1;
}
