import 'package:fdb/core/commands/describe/describe.dart';
import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:fdb/core/describe_ref.dart';
import 'package:fdb/core/gesture_retry.dart';
import 'package:fdb/src/controller/commands/fdb_tap.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/tap/tap_models.dart';

typedef FdbHelperChecker = Future<String?> Function();
typedef FdbTapRunner = Future<FdbTapCommandResponse> Function(Map<String, dynamic> params);

/// Taps a widget or coordinates in the running Flutter app.
///
/// Handles selector-based taps, coordinate taps, and `@N` describe-ref taps.
/// A ref goes to fdb_helper as is: the helper resolves it to the widget it
/// names, or fails when that widget is gone, so a ref never lands on another
/// widget. The retry loop (500ms poll until deadline) runs inside this
/// function. Never throws; all error conditions are represented as sealed
/// result cases.
Future<TapResult> tapWidget(
  TapInput input, {
  FdbHelperChecker? checkFdbHelperFn,
  FdbTapRunner? fdbTapFn,
}) async {
  try {
    final isolateId = await (checkFdbHelperFn ?? checkFdbHelper)();
    if (isolateId == null) return const TapNoFdbHelper();

    final params = <String, dynamic>{'isolateId': isolateId};
    if (input.text != null) params['text'] = input.text;
    if (input.key != null) params['key'] = input.key;
    if (input.type != null) params['type'] = input.type;
    if (input.index != null) params['index'] = input.index.toString();
    if (input.x != null) params['x'] = input.x.toString();
    if (input.y != null) params['y'] = input.y.toString();
    if (input.ref != null) params['ref'] = input.ref.toString();
    if (input.expectText != null) params['expectText'] = input.expectText;
    if (input.expectType != null) params['expectType'] = input.expectType;

    final result = await _tapUntilDeadline(params, fdbTapFn ?? fdbTap, timeoutSeconds: input.timeoutSeconds);
    return switch (result) {
      TapSuccess(:final widgetType, :final x, :final y, :final warning, :final text) => TapSuccess(
          widgetType: input.usedAt ? 'coordinates' : widgetType,
          x: x ?? input.x ?? '',
          y: y ?? input.y ?? '',
          warning: warning,
          text: describeEntryText(text),
        ),
      TapRelayedError(:final message) => TapRelayedError(refAwareError(message, input.ref)),
      _ => result,
    };
  } on AppDiedException catch (e) {
    return TapAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return TapError(e.toString());
  }
}

/// Sends [params] to ext.fdb.tap, retrying every 500ms while the error is
/// retryable (see [isRetryableGestureError]) and the deadline has not passed.
///
/// On success, [TapSuccess.widgetType] is the helper's (or `widget`) and
/// x/y are the helper's (possibly null).
Future<TapResult> _tapUntilDeadline(
  Map<String, dynamic> params,
  FdbTapRunner tapRunner, {
  required int timeoutSeconds,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

  while (true) {
    final result = await tapRunner(params);

    if (result.isSuccess) {
      return TapSuccess(
        widgetType: result.widgetType ?? params['type'] as String? ?? 'widget',
        x: result.x,
        y: result.y,
        warning: result.warning,
        text: result.text,
      );
    }

    final error = result.error;
    if (error != null) {
      if (isRetryableGestureError(error) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      return TapRelayedError(error);
    }

    return TapUnexpectedResponse(result.unexpected.toString());
  }
}
