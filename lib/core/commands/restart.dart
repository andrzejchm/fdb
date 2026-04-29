import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_lifecycle_events.dart';

/// Input parameters for [restartApp]. Empty record because `fdb restart` takes
/// no arguments today.
typedef RestartInput = ();

/// Result of a [restartApp] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class RestartResult extends CommandResult {
  const RestartResult();
}

/// The app was successfully hot-restarted; [elapsedMs] is the wall-clock time.
class RestartSuccess extends RestartResult {
  const RestartSuccess({required this.elapsedMs});

  final int elapsedMs;
}

/// No PID file was found — the app is not running.
class RestartNoSession extends RestartResult {
  const RestartNoSession();
}

/// The PID file exists but the process is no longer alive.
class RestartProcessDead extends RestartResult {
  const RestartProcessDead({required this.pid});

  final int pid;
}

/// The hot-restart signal was sent but the first-frame event was not received
/// within the timeout.
class RestartFailed extends RestartResult {
  const RestartFailed();
}

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
