import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/reload/reload_models.dart';
import 'package:fdb/core/controller_client.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/reload/reload_models.dart';

/// Triggers a hot reload of the running Flutter app via the fdb controller.
///
/// Returns [ReloadSuccess] on success, [ReloadNoSession] if no PID file is
/// present, [ReloadProcessDead] if the process is not alive, or [ReloadFailed]
/// if the reload timed out.
Future<ReloadResult> reloadApp(ReloadInput _) async {
  final stopwatch = Stopwatch()..start();
  try {
    await sendControllerCommand(
      'reload',
      timeout: const Duration(seconds: reloadTimeoutSeconds),
    );
    return ReloadSuccess(stopwatch.elapsedMilliseconds);
  } on ControllerUnavailable {
    final pid = readControllerPid() ?? readPid();
    if (pid == null) return const ReloadNoSession();
    if (!isProcessAlive(pid)) return ReloadProcessDead(pid);
    return const ReloadFailed();
  }
}
