import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A widget State that receives text from the platform IME.
///
/// [client] is the State itself (EditableTextState, QuillRawEditorState, or any
/// other State implementing [TextInputClient]). [element] is the State's
/// element; its widget type is what fdb reports back to the agent.
class TextInputTarget {
  const TextInputTarget(this.element, this.client);

  final StatefulElement element;
  final TextInputClient client;

  /// Widget type of the client, e.g. `EditableText` or `QuillRawEditor`.
  String get widgetType => element.widget.runtimeType.toString();

  /// State type of the client, e.g. `QuillRawEditorState`.
  String get stateType => element.state.runtimeType.toString();

  bool get isEditableText => client is EditableTextState;
}

/// Thrown when no usable text input is found or text cannot be applied.
///
/// [message] names the widget that was inspected and why it was rejected.
class TextInputException implements Exception {
  const TextInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Finds the text input client for [start].
///
/// Search order:
/// 1. [start] itself.
/// 2. Descendants: the first [EditableTextState] wins (plain fields keep their
///    existing route); otherwise the first State implementing [TextInputClient].
/// 3. Ancestors, nearest first. This covers focus nodes and placeholder text
///    that live inside a custom editor (for example flutter_quill's
///    `QuillRawEditorState`, which implements [TextInputClient] directly and
///    never builds an [EditableText]).
///
/// Throws [TextInputException] naming [start]'s widget type when nothing is
/// found.
TextInputTarget resolveTextInputTarget(Element start) {
  final self = _asTarget(start);
  if (self != null) return self;

  TextInputTarget? firstEditable;
  TextInputTarget? firstClient;
  void visitDescendant(Element el) {
    if (firstEditable != null) return;
    final target = _asTarget(el);
    if (target != null) {
      if (target.isEditableText) {
        firstEditable = target;
        return;
      }
      firstClient ??= target;
    }
    el.visitChildren(visitDescendant);
  }

  start.visitChildren(visitDescendant);
  final fromDescendants = firstEditable ?? firstClient;
  if (fromDescendants != null) return fromDescendants;

  TextInputTarget? fromAncestors;
  start.visitAncestorElements((ancestor) {
    fromAncestors = _asTarget(ancestor);
    return fromAncestors == null;
  });
  if (fromAncestors != null) return fromAncestors!;

  throw TextInputException(
    '${start.widget.runtimeType} is not a text input: no EditableText and no '
    'State implementing TextInputClient was found on it, below it, or above it',
  );
}

TextInputTarget? _asTarget(Element element) {
  if (element is! StatefulElement) return null;
  final state = element.state;
  if (state is TextInputClient) {
    return TextInputTarget(element, state as TextInputClient);
  }
  return null;
}

/// Replaces the content of [target] with [text], the way an IME would.
///
/// The new value has a collapsed selection at the end of [text] and an empty
/// composing range. It is delivered through the client interface so the
/// widget's own controller, listeners and formatters run:
/// - [DeltaTextInputClient]: `updateEditingValueWithDeltas` with a
///   [TextEditingDeltaInsertion] (empty field) or [TextEditingDeltaReplacement].
///   If the client ignores deltas (its connection was opened without the delta
///   model), `updateEditingValue` is used as a fallback. Both are never applied
///   together, so text is not inserted twice.
/// - any other [TextInputClient]: `updateEditingValue`.
///
/// Rich-text editors such as flutter_quill keep a mandatory trailing `\n` as
/// the document terminator. For clients other than [EditableTextState], a
/// trailing `\n` in the current value is preserved so the terminator is not
/// deleted.
///
/// Works without a soft or hardware keyboard. When the client has no open
/// input connection (`currentTextEditingValue` is null) and it is also a
/// [TextSelectionDelegate], the value goes through
/// `userUpdateTextEditingValue` instead.
///
/// Returns the text the client holds afterwards (best effort).
Future<String?> enterTextInto(TextInputTarget target, String text) async {
  final client = target.client;

  if (target.isEditableText) {
    // Unchanged EditableText path.
    client.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    WidgetsBinding.instance.scheduleFrame();
    return client.currentTextEditingValue?.text;
  }

  final remote = client.currentTextEditingValue;
  final delegate = client is TextSelectionDelegate ? client as TextSelectionDelegate : null;
  final old = remote ?? delegate?.textEditingValue;
  if (old == null) {
    throw TextInputException(
      '${target.widgetType} (${target.stateType}) has no active text input '
      'connection (currentTextEditingValue is null) and is not a '
      'TextSelectionDelegate, so text cannot be applied. Tap the field to '
      'focus it, then retry',
    );
  }

  final terminator = old.text.endsWith('\n') ? '\n' : '';
  final oldContentLength = old.text.length - terminator.length;
  final newValue = TextEditingValue(
    text: '$text$terminator',
    selection: TextSelection.collapsed(offset: text.length),
    composing: TextRange.empty,
  );

  if (remote == null) {
    // No connection: go through the selection delegate (e.g. Quill's
    // textEditingValue setter → controller.replaceText).
    delegate!.userUpdateTextEditingValue(newValue, SelectionChangedCause.keyboard);
    WidgetsBinding.instance.scheduleFrame();
    return delegate.textEditingValue.text;
  }

  var applied = false;
  if (client is DeltaTextInputClient) {
    final TextEditingDelta delta = oldContentLength == 0
        ? TextEditingDeltaInsertion(
            oldText: old.text,
            textInserted: text,
            insertionOffset: 0,
            selection: newValue.selection,
            composing: TextRange.empty,
          )
        : TextEditingDeltaReplacement(
            oldText: old.text,
            replacementText: text,
            replacedRange: TextRange(start: 0, end: oldContentLength),
            selection: newValue.selection,
            composing: TextRange.empty,
          );
    client.updateEditingValueWithDeltas([delta]);
    applied = client.currentTextEditingValue?.text == newValue.text;
  }
  if (!applied) {
    client.updateEditingValue(newValue);
  }
  WidgetsBinding.instance.scheduleFrame();
  return client.currentTextEditingValue?.text ?? delegate?.textEditingValue.text;
}

/// Maps a CLI action name to a [TextInputAction].
///
/// Accepts the enum names (`send`, `done`, `newline`, `go`, `search`, `next`,
/// `previous`, `join`, `route`, `emergencyCall`, `continueAction`, `none`,
/// `unspecified`) plus the alias `continue`.
TextInputAction? parseTextInputAction(String name) {
  final normalized = name == 'continue' ? 'continueAction' : name;
  for (final action in TextInputAction.values) {
    if (action.name == normalized) return action;
  }
  return null;
}

/// Sends [action] to [target] as if the IME action key (send, done, ...) was
/// pressed. Uses `performAction` on the same client that receives text.
Future<void> performTextInputAction(
  TextInputTarget target,
  TextInputAction action,
) async {
  target.client.performAction(action);
  WidgetsBinding.instance.scheduleFrame();
}

/// Enters [text] into the text input found from [element].
///
/// Kept for callers that only need the plain "type into this subtree" path.
/// Throws [TextInputException] if no text input is found.
Future<void> enterText(Element element, String text) async {
  await enterTextInto(resolveTextInputTarget(element), text);
}
