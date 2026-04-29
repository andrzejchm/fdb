import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [doubleTap].
typedef DoubleTapInput = ({
  String? text,
  String? key,
  String? type,
  int? index,
  double? x,
  double? y,
  int timeoutSeconds,
});

/// Result of a [doubleTap] invocation.
sealed class DoubleTapResult extends CommandResult {
  const DoubleTapResult();
}

/// The double-tap succeeded.
class DoubleTapSuccess extends DoubleTapResult {
  const DoubleTapSuccess({
    required this.widgetType,
    required this.x,
    required this.y,
  });
  final String widgetType;
  final dynamic x;
  final dynamic y;
}

/// fdb_helper was not detected in the running app.
class DoubleTapNoFdbHelper extends DoubleTapResult {
  const DoubleTapNoFdbHelper();
}

/// The VM service returned an error message (after retries).
class DoubleTapRelayedError extends DoubleTapResult {
  const DoubleTapRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class DoubleTapUnexpectedResponse extends DoubleTapResult {
  const DoubleTapUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class DoubleTapAppDied extends DoubleTapResult {
  const DoubleTapAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class DoubleTapError extends DoubleTapResult {
  const DoubleTapError(this.message);
  final String message;
}

/// Double-taps a widget identified by selector or absolute coordinates.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<DoubleTapResult> doubleTap(DoubleTapInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const DoubleTapNoFdbHelper();

    final params = <String, dynamic>{'isolateId': isolateId};
    if (input.text != null) params['text'] = input.text;
    if (input.key != null) params['key'] = input.key;
    if (input.type != null) params['type'] = input.type;
    if (input.index != null) params['index'] = input.index.toString();
    if (input.x != null) params['x'] = input.x.toString();
    if (input.y != null) params['y'] = input.y.toString();

    final deadline = DateTime.now().add(Duration(seconds: input.timeoutSeconds));

    while (true) {
      final response = await vmServiceCall('ext.fdb.doubleTap', params: params);
      final result = unwrapRawExtensionResult(response);

      if (result is Map<String, dynamic>) {
        final status = result['status'] as String?;
        final error = result['error'] as String?;

        if (status == 'Success') {
          final tappedType = result['widgetType'] as String? ?? input.type ?? 'widget';
          final tappedX = result['x'] ?? input.x ?? '';
          final tappedY = result['y'] ?? input.y ?? '';
          return DoubleTapSuccess(widgetType: tappedType, x: tappedX, y: tappedY);
        }

        if (error != null) {
          final isRetryable =
              error.contains('not found') || error.contains('No hittable element');
          if (isRetryable && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            continue;
          }
          return DoubleTapRelayedError(error);
        }
      }

      return DoubleTapUnexpectedResponse(result);
    }
  } on AppDiedException catch (e) {
    return DoubleTapAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return DoubleTapError(e.toString());
  }
}
