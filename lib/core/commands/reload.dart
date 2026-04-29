import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_lifecycle_events.dart';

/// Input parameters for [reloadApp]. Empty record because `fdb reload` takes
/// no arguments today.
typedef ReloadInput = ();

/// Result of a [reloadApp] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class ReloadResult extends CommandResult {
  const ReloadResult();
}

/// The hot reload completed successfully.
class ReloadSuccess extends ReloadResult {
  final int durationMs;
  const ReloadSuccess(this.durationMs);
}

/// No PID file was found — the app was not running and no session exists.
class ReloadNoSession extends ReloadResult {
  const ReloadNoSession();
}

/// The app process is not alive.
class ReloadProcessDead extends ReloadResult {
  final int pid;
  const ReloadProcessDead(this.pid);
}

/// The reload signal was sent but no Flutter frame event was received within
/// the timeout.
class ReloadFailed extends ReloadResult {
  const ReloadFailed();
}

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
