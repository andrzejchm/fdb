import 'package:fdb/core/commands/describe/describe.dart';
import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:fdb/core/gesture_retry.dart';
import 'package:fdb/src/controller/commands/fdb_describe.dart';
import 'package:fdb/src/controller/commands/fdb_tap.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/tap/tap_models.dart';

typedef FdbHelperChecker = Future<String?> Function();
typedef FdbTapRunner = Future<FdbTapCommandResponse> Function(Map<String, dynamic> params);
typedef FdbDescribeRunner = Future<FdbDescribeCommandResponse> Function(String isolateId);

/// Taps a widget or coordinates in the running Flutter app.
///
/// Handles selector-based taps, coordinate taps, and @N describe-ref taps.
/// The retry loop (500ms poll until deadline) runs inside this function.
/// Never throws; all error conditions are represented as sealed result cases.
Future<TapResult> tapWidget(
  TapInput input, {
  FdbHelperChecker? checkFdbHelperFn,
  FdbTapRunner? fdbTapFn,
  FdbDescribeRunner? fdbDescribeFn,
}) async {
  try {
    final isolateId = await (checkFdbHelperFn ?? checkFdbHelper)();
    if (isolateId == null) return const TapNoFdbHelper();

    if (input.describeRef != null) {
      return await _tapByRef(isolateId, input, fdbDescribeFn ?? fdbDescribe, fdbTapFn ?? fdbTap);
    }

    return await _tapWithParams(isolateId, input, fdbTapFn ?? fdbTap);
  } on AppDiedException catch (e) {
    return TapAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return TapError(e.toString());
  }
}

Future<TapResult> _tapWithParams(String isolateId, TapInput input, FdbTapRunner tapRunner) async {
  final params = <String, dynamic>{'isolateId': isolateId};
  if (input.text != null) params['text'] = input.text;
  if (input.key != null) params['key'] = input.key;
  if (input.type != null) params['type'] = input.type;
  if (input.index != null) params['index'] = input.index.toString();
  if (input.x != null) params['x'] = input.x.toString();
  if (input.y != null) params['y'] = input.y.toString();

  final result = await _tapUntilDeadline(
    params,
    tapRunner,
    timeoutSeconds: input.timeoutSeconds,
    isRetryable: isRetryableGestureError,
  );
  if (result is! TapSuccess) return result;
  return TapSuccess(
    widgetType: input.usedAt ? 'coordinates' : result.widgetType,
    x: result.x ?? input.x ?? '',
    y: result.y ?? input.y ?? '',
    warning: result.warning,
  );
}

/// Sends [params] to ext.fdb.tap, retrying every 500ms while the error is
/// [isRetryable] and the deadline has not passed.
///
/// On success, [TapSuccess.widgetType] is the helper's (or `widget`) and
/// x/y are the helper's (possibly null).
Future<TapResult> _tapUntilDeadline(
  Map<String, dynamic> params,
  FdbTapRunner tapRunner, {
  required int timeoutSeconds,
  required bool Function(String error) isRetryable,
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
      );
    }

    final error = result.error;
    if (error != null) {
      if (isRetryable(error) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      return TapRelayedError(error);
    }

    return TapUnexpectedResponse(result.unexpected.toString());
  }
}

/// Taps the widget behind describe entry `@N` of the current screen.
///
/// Refs are positions in a fresh describe, so they shift when the screen
/// changes. `expectText`/`expectType` catch that before anything is tapped.
/// The tap goes through the helper's selector path, pinned to the entry's
/// type, key and centre, so an off-screen or covered widget fails instead of
/// its raw coordinates being tapped.
Future<TapResult> _tapByRef(
  String isolateId,
  TapInput input,
  FdbDescribeRunner describeRunner,
  FdbTapRunner tapRunner,
) async {
  final ref = input.describeRef!;
  final describeResult = await describeRunner(isolateId);

  final snapshot = describeResult.snapshot;
  if (snapshot == null) {
    return const TapUnexpectedDescribeResponse();
  }

  if (describeResult.error != null) {
    return TapRelayedDescribeError(describeResult.error!);
  }

  final interactive = snapshot['interactive'] as List<dynamic>? ?? [];
  final entry = interactive.cast<Map<String, dynamic>>().where((e) => e['ref'] == ref).firstOrNull;
  if (entry == null) {
    return TapRefNotFound(ref);
  }

  final type = entry['type'] as String? ?? 'widget';
  final key = entry['key'] as String?;
  final text = describeEntryText(entry['text'] as String?);
  final expectText = input.expectText;
  final expectType = input.expectType;
  final textMatches = expectText == null || text == expectText || (text?.split(' · ').contains(expectText) ?? false);
  if (!textMatches || (expectType != null && type != expectType)) {
    return TapRefMismatch(ref: ref, type: type, text: text, expectedText: expectText, expectedType: expectType);
  }

  if (entry['built'] == false) {
    return TapRefOffScreen(ref: ref, type: type, text: text);
  }

  final entryX = (entry['x'] as num).toDouble();
  final entryY = (entry['y'] as num).toDouble();
  final params = <String, dynamic>{
    'isolateId': isolateId,
    'refType': type,
    if (key != null) 'refKey': key,
    'refX': entryX.toString(),
    'refY': entryY.toString(),
  };

  final result = await _tapUntilDeadline(
    params,
    tapRunner,
    timeoutSeconds: input.timeoutSeconds,
    // A covered or disabled widget is worth waiting for. One that is no longer
    // at the described position will not come back there; the agent has to
    // describe again.
    isRetryable: (error) => isRetryableGestureError(error, waitForMatch: false),
  );
  return switch (result) {
    TapSuccess(:final x, :final y) => TapSuccess(widgetType: type, x: x ?? entryX, y: y ?? entryY, text: text),
    TapRelayedError(:final message) when message.contains('No hittable element found') =>
      TapRefMoved(ref: ref, type: type, text: text),
    TapRelayedError(:final message) when message.contains('params must contain at least one of') =>
      const TapRelayedError('fdb_helper in the app is too old for @N taps. Update it to the version of fdb.'),
    _ => result,
  };
}
