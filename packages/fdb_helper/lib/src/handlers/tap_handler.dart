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

    // For selector-based taps (--key, --text, --type), prefer direct callback
    // invocation over a synthetic pointer event dispatched at coordinates.
    //
    // Dispatching at coordinates goes through GestureBinding's hit-test, which
    // registers every GestureDetector in the hit path — including opaque
    // ancestors. When an ancestor GestureDetector has HitTestBehavior.opaque
    // (common when swipe gestures are enabled), its onTap fires alongside the
    // target's onTap. For the PhotoActionsToolbar pattern this causes the
    // photo-area toggle GestureDetector to fire every time a toolbar button is
    // tapped, immediately hiding the overlay.
    //
    // Direct invocation finds the nearest GestureDetector with onTap at or
    // above the matched element and calls the callback directly, bypassing the
    // gesture arena entirely. Coordinates are still computed and returned so
    // callers know where the widget is.
    //
    // Long-press (rawDuration != null) cannot be direct-invoked this way
    // because GestureDetector.onLongPress does not expose its recognizer
    // publicly, and the timing semantics matter. Fall back to dispatchTap for
    // long-press.
    if (rawDuration == null) {
      final invoked = _tryDirectInvokeTap(element);
      if (invoked) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        final widgetType = element.widget.runtimeType.toString();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'status': 'Success',
            'widgetType': widgetType,
            'x': globalCenter.dx,
            'y': globalCenter.dy,
          }),
        );
      }
      // No GestureDetector with onTap found — fall through to dispatchTap.
    }

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

/// Attempts to invoke the [onTap] callback of the [GestureDetector] that IS
/// [element] (i.e. only if the matched element itself is a [GestureDetector]
/// with a non-null [onTap]) without dispatching a synthetic pointer event.
///
/// Returns true if [element] is a [GestureDetector] with [onTap] and the
/// callback was invoked. Returns false otherwise, leaving the caller to fall
/// back to [dispatchTap].
///
/// **Why only the matched element — not ancestors?**
///
/// [findHittableElement] already resolves the target upward: if the keyed
/// widget is not hittable, the ancestor walk inside [findHittableElement]
/// finds the nearest interactive ancestor. So by the time [element] arrives
/// here, it IS the intended tap target. Walking further up would risk hitting
/// unrelated ancestor [GestureDetector]s (e.g. [Scaffold]'s drawer gesture,
/// or a page-level scroll handler).
///
/// This check handles the critical [PhotoActionsToolbar] pattern where:
/// - The toolbar button widget has `key: Key('approve_btn')`.
/// - That widget is a [GestureDetector] with [onTap].
/// - An ancestor [GestureDetector] wrapping the whole screen has
///   [HitTestBehavior.opaque], so [dispatchTap] at the button's coordinates
///   also triggers the ancestor's [onTap], hiding the overlay as a side effect.
///
/// Direct invocation bypasses [GestureBinding] entirely, so only the target's
/// [onTap] fires.
bool _tryDirectInvokeTap(Element element) {
  final widget = element.widget;
  if (widget is GestureDetector && widget.onTap != null) {
    widget.onTap!();
    return true;
  }
  return false;
}
