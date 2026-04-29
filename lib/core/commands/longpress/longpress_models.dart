import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [longpressWidget].
typedef LongpressInput = ({
  String? text,
  String? key,
  String? type,
  int? index,
  double? x,
  double? y,
  bool usedAt,
  int timeoutSeconds,
  int durationMs,
});

/// Result of a [longpressWidget] invocation.
sealed class LongpressResult extends CommandResult {
  const LongpressResult();
}

class LongpressSuccess extends LongpressResult {
  /// 'coordinates' if [LongpressInput.usedAt] was true, otherwise the widget
  /// type returned by the VM extension (or a fallback).
  final String widgetType;
  final dynamic x;
  final dynamic y;
  const LongpressSuccess({
    required this.widgetType,
    required this.x,
    required this.y,
  });
}

class LongpressNoFdbHelper extends LongpressResult {
  const LongpressNoFdbHelper();
}

class LongpressRelayedError extends LongpressResult {
  final String message;
  const LongpressRelayedError(this.message);
}

class LongpressUnexpectedResponse extends LongpressResult {
  final String raw;
  const LongpressUnexpectedResponse(this.raw);
}

class LongpressAppDied extends LongpressResult {
  final List<String> logLines;
  final String? reason;
  const LongpressAppDied({required this.logLines, this.reason});
}

class LongpressError extends LongpressResult {
  final String message;
  const LongpressError(this.message);
}
