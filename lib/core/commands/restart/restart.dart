import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/restart/restart_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_lifecycle_events.dart';

export 'package:fdb/core/commands/restart/restart_models.dart';

/// Hot-restarts the running Flutter app referenced by the session's PID file.
///
/// Returns [RestartSuccess] on success, [RestartNoSession] if no PID file is
/// present, [RestartProcessDead] if the process is no longer alive, or
/// [RestartFailed] if the restart did not complete within the timeout.
Future<RestartResult> restartApp(RestartInput _) async {
  final pid = readPid();
  if (pid == null) return const RestartNoSession();

  if (!isProcessAlive(pid)) return RestartProcessDead(pid: pid);

  final stopwatch = Stopwatch()..start();

  final completed = await waitForVmEventAfterSignal(
    streamIds: const ['Extension'],
    matches: isFlutterFirstFrameEvent,
    signal: () => Process.killPid(pid, ProcessSignal.sigusr2),
    timeout: const Duration(seconds: restartTimeoutSeconds),
  );

  if (completed) return RestartSuccess(elapsedMs: stopwatch.elapsedMilliseconds);
  return const RestartFailed();
}
