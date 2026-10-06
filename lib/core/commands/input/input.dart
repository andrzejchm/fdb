import 'package:fdb/core/commands/input/input_models.dart';
import 'package:fdb/core/describe_ref.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/input/input_models.dart';

/// Enters text into a field in the running Flutter app and/or sends an IME
/// action (send, done, newline, ...) to it.
///
/// Works for any widget whose State implements `TextInputClient` (EditableText,
/// flutter_quill editors, custom editors); no keyboard is required.
/// If no selector flags are provided, targets the focused field.
/// Never throws; all error conditions are represented as sealed result cases.
Future<InputResult> enterText(InputInput input) async {
  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) return const InputNoFdbHelper();

    final params = <String, dynamic>{
      'isolateId': isolateId,
      if (input.textToEnter != null) 'input': input.textToEnter,
      if (input.action != null) 'action': input.action,
    };

    final hasSelector = input.text != null || input.key != null || input.type != null || input.ref != null;
    if (!hasSelector) {
      params['focused'] = 'true';
    }
    if (input.text != null) params['text'] = input.text;
    if (input.key != null) params['key'] = input.key;
    if (input.type != null) params['type'] = input.type;
    if (input.index != null) params['index'] = input.index.toString();
    if (input.ref != null) params['ref'] = input.ref.toString();

    final result = await fdbEnterText(params);

    if (result.isSuccess && input.action != null && result.action == null) {
      // Older fdb_helper ignores the `action` param.
      return InputRelayedError(
        '${input.textToEnter != null ? 'Text was entered, but the ' : 'The '}'
        '--action was not performed: the fdb_helper in the app does not support it. '
        'Update fdb_helper and rebuild the app.',
      );
    }

    if (result.isSuccess) {
      final fieldType = result.widgetType ?? input.type ?? 'field';
      return InputSuccess(
        fieldType: fieldType,
        value: input.textToEnter,
        action: result.action,
        clientType: result.clientType,
      );
    }

    if (result.error != null) return InputRelayedError(refAwareError(result.error!, input.ref));

    return InputUnexpectedResponse(result.unexpected);
  } on AppDiedException catch (e) {
    return InputAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return InputError(e.toString());
  }
}
