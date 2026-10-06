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
  int? describeRef,
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

  /// Text of the tapped describe entry, for `@N` taps.
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

class TapRefNotFound extends TapResult {
  final int ref;
  const TapRefNotFound(this.ref);
}

/// The describe entry at `@N` is not the expected one (`--expect-text`,
/// `--expect-type`): the screen changed since the agent read its refs.
class TapRefMismatch extends TapResult {
  final int ref;
  final String type;
  final String? text;
  final String? expectedText;
  final String? expectedType;
  const TapRefMismatch({
    required this.ref,
    required this.type,
    required this.text,
    required this.expectedText,
    required this.expectedType,
  });
}

/// The describe entry at `@N` is not built on screen (an un-built list item).
class TapRefOffScreen extends TapResult {
  final int ref;
  final String type;
  final String? text;
  const TapRefOffScreen({required this.ref, required this.type, required this.text});
}

/// The widget at `@N` moved or disappeared between describe and the tap.
class TapRefMoved extends TapResult {
  final int ref;
  final String type;
  final String? text;
  const TapRefMoved({required this.ref, required this.type, required this.text});
}

class TapUnexpectedDescribeResponse extends TapResult {
  const TapUnexpectedDescribeResponse();
}

class TapRelayedDescribeError extends TapResult {
  final String message;
  const TapRelayedDescribeError(this.message);
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
