import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [runSwipePath].
typedef SwipePathInput = ({
  String points, // semicolon-separated "x,y" pairs, already validated
  double? precision,
});

/// Result of a [runSwipePath] invocation.
sealed class SwipePathResult extends CommandResult {
  const SwipePathResult();
}

/// Swipe path succeeded.
class SwipePathSuccess extends SwipePathResult {
  const SwipePathSuccess({required this.pointCount});

  /// The number of points in the dispatched path.
  final int pointCount;
}

/// fdb_helper was not detected in the running app.
class SwipePathNoFdbHelper extends SwipePathResult {
  const SwipePathNoFdbHelper();
}

/// The VM extension returned a relayed error message.
class SwipePathRelayedError extends SwipePathResult {
  const SwipePathRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class SwipePathUnexpectedResponse extends SwipePathResult {
  const SwipePathUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class SwipePathAppDied extends SwipePathResult {
  const SwipePathAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class SwipePathError extends SwipePathResult {
  const SwipePathError(this.message);
  final String message;
}
