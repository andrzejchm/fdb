import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../element_tree_finder.dart';
import '../gesture_dispatcher.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

/// Minimum pixel movement required to consider a scroll attempt as non-stalled.
/// If the scroll position changes by less than this amount after a drag gesture,
/// the attempt is counted as a stall.
const double _stallThresholdPixels = 0.5;

/// How long to wait after a drag gesture for scroll physics to settle before
/// reading [ScrollPosition.pixels], [ScrollPosition.extentAfter], and
/// [ScrollPosition.extentBefore].
const Duration _scrollSettleDuration = Duration(milliseconds: 80);

/// How many consecutive edge readings are required before treating the scroll
/// edge as truly reached. Guards against transient zero readings of
/// [ScrollPosition.extentAfter] (forward edge) or [ScrollPosition.extentBefore]
/// (backward edge) that can occur during [ListView.builder] rebuild mid-scroll.
const int _edgeConfirmationCount = 2;

/// How many consecutive stall readings are required before treating the scroll
/// as truly stuck and reversing direction. A stall is counted when
/// [ScrollPosition.pixels] changes by less than [_stallThresholdPixels] after
/// a drag gesture.
const int _stallConfirmationCount = 3;

/// Minimum scroll range (in pixels) a Scrollable must have to be considered
/// a meaningful scroll container. Scrollables with a range at or below this
/// value (e.g. fully-visible lists with no overflow) are ignored when
/// selecting the best Scrollable for scroll-to.
const double _minScrollRangePixels = 0.5;

/// Pixel distance of each drag gesture used by scroll-to.
/// Matches the default step used by `fdb scroll`, large enough to produce
/// scroll physics momentum on all platforms.
const double _scrollStepPixels = 200.0;

Future<developer.ServiceExtensionResponse> handleScrollTo(
  String method,
  Map<String, String> params,
) async {
  try {
    final matcher = WidgetMatcher.fromParams(params);

    if (matcher is FocusedMatcher) {
      return errorResponse('scroll-to does not support --focused');
    }

    // Check if the target widget is already visible before requiring a Scrollable.
    final earlyResult = findHittableElement(matcher);
    if (earlyResult.element != null) {
      final ensureVisibleTarget =
          findScrollTargetElement(matcher) ?? earlyResult.element!;
      final earlyRenderObject = ensureVisibleTarget.renderObject;
      if (earlyRenderObject is RenderBox) {
        ScrollPosition? earlyPosition;
        ensureVisibleTarget.visitAncestorElements((ancestor) {
          if (ancestor.widget is Scrollable) {
            earlyPosition = _tryGetScrollPosition(ancestor);
            return false;
          }
          return true;
        });
        return await _ensureVisibleAndReport(
          ensureVisibleTarget: ensureVisibleTarget,
          fallbackRenderObject: earlyRenderObject,
          position: earlyPosition,
          alignment: 0.0,
        );
      }
    }
    if (earlyResult.matchCount > 1) {
      return errorResponse(
        'Found ${earlyResult.matchCount} elements matching the selector. '
        'Use --index to specify which one (0-based).',
      );
    }

    final scrollableElement = _findBestScrollable(matcher);
    if (scrollableElement == null) {
      return errorResponse('No Scrollable found in the widget tree');
    }

    final position = _tryGetScrollPosition(scrollableElement);
    if (position == null) {
      return errorResponse('Could not read ScrollPosition from Scrollable');
    }

    final scrollableWidget = scrollableElement.widget as Scrollable;
    final axisDirection = scrollableWidget.axisDirection;

    var moveStep = switch (axisDirection) {
      AxisDirection.down => const Offset(0, -_scrollStepPixels),
      AxisDirection.up => const Offset(0, _scrollStepPixels),
      AxisDirection.right => const Offset(-_scrollStepPixels, 0),
      AxisDirection.left => const Offset(_scrollStepPixels, 0),
    };

    final maxAttempts = _calculateMaxAttempts(position);
    var reversedOnce = false;
    var stallCount = 0;
    var edgeCount = 0;
    var attempt = 0;

    while (attempt < maxAttempts) {
      // Check if target is now in tree and hittable.
      final (:element, :matchCount) = findHittableElement(matcher);
      if (element != null) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox) {
          final ensureVisibleTarget =
              findScrollTargetElement(matcher) ?? element;
          return await _ensureVisibleAndReport(
            ensureVisibleTarget: ensureVisibleTarget,
            fallbackRenderObject: renderObject,
            position: position,
            alignment: 0.5,
          );
        }
      }
      if (matchCount > 1) {
        return errorResponse(
          'Found $matchCount elements matching the selector. '
          'Use --index to specify which one (0-based).',
        );
      }

      // Perform drag gesture on the Scrollable's center.
      final scrollableRenderObject = scrollableElement.renderObject;
      if (scrollableRenderObject is! RenderBox) break;

      final scrollableCenter = scrollableRenderObject.size.center(Offset.zero);
      final scrollableGlobalCenter =
          scrollableRenderObject.localToGlobal(scrollableCenter);

      final currentPixels = position.pixels;

      await dispatchScroll(
        start: scrollableGlobalCenter,
        end: scrollableGlobalCenter + moveStep,
      );

      // Wait for scroll physics to settle before reading position.
      await Future<void>.delayed(_scrollSettleDuration);

      // Stall detection: if position didn't change, reverse or give up.
      final newPixels = position.pixels;
      if ((newPixels - currentPixels).abs() < _stallThresholdPixels) {
        stallCount++;
        if (stallCount >= _stallConfirmationCount) {
          if (!reversedOnce) {
            moveStep = -moveStep;
            reversedOnce = true;
            stallCount = 0;
            edgeCount = 0;
            attempt = 0;
            continue;
          } else {
            break;
          }
        }
      } else {
        stallCount = 0;
      }

      // Detect scroll edge to decide whether to reverse or give up.
      final scrollingForward = switch (axisDirection) {
        AxisDirection.down => moveStep.dy < 0,
        AxisDirection.up => moveStep.dy > 0,
        AxisDirection.right => moveStep.dx < 0,
        AxisDirection.left => moveStep.dx > 0,
      };
      final atCurrentEdge = scrollingForward
          ? position.extentAfter <= 0
          : position.extentBefore <= 0;

      if (atCurrentEdge) {
        edgeCount++;
        if (edgeCount >= _edgeConfirmationCount) {
          if (!reversedOnce) {
            moveStep = -moveStep;
            reversedOnce = true;
            stallCount = 0;
            edgeCount = 0;
            attempt = 0;
            continue;
          } else {
            break;
          }
        }
      } else {
        edgeCount = 0;
      }

      attempt++;
    }

    // Final check after loop exhaustion.
    final (:element, :matchCount) = findHittableElement(matcher);
    if (element != null) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox) {
        final ensureVisibleTarget = findScrollTargetElement(matcher) ?? element;
        return await _ensureVisibleAndReport(
          ensureVisibleTarget: ensureVisibleTarget,
          fallbackRenderObject: renderObject,
          position: position,
          alignment: 0.5,
        );
      }
    }
    if (matchCount > 1) {
      return errorResponse(
        'Found $matchCount elements matching the selector. '
        'Use --index to specify which one (0-based).',
      );
    }

    return errorResponse('Widget not found after scrolling through the list');
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('scrollTo failed: $e');
  }
}

