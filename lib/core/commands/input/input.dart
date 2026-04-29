import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/input/input_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/input/input_models.dart';

/// Enters text into a field in the running Flutter app.
///
/// If no selector flags are provided, targets the focused field.
/// Never throws; all error conditions are represented as sealed result cases.
Future<InputResult> enterText(InputInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const InputNoFdbHelper();

    final params = <String, dynamic>{
      'isolateId': isolateId,
      'input': input.textToEnter,
    };

    final hasSelector = input.text != null || input.key != null || input.type != null;
    if (!hasSelector) {
      params['focused'] = 'true';
    }
    if (input.text != null) params['text'] = input.text;
    if (input.key != null) params['key'] = input.key;
    if (input.type != null) params['type'] = input.type;
    if (input.index != null) params['index'] = input.index.toString();

    final response = await vmServiceCall('ext.fdb.enterText', params: params);
    final result = unwrapRawExtensionResult(response);

    if (result is Map<String, dynamic>) {
      final status = result['status'] as String?;
      final error = result['error'] as String?;

      if (status == 'Success') {
        final fieldType = result['widgetType'] as String? ?? input.type ?? 'field';
        return InputSuccess(fieldType: fieldType, value: input.textToEnter);
      }

      if (error != null) return InputRelayedError(error);
    }

    return InputUnexpectedResponse(result);
  } on AppDiedException catch (e) {
    return InputAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return InputError(e.toString());
  }
}
