import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../gesture_dispatcher.dart';
import '../element_tree_finder.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleTap(
  String method,
  Map<String, String> params,
) async {
  try {
    final rawDuration = params['duration'];
    final durationMs = rawDuration != null ? int.tryParse(rawDuration) : null;
    if (rawDuration != null && durationMs == null) {
      return errorResponse('Invalid duration value: $rawDuration');
    }
    final holdDuration = durationMs != null
        ? Duration(milliseconds: durationMs)
        : const Duration(milliseconds: 10);

    final matcher = WidgetMatcher.fromParams(params);

    if (matcher is CoordinatesMatcher) {
      await dispatchTap(matcher.offset, holdDuration: holdDuration);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'status': 'Success', 'x': matcher.x, 'y': matcher.y}),
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

    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      return errorResponse('Element has no RenderBox');
    }

    final center = renderObject.size.center(Offset.zero);
    final globalCenter = renderObject.localToGlobal(center);
    await dispatchTap(globalCenter, holdDuration: holdDuration);

    final widgetType = element.widget.runtimeType.toString();
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'widgetType': widgetType,
        'x': globalCenter.dx,
        'y': globalCenter.dy,
      }),
    );
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('Tap failed: $e');
  }
}
