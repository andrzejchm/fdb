import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/longpress/longpress_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/longpress/longpress_models.dart';

/// Long-presses a widget or coordinates in the running Flutter app.
///
/// Includes a retry loop (500 ms poll until deadline) for "not found" /
/// "No hittable element" errors. Never throws; all error conditions are
/// represented as sealed result cases.
Future<LongpressResult> longpressWidget(LongpressInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const LongpressNoFdbHelper();

    final deadline = DateTime.now().add(Duration(seconds: input.timeoutSeconds));

    while (true) {
      final params = <String, dynamic>{
        'isolateId': isolateId,
        'duration': input.durationMs.toString(),
      };
      if (input.text != null) params['text'] = input.text;
      if (input.key != null) params['key'] = input.key;
      if (input.type != null) params['type'] = input.type;
      if (input.index != null) params['index'] = input.index.toString();
      if (input.x != null) params['x'] = input.x.toString();
      if (input.y != null) params['y'] = input.y.toString();

      final response = await vmServiceCall('ext.fdb.longPress', params: params);
      final result = unwrapRawExtensionResult(response);

      if (result is Map<String, dynamic>) {
        final status = result['status'] as String?;
        final error = result['error'] as String?;

        if (status == 'Success') {
          final widgetType = input.usedAt ? 'coordinates' : result['widgetType'] as String? ?? input.type ?? 'widget';
          final pressedX = result['x'] ?? input.x ?? '';
          final pressedY = result['y'] ?? input.y ?? '';
          return LongpressSuccess(widgetType: widgetType, x: pressedX, y: pressedY);
        }

        if (error != null) {
          final isRetryable = error.contains('not found') || error.contains('No hittable element');
          if (isRetryable && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            continue;
          }
          return LongpressRelayedError(error);
        }
      }

      return LongpressUnexpectedResponse(result.toString());
    }
  } on AppDiedException catch (e) {
    return LongpressAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return LongpressError(e.toString());
  }
}
