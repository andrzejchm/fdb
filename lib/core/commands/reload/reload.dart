import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/reload/reload_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_lifecycle_events.dart';

export 'package:fdb/core/commands/reload/reload_models.dart';

/// Triggers a hot reload of the running Flutter app via SIGUSR1.
///
/// Returns [ReloadSuccess] on success, [ReloadNoSession] if no PID file is
/// present, [ReloadProcessDead] if the process is not alive, or [ReloadFailed]
/// if the reload timed out.
Future<ReloadResult> reloadApp(ReloadInput _) async {
  final pid = readPid();
  if (pid == null) return const ReloadNoSession();

  if (!isProcessAlive(pid)) return ReloadProcessDead(pid);

  final stopwatch = Stopwatch()..start();

  final completed = await waitForVmEventAfterSignal(
    streamIds: const ['Extension'],
    matches: isFlutterFrameEvent,
    signal: () => Process.killPid(pid, ProcessSignal.sigusr1),
    timeout: const Duration(seconds: reloadTimeoutSeconds),
  );

  if (completed) return ReloadSuccess(stopwatch.elapsedMilliseconds);
  return const ReloadFailed();
}
