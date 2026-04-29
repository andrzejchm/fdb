import 'package:fdb/core/commands/status/status_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/status/status_models.dart';

/// Checks whether the Flutter app session is running.
///
/// Never throws. Returns a [StatusResult] with [StatusResult.running] set to
/// `false` when there is no active session.
Future<StatusResult> getStatus(StatusInput _) async {
  final pid = readPid();
  final vmUri = readVmUri();

  // Primary check: PID file exists and process is alive.
  final pidAlive = pid != null && isProcessAlive(pid);
  var running = pidAlive;

  // Fallback: the PID file may be absent or stale (e.g. fdb launch was killed
  // by an agent timeout after the Flutter app started but before APP_STARTED
  // was printed, or before --pid-file was written by flutter run). In that
  // case, probe the VM service URI directly. If the WebSocket connects, the
  // app is alive even though the PID check failed.
  if (!running && vmUri != null) {
    running = await isVmServiceReachable(vmUri);
  }

  return StatusResult(
    running: running,
    pid: pidAlive ? pid : null,
    vmServiceUri: (running && vmUri != null) ? vmUri : null,
  );
}
