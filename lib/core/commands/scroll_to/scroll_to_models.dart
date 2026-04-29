import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [scrollTo].
typedef ScrollToInput = ({String? text, String? key, String? type, int? index});

/// Result of a [scrollTo] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class ScrollToResult extends CommandResult {
  const ScrollToResult();
}

/// The scroll succeeded and the target widget is now visible.
class ScrollToSuccess extends ScrollToResult {
  const ScrollToSuccess({required this.widgetType, required this.x, required this.y});
  final String widgetType;
  final double x;
  final double y;
}

/// fdb_helper was not detected in the running app.
class ScrollToNoFdbHelper extends ScrollToResult {
  const ScrollToNoFdbHelper();
}

/// The VM service returned a success status but x or y was missing.
class ScrollToMissingCoordinates extends ScrollToResult {
  const ScrollToMissingCoordinates();
}

/// The VM service returned an error message.
class ScrollToRelayedError extends ScrollToResult {
  const ScrollToRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class ScrollToUnexpectedResponse extends ScrollToResult {
  const ScrollToUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class ScrollToAppDied extends ScrollToResult {
  const ScrollToAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class ScrollToError extends ScrollToResult {
  const ScrollToError(this.message);
  final String message;
}
