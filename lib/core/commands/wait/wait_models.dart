import 'package:fdb/core/models/command_result.dart';

/// The condition to wait for.
enum WaitCondition { present, absent }

/// Input parameters for [waitForWidget].
typedef WaitInput = ({
  String? text,
  String? key,
  String? type,
  String? route,
  WaitCondition condition,
  int timeoutMs,
});

/// Result of a [waitForWidget] invocation.
sealed class WaitResult extends CommandResult {
  const WaitResult();
}

/// The condition was met successfully.
class WaitConditionMet extends WaitResult {
  const WaitConditionMet({
    required this.condition,
    required this.selectorToken,
  });

  final WaitCondition condition;

  /// e.g. "KEY=foo" or "TEXT=bar"
  final String selectorToken;
}

/// fdb_helper was not detected in the running app.
class WaitNoFdbHelper extends WaitResult {
  const WaitNoFdbHelper();
}

/// The VM service returned an error message (e.g. timeout).
class WaitRelayedError extends WaitResult {
  const WaitRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class WaitUnexpectedResponse extends WaitResult {
  const WaitUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class WaitAppDied extends WaitResult {
  const WaitAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class WaitError extends WaitResult {
  const WaitError(this.message);
  final String message;
}
