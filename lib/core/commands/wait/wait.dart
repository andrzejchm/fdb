import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/wait/wait_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/wait/wait_models.dart';

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
