import 'package:fdb/core/commands/scroll/scroll_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/scroll/scroll_models.dart';

// ── Core function ─────────────────────────────────────────────────────────────

/// Performs a scroll or drag gesture in the running Flutter app.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<ScrollResult> runScroll(ScrollInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const ScrollNoFdbHelper();

    final Map<String, dynamic> params;
    switch (input) {
      case ScrollDirectionMode(:final direction, :final at, :final distance):
        params = {
          'isolateId': isolateId,
          'direction': direction,
          'distance': distance.toString(),
        };
        if (at != null) params['at'] = at;
      case ScrollRawMode(:final fromX, :final fromY, :final toX, :final toY):
        params = {
          'isolateId': isolateId,
          'startX': fromX.toString(),
          'startY': fromY.toString(),
          'endX': toX.toString(),
          'endY': toY.toString(),
        };
    }

    final result = await fdbScroll(params);

    if (result.isSuccess) {
      switch (input) {
        case ScrollDirectionMode(:final direction, :final distance):
          return ScrollDirectionSuccess(
            direction: direction.toUpperCase(),
            distance: distance,
          );
        case ScrollRawMode(:final fromX, :final fromY, :final toX, :final toY):
          return ScrollRawSuccess(
            fromX: fromX.toInt(),
            fromY: fromY.toInt(),
            toX: toX.toInt(),
            toY: toY.toInt(),
          );
      }
    }

    if (result.error != null) return ScrollRelayedError(result.error!);

    return ScrollUnexpectedResponse(result.unexpected.toString());
  } on AppDiedException catch (e) {
    return ScrollAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return ScrollError(e.toString());
  }
}
