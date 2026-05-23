import 'package:fdb/core/commands/swipe/swipe_models.dart';
import 'package:fdb/src/controller/commands/fdb_swipe.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/swipe/swipe_models.dart';

typedef FdbHelperChecker = Future<String?> Function();
typedef FdbSwipeRunner = Future<FdbSwipeCommandResponse> Function(Map<String, dynamic> params);

/// Sends a swipe gesture to the running Flutter app via the VM service.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SwipeResult> runSwipe(
  SwipeInput input, {
  FdbHelperChecker? checkFdbHelperFn,
  FdbSwipeRunner? fdbSwipeFn,
}) async {
  try {
    final helperChecker = checkFdbHelperFn ?? checkFdbHelper;
    final swipeRunner = fdbSwipeFn ?? fdbSwipe;
    final isolateId = await helperChecker();
    if (isolateId == null) return const SwipeNoFdbHelper();

    final params = <String, dynamic>{
      'isolateId': isolateId,
      'direction': input.direction,
    };
    if (input.key != null) params['key'] = input.key;
    if (input.text != null) params['text'] = input.text;
    if (input.type != null) params['type'] = input.type;
    if (input.at != null) params['at'] = input.at;
    if (input.distance != null) params['distance'] = input.distance.toString();

    final result = await swipeRunner(params);

    if (result.isSuccess) {
      final actualDistance = result.distance ?? input.distance ?? '';
      return SwipeSuccess(
        direction: input.direction,
        actualDistance: actualDistance,
      );
    }

    if (result.error != null) return SwipeRelayedError(result.error!);

    return SwipeUnexpectedResponse(result.unexpected);
  } on AppDiedException catch (e) {
    return SwipeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return SwipeError(e.toString());
  }
}
