import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../gesture_dispatcher.dart';
import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleScroll(
  String method,
  Map<String, String> params,
) async {
  try {
    // Support two modes:
    // 1. direction + distance (+ optional at=x,y)
    // 2. raw startX/startY/endX/endY

    final direction = params['direction'];

    double startX;
    double startY;
    double endX;
    double endY;

    if (direction != null) {
      final distance = double.tryParse(params['distance'] ?? '') ?? 200.0;

      // Default start: center of screen.
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final screenSize = view.physicalSize / view.devicePixelRatio;
      var centerX = screenSize.width / 2;
      var centerY = screenSize.height / 2;

      // Override with --at x,y.
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

      switch (direction) {
        case 'up':
          // Finger moves down → content scrolls up (reveals content above).
          endX = startX;
          endY = startY + distance;
        case 'down':
          // Finger moves up → content scrolls down (reveals content below).
          endX = startX;
          endY = startY - distance;
        case 'left':
          // Finger moves right → content scrolls left.
          endX = startX + distance;
          endY = startY;
        case 'right':
          // Finger moves left → content scrolls right.
          endX = startX - distance;
          endY = startY;
        default:
          return errorResponse(
            'Invalid direction: $direction. Use up, down, left, or right.',
          );
      }
    } else {
      // Raw coordinates mode.
      final sx = double.tryParse(params['startX'] ?? '');
      final sy = double.tryParse(params['startY'] ?? '');
      final ex = double.tryParse(params['endX'] ?? '');
      final ey = double.tryParse(params['endY'] ?? '');

      if (sx == null || sy == null || ex == null || ey == null) {
        return errorResponse(
          'Provide direction (up/down/left/right) or '
          'startX, startY, endX, endY',
        );
      }

      startX = sx;
      startY = sy;
      endX = ex;
      endY = ey;
    }

    await dispatchScroll(
      start: Offset(startX, startY),
      end: Offset(endX, endY),
    );

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
      }),
    );
  } catch (e) {
    return errorResponse('Scroll failed: $e');
  }
}
