import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [tapWidget].
typedef TapInput = ({
  String? text,
  String? key,
  String? type,
  int? index,
  double? x,
  double? y,
  bool usedAt,
  int? ref,
  String? expectText,
  String? expectType,
  int timeoutSeconds,
});

/// Result of a [tapWidget] invocation.
sealed class TapResult extends CommandResult {
  const TapResult();
}

class TapSuccess extends TapResult {
  final String widgetType;
  final dynamic x;
  final dynamic y;
  final String? warning;

  /// For `@N` taps: the text `fdb describe` shows for the tapped widget.
  final String? text;
  const TapSuccess({
    required this.widgetType,
    required this.x,
    required this.y,
    this.warning,
    this.text,
  });
}

class TapNoFdbHelper extends TapResult {
  const TapNoFdbHelper();
}

class TapRelayedError extends TapResult {
  final String message;
  const TapRelayedError(this.message);
}

class TapUnexpectedResponse extends TapResult {
  final String raw;
  const TapUnexpectedResponse(this.raw);
}

class TapAppDied extends TapResult {
  final String? reason;
  final List<String> logLines;
  const TapAppDied({required this.logLines, this.reason});
}

class TapError extends TapResult {
  final String message;
  const TapError(this.message);
}
