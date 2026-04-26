import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../element_tree_finder.dart';
import '../gesture_dispatcher.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

typedef _DoubleTapTarget = ({GestureTapCallback callback, Element element});

Future<developer.ServiceExtensionResponse> handleDoubleTap(
  String method,
  Map<String, String> params,
) async {
  try {
    final matcher = WidgetMatcher.fromParams(params);

    if (matcher is CoordinatesMatcher) {
      final targetElement = _findElementAtOffset(matcher.offset);
      if (targetElement == null) {
        return errorResponse('No element found at (${matcher.x}, ${matcher.y})');
      }

      final doubleTapTarget = _findDoubleTapTargetForElement(targetElement);

      final didDoubleTap = await _performDoubleTap(matcher.offset);
      if (!didDoubleTap) {
        return errorResponse(
          'No double-tap target found at (${matcher.x}, ${matcher.y}) on macOS',
        );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'widgetType': (doubleTapTarget?.element ?? targetElement).widget.runtimeType.toString(),
          'x': matcher.x,
          'y': matcher.y,
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

    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      return errorResponse('Element has no RenderBox');
    }

    final center = renderObject.size.center(Offset.zero);
    final globalCenter = renderObject.localToGlobal(center);
    final doubleTapTarget = _findDoubleTapTargetForElement(element);
    if (doubleTapTarget == null) {
      return errorResponse('Matched element has no onDoubleTap handler');
    }

    final didDoubleTap = await _performDoubleTap(globalCenter, element: doubleTapTarget.element);
    if (!didDoubleTap) {
      return errorResponse('No double-tap target found for matcher on macOS');
    }

    final widgetType = doubleTapTarget.element.widget.runtimeType.toString();
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
    return errorResponse('Double-tap failed: $e');
  }
}

Future<bool> _performDoubleTap(Offset globalPosition, {Element? element}) async {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final callback = element != null
        ? _findDoubleTapTargetForElement(element)?.callback
        : _findDoubleTapCallbackAtOffset(globalPosition);
    if (callback != null) {
      callback();
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return true;
    }

    return false;
  }

  await dispatchDoubleTap(globalPosition);
  return true;
}

GestureTapCallback? _findDoubleTapCallbackAtOffset(Offset globalPosition) {
  final matchedElement = _findElementAtOffset(globalPosition);
  if (matchedElement != null) {
    final doubleTapTarget = _findDoubleTapTargetForElement(matchedElement);
    if (doubleTapTarget != null) {
      return doubleTapTarget.callback;
    }
  }

  final hitTestCallback = _findDoubleTapCallbackFromHitTest(globalPosition);
  if (hitTestCallback != null) {
    return hitTestCallback;
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return null;
  }

  GestureTapCallback? matchedCallback;
  double? matchedArea;

  void visit(Element element) {
    final callback = _doubleTapCallbackForWidget(element.widget);
    if (callback != null) {
      final bounds = _subtreeBounds(element);
      if (bounds != null && bounds.contains(globalPosition)) {
        final area = bounds.width * bounds.height;
        if (matchedArea == null || area <= matchedArea!) {
          matchedCallback = callback;
          matchedArea = area;
        }
      }
    }

    element.visitChildren(visit);
  }

  root.visitChildren(visit);

  return matchedCallback;
}

