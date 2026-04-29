import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/swipe/swipe_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/swipe/swipe_models.dart';

/// Sends a swipe gesture to the running Flutter app via the VM service.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SwipeResult> runSwipe(SwipeInput input) async {
  try {
    final isolateId = await checkFdbHelper();
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

    final response = await vmServiceCall('ext.fdb.swipe', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final actualDistance = result['distance'] ?? input.distance ?? '';
        return SwipeSuccess(
          direction: input.direction.toUpperCase(),
          actualDistance: actualDistance,
        );
      }

      if (error != null) return SwipeRelayedError(error);
    }

    return SwipeUnexpectedResponse(result);
  } on AppDiedException catch (e) {
    return SwipeAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return SwipeError(e.toString());
  }
}
