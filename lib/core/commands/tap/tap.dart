import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:fdb/core/vm_service.dart';

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

    final response = await vmServiceCall('ext.fdb.tap', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final widgetType = input.usedAt
            ? 'coordinates'
            : result['widgetType'] as String? ?? input.type ?? 'widget';
        final tappedX = result['x'] ?? input.x ?? '';
        final tappedY = result['y'] ?? input.y ?? '';
        final warning = result['warning'] as String?;
        return TapSuccess(widgetType: widgetType, x: tappedX, y: tappedY, warning: warning);
      }

      if (error != null) {
        final isRetryable =
            error.contains('not found') || error.contains('No hittable element');
        if (isRetryable && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return TapRelayedError(error);
      }
    }

    return TapUnexpectedResponse(result.toString());
  }
}

Future<TapResult> _tapByRef(String isolateId, int ref, int timeoutSeconds) async {
  final describeResponse = await vmServiceCall(
    'ext.fdb.describe',
    params: {'isolateId': isolateId},
  );
  final describeResult = unwrapRawExtensionResult(describeResponse);

  if (describeResult is! Map<String, dynamic>) {
    return const TapUnexpectedDescribeResponse();
  }

  final describeError = describeResult['error'] as String?;
  if (describeError != null) {
    return TapRelayedDescribeError(describeError);
  }

  final interactive = describeResult['interactive'] as List<dynamic>? ?? [];
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

  final tapResponse = await vmServiceCall('ext.fdb.tap', params: tapParams);
  final tapResult = unwrapRawExtensionResult(tapResponse);

  if (tapResult is Map<String, dynamic>) {
    final status = tapResult['status'] as String?;
    final tapError = tapResult['error'] as String?;

    if (status == 'Success') {
      final type = element['type'] as String? ?? 'widget';
      return TapSuccess(widgetType: type, x: cx, y: cy);
    }

    if (tapError != null) {
      return TapRelayedError(tapError);
    }
  }

  return TapUnexpectedResponse(tapResult.toString());
}
