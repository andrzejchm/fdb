import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/models/command_result.dart';
import 'package:fdb/core/vm_service.dart';

/// The condition to wait for.
enum WaitCondition { present, absent }

/// Input parameters for [waitForWidget].
typedef WaitInput = ({
  String? text,
  String? key,
  String? type,
  String? route,
  WaitCondition condition,
  int timeoutMs,
});

/// Result of a [waitForWidget] invocation.
sealed class WaitResult extends CommandResult {
  const WaitResult();
}

/// The condition was met successfully.
class WaitConditionMet extends WaitResult {
  const WaitConditionMet({
    required this.condition,
    required this.selectorToken,
  });

  final WaitCondition condition;

  /// e.g. "KEY=foo" or "TEXT=bar"
  final String selectorToken;
}

/// fdb_helper was not detected in the running app.
class WaitNoFdbHelper extends WaitResult {
  const WaitNoFdbHelper();
}

/// The VM service returned an error message (e.g. timeout).
class WaitRelayedError extends WaitResult {
  const WaitRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class WaitUnexpectedResponse extends WaitResult {
  const WaitUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class WaitAppDied extends WaitResult {
  const WaitAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class WaitError extends WaitResult {
  const WaitError(this.message);
  final String message;
}

/// Waits until a widget or route is present or absent in the running Flutter app.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<WaitResult> waitForWidget(WaitInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const WaitNoFdbHelper();

    final params = <String, String>{
      'isolateId': isolateId,
      'condition': input.condition.name,
      'timeout': input.timeoutMs.toString(),
    };
    if (input.text != null) params['text'] = input.text!;
    if (input.key != null) params['key'] = input.key!;
    if (input.type != null) params['type'] = input.type!;
    if (input.route != null) params['route'] = input.route!;

    final response = await vmServiceCall(
      'ext.fdb.waitFor',
      params: params,
      timeout: Duration(milliseconds: input.timeoutMs + 5000),
    );
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final token = _selectorToken(input.key, input.text, input.type, input.route);
        return WaitConditionMet(condition: input.condition, selectorToken: token);
      }

      if (error != null) return WaitRelayedError(error);
    }

    return WaitUnexpectedResponse(result);
  } on AppDiedException catch (e) {
    return WaitAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return WaitError(e.toString());
  }
}

String _selectorToken(String? key, String? text, String? type, String? route) {
  if (key != null) return 'KEY=$key';
  if (text != null) return 'TEXT=$text';
  if (type != null) return 'TYPE=$type';
  return 'ROUTE=$route';
}
