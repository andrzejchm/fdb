import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [enterText].
typedef InputInput = ({
  String? text,
  String? key,
  String? type,
  int? index,
  // Text to enter (replaces the field content). Null when only [action] is sent.
  String? textToEnter,
  // IME action to send after the text: send, done, newline, go, search, next, ...
  String? action,
});

/// Result of an [enterText] invocation.
sealed class InputResult extends CommandResult {
  const InputResult();
}

/// Text was entered and/or an IME action was sent.
///
/// [fieldType] is the widget type string. [value] is the entered text (null
/// when only an action was sent). [action] is the IME action performed, if any.
/// [clientType] is the State that received the input (e.g. EditableTextState,
/// QuillRawEditorState).
class InputSuccess extends InputResult {
  const InputSuccess({required this.fieldType, required this.value, this.action, this.clientType});
  final String fieldType;
  final String? value;
  final String? action;
  final String? clientType;
}

/// fdb_helper was not detected in the running app.
class InputNoFdbHelper extends InputResult {
  const InputNoFdbHelper();
}

/// The VM service returned an error message.
class InputRelayedError extends InputResult {
  const InputRelayedError(this.message);
  final String message;
}

/// The VM service returned an unexpected response shape.
class InputUnexpectedResponse extends InputResult {
  const InputUnexpectedResponse(this.raw);
  final Object? raw;
}

/// The app process died while fdb was communicating with it.
class InputAppDied extends InputResult {
  const InputAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class InputError extends InputResult {
  const InputError(this.message);
  final String message;
}
