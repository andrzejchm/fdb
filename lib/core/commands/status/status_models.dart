import 'package:fdb/core/models/command_result.dart';

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
