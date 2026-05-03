import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:fdb/controller/controller_client.dart';

export 'package:fdb/core/commands/tap/tap_models.dart';

/// Taps a widget or coordinates in the running Flutter app.
///
/// Handles selector-based taps, coordinate taps, and @N describe-ref taps.
/// The retry loop (500ms poll until deadline) runs inside this function.
/// Never throws; all error conditions are represented as sealed result cases.
Future<TapResult> tapWidget(TapInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const TapNoFdbHelper();

    if (input.describeRef != null) {
      return _tapByRef(isolateId, input.describeRef!, input.timeoutSeconds);
    }

    return _tapWithParams(isolateId, input);
  } on AppDiedException catch (e) {
    return TapAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return TapError(e.toString());
  }
}

Future<TapResult> _tapWithParams(String isolateId, TapInput input) async {
  final deadline = DateTime.now().add(Duration(seconds: input.timeoutSeconds));

  while (true) {
    final params = <String, dynamic>{'isolateId': isolateId};
    if (input.text != null) params['text'] = input.text;
    if (input.key != null) params['key'] = input.key;
    if (input.type != null) params['type'] = input.type;
    if (input.index != null) params['index'] = input.index.toString();
    if (input.x != null) params['x'] = input.x.toString();
    if (input.y != null) params['y'] = input.y.toString();

    final result = await fdbTap(params);

    if (result.isSuccess) {
      final widgetType = input.usedAt ? 'coordinates' : result.widgetType ?? input.type ?? 'widget';
      final tappedX = result.x ?? input.x ?? '';
      final tappedY = result.y ?? input.y ?? '';
      return TapSuccess(
        widgetType: widgetType,
        x: tappedX,
        y: tappedY,
        warning: result.warning,
      );
    }

    final error = result.error;
    if (error != null) {
      final isRetryable = error.contains('not found') || error.contains('No hittable element');
      if (isRetryable && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      return TapRelayedError(error);
    }

    return TapUnexpectedResponse(result.unexpected.toString());
  }
}

Future<TapResult> _tapByRef(String isolateId, int ref, int timeoutSeconds) async {
  final describeResult = await fdbDescribe(isolateId);

  final snapshot = describeResult.snapshot;
  if (snapshot == null) {
    return const TapUnexpectedDescribeResponse();
  }

  if (describeResult.error != null) {
    return TapRelayedDescribeError(describeResult.error!);
  }

  final interactive = snapshot['interactive'] as List<dynamic>? ?? [];
  final matches = interactive.cast<Map<String, dynamic>>().where((e) => e['ref'] == ref);

  if (matches.isEmpty) {
    return TapRefNotFound(ref);
  }

  final element = matches.first;
  final cx = (element['x'] as num).toDouble();
  final cy = (element['y'] as num).toDouble();

  final tapParams = <String, dynamic>{
    'isolateId': isolateId,
    'x': cx.toString(),
    'y': cy.toString(),
  };

  final tapResult = await fdbTap(tapParams);

  if (tapResult.isSuccess) {
    final type = element['type'] as String? ?? 'widget';
    return TapSuccess(widgetType: type, x: cx, y: cy);
  }

  if (tapResult.error != null) {
    return TapRelayedError(tapResult.error!);
  }

  return TapUnexpectedResponse(tapResult.unexpected.toString());
}
