import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Returns true if [element] is hittable at its center point.
///
/// An element is hittable if its render object is attached, has a size, and
/// the hit test at its center point reaches that render object.
bool isElementHittable(Element element) {
  final renderObject = element.renderObject;
  if (renderObject is! RenderBox) return false;
  if (!renderObject.hasSize || !renderObject.attached) return false;

  final center = renderObject.size.center(Offset.zero);
  final absoluteCenter = renderObject.localToGlobal(center);

  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final viewId = view.viewId;

  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, absoluteCenter, viewId);

  for (final entry in result.path) {
    if (entry.target == renderObject) return true;
  }
  return false;
}
