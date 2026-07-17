import 'package:fdb/core/commands/swipe_path/swipe_path_models.dart';
import 'package:fdb/src/controller/commands/fdb_swipe_path.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/swipe_path/swipe_path_models.dart';

typedef FdbHelperChecker = Future<String?> Function();
typedef FdbSwipePathRunner = Future<FdbSwipePathCommandResponse> Function(Map<String, dynamic> params);

/// Sends a multi-point swipe path gesture to the running Flutter app via the
/// VM service.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SwipePathResult> runSwipePath(
  SwipePathInput input, {
  FdbHelperChecker? checkFdbHelperFn,
  FdbSwipePathRunner? fdbSwipePathFn,
}) async {
  try {
    final helperChecker = checkFdbHelperFn ?? checkFdbHelper;
    final swipePathRunner = fdbSwipePathFn ?? fdbSwipePath;
    final isolateId = await helperChecker();
    if (isolateId == null) return const SwipePathNoFdbHelper();

    final params = <String, dynamic>{
      'isolateId': isolateId,
      'points': input.points,
    };
    if (input.precision != null) params['precision'] = '${input.precision}';

    final result = await swipePathRunner(params);

    if (result.isSuccess) {
      final pointCount = result.pointCount ?? input.points.split(';').length;
      return SwipePathSuccess(pointCount: pointCount);
    }

    if (result.error != null) return SwipePathRelayedError(result.error!);

    return SwipePathUnexpectedResponse(result.unexpected);
  } on AppDiedException catch (e) {
    return SwipePathAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return SwipePathError(e.toString());
  }
}
