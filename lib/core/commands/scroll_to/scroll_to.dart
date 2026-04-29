import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/scroll_to/scroll_to_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/scroll_to/scroll_to_models.dart';

/// Scrolls the nearest Scrollable until the target widget becomes visible.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<ScrollToResult> scrollTo(ScrollToInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const ScrollToNoFdbHelper();

    final params = <String, String>{'isolateId': isolateId};
    if (input.text != null) params['text'] = input.text!;
    if (input.key != null) params['key'] = input.key!;
    if (input.type != null) params['type'] = input.type!;
    if (input.index != null) params['index'] = input.index.toString();

    final response = await vmServiceCall('ext.fdb.scrollTo', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final x = result['x'] as double?;
        final y = result['y'] as double?;
        if (x == null || y == null) return const ScrollToMissingCoordinates();
        final widgetType = result['widgetType'] as String? ?? input.key ?? input.text ?? input.type ?? 'widget';
        return ScrollToSuccess(widgetType: widgetType, x: x, y: y);
      }

      if (error != null) return ScrollToRelayedError(error);
    }

    return ScrollToUnexpectedResponse(result);
  } on AppDiedException catch (e) {
    return ScrollToAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return ScrollToError(e.toString());
  }
}
