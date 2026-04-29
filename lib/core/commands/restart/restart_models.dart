import 'package:fdb/core/models/command_result.dart';

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
