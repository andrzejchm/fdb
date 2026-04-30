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
    final holdDuration = durationMs != null ? Duration(milliseconds: durationMs) : const Duration(milliseconds: 10);

    final matcher = WidgetMatcher.fromParams(params);

    if (matcher is CoordinatesMatcher) {
      // For quick taps, use native in-process injection so that native
      // overlays (UIAlertController, WKWebView, platform views, AlertDialog)
      // are reachable — not just Flutter widgets.
      //
      // For long-press by coordinate (rawDuration != null, typically 500ms+),
      // fall back to Flutter's GestureBinding because native_tap.g.dart's
      // Pigeon API only supports a quick tap. Long-press by coordinate on
      // native overlays is not currently supported — see beads ticket for
      // adding a holdDuration parameter to NativeTapApi.
      final response = <String, Object?>{
        'status': 'Success',
        'x': matcher.x,
        'y': matcher.y,
      };
      if (rawDuration == null) {
        final result = await dispatchNativeTap(matcher.offset);
        // Surface fallback to caller so agents can detect that native overlays
        // were not actually tapped (only Flutter widgets received the tap).
        if (result == NativeTapResult.nativeFailedFallback) {
          response['warning'] = 'native_tap_fallback';
        }
      } else {
        await dispatchTap(matcher.offset, holdDuration: holdDuration);
      }
      return developer.ServiceExtensionResponse.result(jsonEncode(response));
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
    // Capture widgetType before the async gap: the tap may cause the widget
    // to disappear (e.g. a button that navigates away or hides itself), which
    // unmounts the element. Accessing element.widget after the await would
    // throw "Null check operator used on a null value".
    final widgetType = element.widget.runtimeType.toString();
    await dispatchTap(globalCenter, holdDuration: holdDuration);

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
