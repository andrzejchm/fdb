import 'package:fdb/core/models/command_result.dart';

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
