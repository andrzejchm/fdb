import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/kill/kill_models.dart';
import 'package:fdb/core/controller_client.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/kill/kill_models.dart';

/// Stops the running app process referenced by the session's PID file.
///
/// Returns [KillSuccess] on success, [KillNoSession] if no PID file is
/// present, or [KillFailed] if the process refused to die after `SIGKILL`.
Future<KillResult> killApp(KillInput _) async {
  final controllerPid = readControllerPid();
  if (controllerPid == null) return const KillNoSession();

  // Kill the log collector first so it stops writing to the log file.
  _killLogCollector();

  try {
    final response = await sendControllerCommand(
      'kill',
      timeout: const Duration(seconds: killTimeoutSeconds),
    );
    if (response['ok'] == true) {
      cleanupTempFiles();
      return const KillSuccess();
    }
  } on ControllerUnavailable {
    return const KillFailed();
  }

  return const KillFailed();
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
