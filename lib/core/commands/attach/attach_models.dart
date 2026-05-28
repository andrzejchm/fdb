import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [attachApp].
typedef AttachInput = ({
  String? device,
  String? project,
  String? flavor,
  String? target,
  String? flutterSdk,
  String? sessionDir,
  String? appId,
  String? debugUrl,
  bool verbose,
  bool interactive,
});

/// Result of an [attachApp] invocation.
sealed class AttachResult extends CommandResult {
  const AttachResult();
}

/// App attached successfully. VM service is reachable at [vmServiceUri].
class AttachSuccess extends AttachResult {
  const AttachSuccess({
    required this.vmServiceUri,
    required this.pid,
    required this.logFilePath,
  });

  final String vmServiceUri;
  final String pid;
  final String logFilePath;
}

/// No --device was provided.
class AttachMissingDevice extends AttachResult {
  const AttachMissingDevice();
}

/// The controller process failed to start.
class AttachControllerFailed extends AttachResult {
  const AttachControllerFailed(this.details);

  final String details;
}

/// The attach process exited before the VM service URI appeared.
class AttachProcessDied extends AttachResult {
  const AttachProcessDied({
    this.noLogFile = false,
    this.fullLog = '',
  });

  final bool noLogFile;
  final String fullLog;
}

/// The VM service URI did not appear within the launch timeout.
class AttachTimeout extends AttachResult {
  const AttachTimeout({this.tailLogLines = const []});

  final List<String> tailLogLines;
}

/// Generic / unrecognised error.
class AttachError extends AttachResult {
  const AttachError(this.message);

  final String message;
}
