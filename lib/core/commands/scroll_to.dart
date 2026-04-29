import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// Input parameters for [scrollTo].
typedef ScrollToInput = ({String? text, String? key, String? type, int? index});

/// Result of a [scrollTo] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class ScrollToResult extends CommandResult {
  const ScrollToResult();
}

/// The scroll succeeded and the target widget is now visible.
class ScrollToSuccess extends ScrollToResult {
  const ScrollToSuccess({required this.widgetType, required this.x, required this.y});
  final String widgetType;
  final double x;
  final double y;
}

/// fdb_helper was not detected in the running app.
class ScrollToNoFdbHelper extends ScrollToResult {
  const ScrollToNoFdbHelper();
}

/// The VM service returned a success status but x or y was missing.
class ScrollToMissingCoordinates extends ScrollToResult {
  const ScrollToMissingCoordinates();
}

/// The VM service returned an error message.
class ScrollToRelayedError extends ScrollToResult {
  const ScrollToRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class ScrollToUnexpectedResponse extends ScrollToResult {
  const ScrollToUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class ScrollToAppDied extends ScrollToResult {
  const ScrollToAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class ScrollToError extends ScrollToResult {
  const ScrollToError(this.message);
  final String message;
}

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
        final widgetType =
            result['widgetType'] as String? ?? input.key ?? input.text ?? input.type ?? 'widget';
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
