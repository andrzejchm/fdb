import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [doubleTap].
typedef DoubleTapInput = ({
  String? text,
  String? key,
  String? type,
  int? index,
  double? x,
  double? y,
  int timeoutSeconds,
});

/// Result of a [doubleTap] invocation.
sealed class DoubleTapResult extends CommandResult {
  const DoubleTapResult();
}

/// The double-tap succeeded.
class DoubleTapSuccess extends DoubleTapResult {
  const DoubleTapSuccess({
    required this.widgetType,
    required this.x,
    required this.y,
  });
  final String widgetType;
  final dynamic x;
  final dynamic y;
}

/// fdb_helper was not detected in the running app.
class DoubleTapNoFdbHelper extends DoubleTapResult {
  const DoubleTapNoFdbHelper();
}

/// The VM service returned an error message (after retries).
class DoubleTapRelayedError extends DoubleTapResult {
  const DoubleTapRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class DoubleTapUnexpectedResponse extends DoubleTapResult {
  const DoubleTapUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class DoubleTapAppDied extends DoubleTapResult {
  const DoubleTapAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class DoubleTapError extends DoubleTapResult {
  const DoubleTapError(this.message);
  final String message;
}
