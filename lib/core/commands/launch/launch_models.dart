import 'package:fdb/core/models/command_result.dart';

// ---------------------------------------------------------------------------
// Input / Result types
// ---------------------------------------------------------------------------

/// Input parameters for [launchApp].
typedef LaunchInput = ({
  String? device,
  String? project,
  String? flavor,
  String? target,
  String? flutterSdk,
  bool verbose,
});

/// Result of a [launchApp] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class LaunchResult extends CommandResult {
  const LaunchResult();
}

/// App launched successfully. VM service is reachable at [vmServiceUri].
class LaunchSuccess extends LaunchResult {
  final String vmServiceUri;
  final String pid;
  final String logFilePath;

  const LaunchSuccess({
    required this.vmServiceUri,
    required this.pid,
    required this.logFilePath,
  });
}

/// No --device was provided.
class LaunchMissingDevice extends LaunchResult {
  const LaunchMissingDevice();
}

/// The nohup launcher process failed to start (non-zero exit).
class LaunchLauncherFailed extends LaunchResult {
  final String details;

  const LaunchLauncherFailed(this.details);
}

/// The launcher PID could not be parsed from bash output.
class LaunchInvalidLauncherPid extends LaunchResult {
  const LaunchInvalidLauncherPid();
}

/// The flutter process exited before the VM service URI appeared in the log.
///
/// If [noLogFile] is true, no log file was created at all.
/// Otherwise [fullLog] contains the complete log content and [tailLogLines]
/// contains the last 10 lines (kept for backward compat with callers that
/// only need the tail).
class LaunchProcessDied extends LaunchResult {
  final List<String> tailLogLines;
  final bool noLogFile;

  /// Full log content passed to [analyzeLaunchFailure]. Empty when [noLogFile].
  final String fullLog;

  const LaunchProcessDied({
    this.tailLogLines = const [],
    this.noLogFile = false,
    this.fullLog = '',
  });
}

/// The VM service URI did not appear within [launchTimeoutSeconds].
/// [tailLogLines] contains the last 10 lines of the log (may be empty).
class LaunchTimeout extends LaunchResult {
  final List<String> tailLogLines;

  const LaunchTimeout({this.tailLogLines = const []});
}

/// Generic / unrecognised error.
class LaunchError extends LaunchResult {
  final String message;

  const LaunchError(this.message);
}
