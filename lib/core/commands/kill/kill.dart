import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/kill/kill_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/kill/kill_models.dart';

/// Stops the running app process referenced by the session's PID file.
///
/// Returns [KillSuccess] on success, [KillNoSession] if no PID file is
/// present, or [KillFailed] if the process refused to die after `SIGKILL`.
Future<KillResult> killApp(KillInput _) async {
  final pid = readPid();
  if (pid == null) return const KillNoSession();

  // Kill the log collector first so it stops writing to the log file.
  _killLogCollector();

  if (!isProcessAlive(pid)) {
    cleanupTempFiles();
    return const KillSuccess();
  }

  // Send SIGTERM
  Process.killPid(pid, ProcessSignal.sigterm);

  // Wait for process to exit
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed.inSeconds < killTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!isProcessAlive(pid)) {
      cleanupTempFiles();
      return const KillSuccess();
    }
  }

  // Force kill if still alive
  try {
    Process.killPid(pid, ProcessSignal.sigkill);
  } catch (_) {
    // Process may have already exited
  }

  cleanupTempFiles();

  if (isProcessAlive(pid)) return const KillFailed();
  return const KillSuccess();
}

void _killLogCollector() {
  final collectorPid = readLogCollectorPid();
  if (collectorPid == null) return;
  if (!isProcessAlive(collectorPid)) return;

  try {
    Process.killPid(collectorPid, ProcessSignal.sigterm);
  } catch (_) {
    // Already gone.
  }
}
