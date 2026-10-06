import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'element_tree_finder.dart';

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
  final found = _asTarget(start) ?? _descendantTargets(start).firstOrNull ?? _ancestorTarget(start);
  if (found != null) return found;
  throw TextInputException(_notATextInput(start));
}

/// Finds the text input a selector match refers to.
///
/// Searches [matched] itself, then its descendants, then its ancestors (a
/// placeholder inside a custom editor). The descendants of an ancestor are
/// never searched, so a label next to a field inside a screen-level
/// `GestureDetector` does not resolve to whichever field comes first. Only
/// when that finds nothing is [gestureTarget] (the nearest interactive
/// ancestor of a non-interactive match, e.g. the `TextField` around a hint)
/// used, and only if it is a text input itself or holds exactly one with no
/// other interactive widget in between.
///
/// Throws [TextInputException] when [matched] holds several text inputs or
/// none belongs to it.
TextInputTarget resolveSelectorTextInput(Element matched, Element gestureTarget) {
  final self = _asTarget(matched);
  if (self != null) return self;

  final type = matched.widget.runtimeType;
  final below = _descendantTargets(matched);
  if (below.length > 1) {
    throw TextInputException(
      '$type contains ${below.length} text inputs. Target one field with --key, or with --type and --index',
    );
  }
  final found = below.firstOrNull ?? _ancestorTarget(matched) ?? _ownedTarget(gestureTarget, matched);
  if (found != null) return found;

  if (gestureTarget == matched) throw TextInputException(_notATextInput(matched));
  throw TextInputException(
    '${_notATextInput(matched)}, and its nearest interactive ancestor ${gestureTarget.widget.runtimeType} '
    'is not a single text field. Target the field with --key, or with --type and --index',
  );
}

String _notATextInput(Element element) => '${element.widget.runtimeType} is not a text input: no EditableText and no '
    'State implementing TextInputClient was found on it, below it, or above it';

/// Text inputs below [element] in tree order: its [EditableTextState]s, or
/// when there are none the States implementing [TextInputClient].
List<TextInputTarget> _descendantTargets(Element element) {
  final editables = <TextInputTarget>[];
  final clients = <TextInputTarget>[];
  void visit(Element child) {
    final target = _asTarget(child);
    if (target != null) (target.isEditableText ? editables : clients).add(target);
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return editables.isNotEmpty ? editables : clients;
}

/// The nearest ancestor of [element] that is a text input client.
TextInputTarget? _ancestorTarget(Element element) {
  TextInputTarget? found;
  element.visitAncestorElements((ancestor) {
    found = _asTarget(ancestor);
    return found == null;
  });
  return found;
}

/// The text input [owner] is or directly owns: the only one below it, with no
/// other interactive widget in between. Null for [matched] itself (already
/// searched) and for containers such as a screen-level `GestureDetector`.
TextInputTarget? _ownedTarget(Element owner, Element matched) {
  if (owner == matched) return null;
  final self = _asTarget(owner);
  if (self != null) return self;
  final below = _descendantTargets(owner);
  if (below.length != 1) return null;
  var direct = true;
  below.single.element.visitAncestorElements((ancestor) {
    if (ancestor == owner) return false;
    direct = !isInteractiveElement(ancestor);
    return direct;
  });
  return direct ? below.single : null;
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
