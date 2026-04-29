import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [navigateBack]. Empty record because `fdb back` takes
/// no arguments today.
typedef BackInput = ();

/// Result of a [navigateBack] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class BackResult extends CommandResult {
  const BackResult();
}

/// Navigator.maybePop() succeeded and the page was popped.
class BackPopped extends BackResult {
  const BackPopped();
}

/// fdb_helper was not detected in the running app.
class BackNoHelper extends BackResult {
  const BackNoHelper();
}

/// Navigator.maybePop() returned false — already at root, nothing to pop.
class BackAtRoot extends BackResult {
  const BackAtRoot();
}

/// The VM service returned an error message.
class BackVmError extends BackResult {
  const BackVmError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class BackUnexpectedResponse extends BackResult {
  const BackUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class BackAppDied extends BackResult {
  const BackAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class BackError extends BackResult {
  const BackError(this.message);
  final String message;
}
