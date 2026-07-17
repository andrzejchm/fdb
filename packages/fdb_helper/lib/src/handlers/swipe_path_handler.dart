import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../gesture_dispatcher.dart';
import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleSwipePath(
  String method,
  Map<String, String> params,
) async {
  try {
    final raw = params['points'];
    if (raw == null) {
      return errorResponse('Missing required param: points');
    }

    final points = <Offset>[];
    for (final segment in raw.split(';')) {
      final parts = segment.split(',');
      final x = parts.length == 2 ? double.tryParse(parts[0]) : null;
      final y = parts.length == 2 ? double.tryParse(parts[1]) : null;
      if (x == null || y == null) {
        return errorResponse(
          'Invalid --points value: "$raw". Expected format: '
          'x1,y1;x2,y2;... (at least 2 points).',
        );
      }
      points.add(Offset(x, y));
    }

    if (points.length < 2) {
      return errorResponse(
        'Invalid --points value: "$raw". Expected format: '
        'x1,y1;x2,y2;... (at least 2 points).',
      );
    }

    final maxStepSize = double.tryParse(params['precision'] ?? '') ?? 8.0;

    await dispatchPath(points: points, maxStepSize: maxStepSize);

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'pointCount': points.length,
      }),
    );
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('Swipe path failed: $e');
  }
}
