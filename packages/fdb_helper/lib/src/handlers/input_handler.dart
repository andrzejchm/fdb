import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../element_tree_finder.dart';
import '../text_input_simulator.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

/// `ext.fdb.enterText` — types into a text input and/or sends an IME action.
///
/// Params:
/// - `input`: text to put in the field (replaces current content). Optional
///   when `action` is given.
/// - `action`: optional IME action (`send`, `done`, `newline`, `go`, `search`,
///   `next`, ...) delivered via `TextInputClient.performAction` after the text.
/// - selector params (`focused`, `text`, `key`, `type`, `index`).
///
/// Works for any State implementing `TextInputClient` (EditableText,
/// flutter_quill's QuillRawEditorState, custom editors). No keyboard needed.
Future<developer.ServiceExtensionResponse> handleEnterText(
  String method,
  Map<String, String> params,
) async {
  try {
    final input = params['input'];
    final actionName = params['action'];
    if (input == null && actionName == null) {
      return errorResponse('Missing required param: input (or action)');
    }

    TextInputAction? action;
    if (actionName != null) {
      action = parseTextInputAction(actionName);
      if (action == null) {
        return errorResponse(
          'Unknown text input action "$actionName". Valid: '
          '${TextInputAction.values.map((a) => a.name).join(', ')}',
        );
      }
    }

    final matcher = WidgetMatcher.fromParams(params);

    final TextInputTarget target;
    final String reportedType;
    if (matcher is FocusedMatcher) {
      final focusNode = FocusManager.instance.primaryFocus;
      final focusContext = focusNode?.context;
      if (focusContext == null || focusContext is! Element) {
        return errorResponse('No focused element found');
      }
      // With no field focused, primary focus sits on a route/app FocusScopeNode.
      // Searching below it would pick an arbitrary field, so refuse.
      if (focusNode is FocusScopeNode) {
        return errorResponse(
          'No focused element found: focus is on a focus scope '
          '(${focusContext.widget.runtimeType}), not on a text field. '
          'Tap the field first, or pass --key, --text or --type',
        );
      }
      try {
        target = resolveTextInputTarget(focusContext);
      } on TextInputException catch (e) {
        return errorResponse('Focused element is not an editable text field: ${e.message}');
      }
      reportedType = target.widgetType;
    } else {
      final (:element, :matchCount) = findHittableElement(matcher);
      if (element == null) {
        if (matchCount > 1) {
          return errorResponse(
            'Found $matchCount elements matching the selector. '
            'Use --index to specify which one (0-based).',
          );
        }
        return errorResponse('No hittable element found for matcher');
      }
      try {
        target = resolveTextInputTarget(element);
      } on TextInputException catch (e) {
        return errorResponse('enterText failed: ${e.message}');
      }
      reportedType = element.widget.runtimeType.toString();
    }

    String? resultingText;
    if (input != null) {
      resultingText = await enterTextInto(target, input);
    }
    if (action != null) {
      await performTextInputAction(target, action);
    }

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        if (input != null) 'input': input,
        'widgetType': reportedType,
        'clientType': target.stateType,
        'clientKind': _clientKind(target),
        if (action != null) 'action': actionName,
        if (resultingText != null) 'resultingText': resultingText,
      }),
    );
  } on TextInputException catch (e) {
    return errorResponse('enterText failed: ${e.message}');
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('enterText failed: $e');
  }
}

String _clientKind(TextInputTarget target) {
  if (target.isEditableText) return 'EditableText';
  if (target.client is DeltaTextInputClient) return 'DeltaTextInputClient';
  return 'TextInputClient';
}
