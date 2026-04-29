import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/process_utils.dart';

/// Input parameters for [getStatus]. Empty record because `fdb status` takes
/// no arguments.
typedef StatusInput = ();

/// Result of a [getStatus] invocation.
///
/// Always produced (no errors, no exceptions). The CLI adapter translates
/// the fields into the standard RUNNING=/PID=/VM_SERVICE_URI= output tokens.
class StatusResult extends CommandResult {
  final bool running;

  /// Non-null only when the PID file exists and the process is alive.
  final int? pid;

  /// Non-null only when [running] is true and a VM service URI is recorded.
  final String? vmServiceUri;

  const StatusResult({
    required this.running,
    this.pid,
    this.vmServiceUri,
  });
}

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
