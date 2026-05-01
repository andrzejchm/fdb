import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/restart/restart_models.dart';
import 'package:fdb/core/controller_client.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/restart/restart_models.dart';

/// Hot-restarts the running Flutter app via the fdb controller.
///
/// Returns [RestartSuccess] on success, [RestartNoSession] if no PID file is
/// present, [RestartProcessDead] if the process is no longer alive, or
/// [RestartFailed] if the restart did not complete within the timeout.
Future<RestartResult> restartApp(RestartInput _) async {
  final stopwatch = Stopwatch()..start();
  try {
    await sendControllerCommand(
      'restart',
      timeout: const Duration(seconds: restartTimeoutSeconds),
    );
    return RestartSuccess(elapsedMs: stopwatch.elapsedMilliseconds);
  } on ControllerUnavailable {
    final pid = readControllerPid() ?? readPid();
    if (pid == null) return const RestartNoSession();
    if (!isProcessAlive(pid)) return RestartProcessDead(pid: pid);
    return const RestartFailed();
  }
}
