import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [getSelected]. Empty record because `fdb selected`
/// takes no arguments today.
typedef SelectedInput = ();

/// Result of a [getSelected] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class SelectedResult extends CommandResult {
  const SelectedResult();
}

/// No Flutter isolate was found in the running app.
class SelectedNoIsolate extends SelectedResult {
  const SelectedNoIsolate();
}

/// No widget is currently selected in the inspector.
class SelectedNone extends SelectedResult {
  const SelectedNone();
}

/// A widget is selected; carries its description and optional source location.
class SelectedWidget extends SelectedResult {
  const SelectedWidget({required this.description, this.location});

  /// The widget's description string (e.g. `"Text"`).
  final String description;

  /// Optional source location in `"file.dart:42"` or `"file.dart"` form.
  final String? location;
}

/// The app process died while fdb was communicating with it.
class SelectedAppDied extends SelectedResult {
  const SelectedAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class SelectedError extends SelectedResult {
  const SelectedError(this.message);
  final String message;
}
