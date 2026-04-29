import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/scroll/scroll_models.dart';
import 'package:fdb/core/vm_service.dart';

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

    final response = await vmServiceCall('ext.fdb.scroll', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
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

      if (error != null) return ScrollRelayedError(error);
    }

    return ScrollUnexpectedResponse(result.toString());
  } on AppDiedException catch (e) {
    return ScrollAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return ScrollError(e.toString());
  }
}
