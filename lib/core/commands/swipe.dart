import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [runSwipe].
typedef SwipeInput = ({
  String direction, // already lowercased + validated
  String? key,
  String? text,
  String? type,
  String? at,
  int? distance,
});

/// Result of a [runSwipe] invocation.
sealed class SwipeResult extends CommandResult {
  const SwipeResult();
}

/// Swipe succeeded.
class SwipeSuccess extends SwipeResult {
  const SwipeSuccess({required this.direction, required this.actualDistance});

  /// Direction in uppercase (e.g. "LEFT").
  final String direction;

  /// The distance returned by the VM extension, or the requested distance, or
  /// an empty string when neither is available.
  final dynamic actualDistance;
}

/// fdb_helper was not detected in the running app.
class SwipeNoFdbHelper extends SwipeResult {
  const SwipeNoFdbHelper();
}

/// The VM extension returned a relayed error message.
class SwipeRelayedError extends SwipeResult {
  const SwipeRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class SwipeUnexpectedResponse extends SwipeResult {
  const SwipeUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class SwipeAppDied extends SwipeResult {
  const SwipeAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class SwipeError extends SwipeResult {
  const SwipeError(this.message);
  final String message;
}

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