Future<developer.ServiceExtensionResponse> _ensureVisibleAndReport({
  required Element ensureVisibleTarget,
  required RenderBox fallbackRenderObject,
  ScrollPosition? position,
  required double alignment,
}) async {
  if (position != null) {
    position.jumpTo(position.pixels);
  } else {
    WidgetsBinding.instance.scheduleFrame();
  }
  await WidgetsBinding.instance.endOfFrame;
  await Scrollable.ensureVisible(
    ensureVisibleTarget,
    alignment: alignment,
    duration: Duration.zero,
  );
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;
  final targetRenderObject = ensureVisibleTarget.renderObject;
  final reportRenderObject = targetRenderObject is RenderBox
      ? targetRenderObject
      : fallbackRenderObject;
  final center = reportRenderObject.size.center(Offset.zero);
  final globalCenter = reportRenderObject.localToGlobal(center);
  final widgetType = ensureVisibleTarget.widget.runtimeType.toString();
  return developer.ServiceExtensionResponse.result(
    jsonEncode({
      'status': 'Success',
      'widgetType': widgetType,
      'x': globalCenter.dx,
      'y': globalCenter.dy,
    }),
  );
}

Element? _findBestScrollable(WidgetMatcher matcher) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  Element? targetElement;
  void findTarget(Element el) {
    if (targetElement != null) return;
    if (matcher.matches(el, extractText: extractWidgetText)) {
      targetElement = el;
      return;
    }
    el.visitChildren(findTarget);
  }

  root.visitChildren(findTarget);

  if (targetElement != null) {
    Element? ancestor;
    targetElement!.visitAncestorElements((el) {
      if (el.widget is Scrollable) {
        ancestor = el;
        return false;
      }
      return true;
    });
    if (ancestor != null) return ancestor;
  }

  Element? fallback;
  Element? lastWithRange;

  void visitForScrollable(Element el) {
    if (el.widget.runtimeType.toString() == 'Offstage') {
      try {
        final offstage = (el.widget as dynamic).offstage as bool;
        if (offstage) return;
      } catch (_) {}
    }
    if (el.widget is Scrollable) {
      fallback ??= el;
      final scrollPosition = _tryGetScrollPosition(el);
      if (scrollPosition != null) {
        final range =
            (scrollPosition.maxScrollExtent - scrollPosition.minScrollExtent)
                .abs();
        if (range > _minScrollRangePixels) {
          lastWithRange = el;
        }
      }
    }
    el.visitChildren(visitForScrollable);
  }

  root.visitChildren(visitForScrollable);
  return lastWithRange ?? fallback;
}

ScrollPosition? _tryGetScrollPosition(Element scrollableElement) {
  try {
    final state =
        (scrollableElement as StatefulElement).state as ScrollableState;
    return state.position;
  } catch (_) {
    return null;
  }
}

int _calculateMaxAttempts(ScrollPosition position) {
  final extent = (position.maxScrollExtent - position.minScrollExtent).abs();
  if (!extent.isFinite) return 50;
  return ((extent / _scrollStepPixels).ceil() * 2 + 20).clamp(1, 200);
}
