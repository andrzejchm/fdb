import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Returns true if [element] is hittable, see [findHittablePoint].
bool isElementHittable(Element element) => findHittablePoint(element) != null;

/// Returns the global point at which a tap reaches [element], or null.
///
/// Tries the centre of the element first. If that misses (typically because
/// the element is partly scrolled out of its viewport or off the screen),
/// tries the centre of the element's visible part.
Offset? findHittablePoint(Element element) {
  final renderObject = element.renderObject;
  if (renderObject is! RenderBox) return null;
  if (!renderObject.hasSize || !renderObject.attached) return null;

  for (final point in tapCandidatePoints(renderObject)) {
    if (hitTestAt(point).path.any((entry) => entry.target == renderObject)) return point;
  }
  return null;
}

/// The global points to try, in order, when tapping [box]: its centre, then
/// the centre of its visible part. Empty when no part of [box] is visible.
List<Offset> tapCandidatePoints(RenderBox box) {
  final visible = visibleGlobalRect(box);
  if (visible.isEmpty) return const [];
  final center = box.localToGlobal(box.size.center(Offset.zero));
  return [center, if (visible.center != center) visible.center];
}

/// The part of [box] inside the screen and its viewport, in global coordinates.
Rect visibleGlobalRect(RenderBox box) {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  var visible = _globalRect(box).intersect(Offset.zero & (view.physicalSize / view.devicePixelRatio));
  final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport is RenderBox && viewport.hasSize) visible = visible.intersect(_globalRect(viewport));
  return visible;
}

/// Hit-tests the app's view at [globalPosition], like a real pointer would.
HitTestResult hitTestAt(Offset globalPosition) {
  final result = HitTestResult();
  final viewId = WidgetsBinding.instance.platformDispatcher.views.first.viewId;
  WidgetsBinding.instance.hitTestInView(result, globalPosition, viewId);
  return result;
}

Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
