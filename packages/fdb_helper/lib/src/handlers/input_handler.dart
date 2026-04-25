import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../element_tree_finder.dart';
import '../text_input_simulator.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleEnterText(
  String method,
  Map<String, String> params,
) async {
  try {
    final input = params['input'];
    if (input == null) {
      return errorResponse('Missing required param: input');
    }

    final matcher = WidgetMatcher.fromParams(params);

    if (matcher is FocusedMatcher) {
      // Type into the currently focused element.
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null) {
        return errorResponse('No focused element found');
      }

      // Walk descendants to find the nearest EditableText element.
      Element? editableElement;

      void findEditableText(Element el) {
        if (editableElement != null) return;
        if (el.widget is EditableText) {
          editableElement = el;
          return;
        }
        el.visitChildElements(findEditableText);
      }

      if (focusContext is Element) {
        findEditableText(focusContext);
      }

      if (editableElement == null) {
        return errorResponse('Focused element is not an editable text field');
      }

      await enterText(editableElement!, input);

      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'input': input,
          'widgetType': editableElement!.widget.runtimeType.toString(),
        }),
      );
    }

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

    await enterText(element, input);

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'input': input,
        'widgetType': element.widget.runtimeType.toString(),
      }),
    );
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('enterText failed: $e');
  }
}
