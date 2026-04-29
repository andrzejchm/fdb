import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [killApp]. Empty record because `fdb kill` takes
/// no arguments today.
typedef KillInput = ();

/// Result of a [killApp] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class KillResult extends CommandResult {
  const KillResult();
}

/// The app process was successfully terminated (or was already dead).
class KillSuccess extends KillResult {
  const KillSuccess();
}

/// No PID file was found — the app was not running and no session exists.
class KillNoSession extends KillResult {
  const KillNoSession();
}

/// The kill signal was sent but the process did not exit within the timeout
/// even after `SIGKILL`.
class KillFailed extends KillResult {
  const KillFailed();
}
