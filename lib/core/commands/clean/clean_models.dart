import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [cleanApp]. Empty record because `fdb clean` takes
/// no arguments today.
typedef CleanInput = ();

/// Result of a [cleanApp] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class CleanResult extends CommandResult {
  const CleanResult();
}

/// Cache directories were successfully cleaned.
class CleanSuccess extends CleanResult {
  const CleanSuccess({required this.dirs, required this.deletedEntries});
  final List<String> dirs;
  final int deletedEntries;
}

/// fdb_helper was not detected in the running app.
class CleanNoFdbHelper extends CleanResult {
  const CleanNoFdbHelper();
}

/// The VM service extension returned an error message.
class CleanError extends CleanResult {
  const CleanError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class CleanUnexpectedResponse extends CleanResult {
  const CleanUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class CleanAppDied extends CleanResult {
  const CleanAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}
