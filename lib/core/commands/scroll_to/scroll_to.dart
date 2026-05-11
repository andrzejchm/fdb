import 'package:fdb/core/commands/scroll_to/scroll_to_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

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

    final result = await fdbScrollTo(params);

    if (result.isSuccess) {
      final x = result.x;
      final y = result.y;
      if (x == null || y == null) return const ScrollToMissingCoordinates();
      final widgetType = result.widgetType ?? input.key ?? input.text ?? input.type ?? 'widget';
      return ScrollToSuccess(widgetType: widgetType, x: x, y: y);
    }

    if (result.error != null) return ScrollToRelayedError(result.error!);

    return ScrollToUnexpectedResponse(result.unexpected);
  } on AppDiedException catch (e) {
    return ScrollToAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return ScrollToError(e.toString());
  }
}
