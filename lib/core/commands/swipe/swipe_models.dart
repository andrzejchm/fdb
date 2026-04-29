import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [runSwipe].
typedef SwipeInput = ({
  String direction, // already lowercased + validated
  String? key,
  String? text,
  String? type,
  String? at,
  int? distance,
});

/// Result of a [runSwipe] invocation.
sealed class SwipeResult extends CommandResult {
  const SwipeResult();
}

/// Swipe succeeded.
class SwipeSuccess extends SwipeResult {
  const SwipeSuccess({required this.direction, required this.actualDistance});

  /// Direction in uppercase (e.g. "LEFT").
  final String direction;

  /// The distance returned by the VM extension, or the requested distance, or
  /// an empty string when neither is available.
  final dynamic actualDistance;
}

/// fdb_helper was not detected in the running app.
class SwipeNoFdbHelper extends SwipeResult {
  const SwipeNoFdbHelper();
}

/// The VM extension returned a relayed error message.
class SwipeRelayedError extends SwipeResult {
  const SwipeRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class SwipeUnexpectedResponse extends SwipeResult {
  const SwipeUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class SwipeAppDied extends SwipeResult {
  const SwipeAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class SwipeError extends SwipeResult {
  const SwipeError(this.message);
  final String message;
}