Element? _findElementAtOffset(Offset globalPosition) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return null;
  }

  final viewId = WidgetsBinding.instance.platformDispatcher.views.first.viewId;
  final hitTestResult = HitTestResult();
  WidgetsBinding.instance.hitTestInView(hitTestResult, globalPosition, viewId);

  final hitRenderObjects = hitTestResult.path.map((entry) => entry.target).whereType<RenderObject>().toSet();

  if (hitRenderObjects.isNotEmpty) {
    Element? matchedHitElement;
    int? matchedHitDepth;

    void visitHit(Element element, int depth) {
      final renderObject = element.renderObject;
      if (renderObject != null && hitRenderObjects.contains(renderObject)) {
        if (matchedHitDepth == null || depth >= matchedHitDepth!) {
          matchedHitElement = element;
          matchedHitDepth = depth;
        }
      }

      element.visitChildren((child) {
        visitHit(child, depth + 1);
      });
    }

    root.visitChildren((child) {
      visitHit(child, 1);
    });

    if (matchedHitElement != null) {
      return matchedHitElement;
    }
  }

  Element? matchedElement;
  int? matchedDepth;

  void visit(Element element, int depth) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize && renderObject.attached) {
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(globalPosition) && (matchedDepth == null || depth >= matchedDepth!)) {
        matchedElement = element;
        matchedDepth = depth;
      }
    }

    element.visitChildren((child) {
      visit(child, depth + 1);
    });
  }

  root.visitChildren((child) {
    visit(child, 1);
  });

  return matchedElement;
}

Rect? _subtreeBounds(Element element) {
  Rect? bounds;

  void visit(Element current) {
    final renderObject = current.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize && renderObject.attached) {
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }

    current.visitChildren(visit);
  }

  visit(element);
  return bounds;
}

GestureTapCallback? _findDoubleTapCallbackFromHitTest(Offset globalPosition) {
  final viewId = WidgetsBinding.instance.platformDispatcher.views.first.viewId;
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, globalPosition, viewId);

  for (final entry in result.path.toList().reversed) {
    final target = entry.target;
    if (target is! RenderObject) {
      continue;
    }

    final debugCreator = target.debugCreator;
    if (debugCreator is! DebugCreator) {
      continue;
    }

    final doubleTapTarget = _findDoubleTapTargetForElement(debugCreator.element);
    if (doubleTapTarget != null) {
      return doubleTapTarget.callback;
    }
  }

  return null;
}

_DoubleTapTarget? _findDoubleTapTargetForElement(Element element) {
  final ownCallback = _doubleTapCallbackForElementWidget(element);
  if (ownCallback != null) {
    return (callback: ownCallback, element: element);
  }

  _DoubleTapTarget? descendantTarget;
  void visitDescendant(Element descendant) {
    if (descendantTarget != null) {
      return;
    }

    final callback = _doubleTapCallbackForElementWidget(descendant);
    if (callback != null) {
      descendantTarget = (callback: callback, element: descendant);
      return;
    }

    descendant.visitChildren(visitDescendant);
  }

  element.visitChildren(visitDescendant);
  if (descendantTarget != null) {
    return descendantTarget;
  }

  _DoubleTapTarget? ancestorTarget;
  element.visitAncestorElements((ancestor) {
    final callback = _doubleTapCallbackForElementWidget(ancestor);
    if (callback == null) {
      return true;
    }
    ancestorTarget = (callback: callback, element: ancestor);
    return false;
  });
  return ancestorTarget;
}

GestureTapCallback? _doubleTapCallbackForElementWidget(Element element) {
  final widgetCallback = _doubleTapCallbackForWidget(element.widget);
  if (widgetCallback != null) {
    return widgetCallback;
  }

  if (element.widget is RawGestureDetector) {
    final widget = element.widget as RawGestureDetector;
    final factory = widget.gestures[DoubleTapGestureRecognizer];
    if (factory != null) {
      final recognizer = factory.constructor();
      try {
        if (recognizer is DoubleTapGestureRecognizer) {
          factory.initializer(recognizer);
          final callback = recognizer.onDoubleTap;
          if (callback != null) {
            return callback;
          }
        }
      } finally {
        recognizer.dispose();
      }
    }
  }

  return null;
}

GestureTapCallback? _doubleTapCallbackForWidget(Widget widget) {
  if (widget is GestureDetector) {
    return widget.onDoubleTap;
  }
  if (widget is InkWell) {
    return widget.onDoubleTap;
  }
  if (widget is InkResponse) {
    return widget.onDoubleTap;
  }
  return null;
}
