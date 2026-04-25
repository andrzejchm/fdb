import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../gesture_dispatcher.dart';
import '../element_tree_finder.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleSwipe(
  String method,
  Map<String, String> params,
) async {
  try {
    final direction = params['direction'];
    if (direction == null) {
      return errorResponse('Missing required param: direction');
    }

    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;

    double startX;
    double startY;
    double swipeDistance;

    // Check if a widget selector was provided.
    final hasSelector = params.containsKey('key') || params.containsKey('text') || params.containsKey('type');

    if (hasSelector) {
      // Widget-targeted swipe: find the widget's bounds and compute
      // start = widget center, distance = 60% of widget dimension.
      final matcher = WidgetMatcher.fromParams(params);
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
      startX = globalCenter.dx;
      startY = globalCenter.dy;

      // Smart default: 60% of widget width for left/right, height for up/down.
      final rawDistance = params['distance'];
      if (rawDistance != null) {
        swipeDistance = double.tryParse(rawDistance) ?? 200.0;
      } else {
        swipeDistance = switch (direction) {
          'left' || 'right' => renderObject.size.width * 0.6,
          'up' || 'down' => renderObject.size.height * 0.6,
          _ => 200.0,
        };
      }
    } else {
      // Fallback: screen center (or --at override) + fixed distance.
      var centerX = screenSize.width / 2;
      var centerY = screenSize.height / 2;

      final at = params['at'];
      if (at != null) {
        final parts = at.split(',');
        final atX = parts.length == 2 ? double.tryParse(parts[0]) : null;
        final atY = parts.length == 2 ? double.tryParse(parts[1]) : null;
        if (atX == null || atY == null) {
          return errorResponse(
            'Invalid --at value: "$at". Expected format: x,y (e.g. 200,400).',
          );
        }
        centerX = atX;
        centerY = atY;
      }

      startX = centerX;
      startY = centerY;
      swipeDistance = double.tryParse(params['distance'] ?? '') ?? 200.0;
    }

    double endX;
    double endY;

    switch (direction) {
      case 'left':
        endX = startX - swipeDistance;
        endY = startY;
      case 'right':
        endX = startX + swipeDistance;
        endY = startY;
      case 'up':
        endX = startX;
        endY = startY - swipeDistance;
      case 'down':
        endX = startX;
        endY = startY + swipeDistance;
      default:
        return errorResponse(
          'Invalid direction: $direction. Use up, down, left, or right.',
        );
    }

    await dispatchScroll(
      start: Offset(startX, startY),
      end: Offset(endX, endY),
    );

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'direction': direction,
        'distance': swipeDistance,
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
      }),
    );
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('Swipe failed: $e');
  }
}
