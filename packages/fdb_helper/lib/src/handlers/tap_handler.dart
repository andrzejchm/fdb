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
      // For quick taps and long-presses by coordinate, use native in-process
      // injection so that native overlays (UIAlertController, WKWebView,
      // platform views, AlertDialog) are reachable — not just Flutter widgets.
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
        final result = await dispatchNativeLongPress(
          matcher.offset,
          holdDuration: holdDuration,
        );
        if (result == NativeTapResult.nativeFailedFallback) {
          response['warning'] = 'native_long_press_fallback';
        }
      }
      return developer.ServiceExtensionResponse.result(jsonEncode(response));
    }

    final refElement = matcher is RefMatcher ? matcher.element ?? findScrollTargetElement(matcher) : null;
    final mismatch = refElement != null ? _expectationError(refElement, params, (matcher as RefMatcher).ref) : null;
    if (mismatch != null) return errorResponse(mismatch);

    final (:target, :error) = findGestureTarget(matcher, rejectDisabled: true);
    if (target == null) return errorResponse(error!);
    final (:element, point: globalCenter) = target;

    // Capture widgetType before the async gap: the tap may cause the widget
    // to disappear (e.g. a button that navigates away or hides itself), which
    // unmounts the element. Accessing element.widget after the await would
    // throw "Null check operator used on a null value".
    final widgetType = element.widget.runtimeType.toString();
    final refText = refElement != null ? describeElementText(refElement) : null;
    await dispatchTap(globalCenter, holdDuration: holdDuration);

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'widgetType': widgetType,
        'x': globalCenter.dx,
        'y': globalCenter.dy,
        if (refText != null) 'text': refText,
      }),
    );
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('Tap failed: $e');
  }
}

/// The error when the widget behind `@ref` no longer has the `expectType` /
/// `expectText` the agent saw (`fdb tap @N --expect-type/--expect-text`).
///
/// The ref still names the same element, but its widget may have changed,
/// e.g. a "Follow" button that now reads "Unfollow".
String? _expectationError(Element element, Map<String, String> params, int ref) {
  final expectType = params['expectType'];
  final expectText = params['expectText'];
  if (expectType == null && expectText == null) return null;

  final type = element.widget.runtimeType.toString();
  final parts = (describeElementText(element) ?? '')
      .split(' · ')
      .map((part) => part.trim())
      .where((part) => part.runes.any((r) => r < 0xE000 || r > 0xF8FF))
      .toList();
  final text = parts.isEmpty ? null : parts.join(' · ');
  final textMatches = expectText == null || text == expectText || parts.contains(expectText);
  if (textMatches && (expectType == null || type == expectType)) return null;

  final actual = text != null ? '$type "$text"' : type;
  final expected = [if (expectType != null) expectType, if (expectText != null) '"$expectText"'].join(' ');
  return '@$ref is now $actual, not $expected. Nothing was tapped. Run fdb describe again.';
}
