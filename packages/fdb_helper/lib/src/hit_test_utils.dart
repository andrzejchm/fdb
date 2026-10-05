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

  final center = renderObject.localToGlobal(renderObject.size.center(Offset.zero));
  if (_hits(renderObject, center)) return center;

  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  var visible = _globalRect(renderObject).intersect(Offset.zero & (view.physicalSize / view.devicePixelRatio));
  final RenderObject? viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport is RenderBox && viewport.hasSize) visible = visible.intersect(_globalRect(viewport));
  if (visible.isEmpty) return null;
  return _hits(renderObject, visible.center) ? visible.center : null;
}

Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

bool _hits(RenderBox renderObject, Offset globalPosition) {
  final result = HitTestResult();
  final viewId = WidgetsBinding.instance.platformDispatcher.views.first.viewId;
  WidgetsBinding.instance.hitTestInView(result, globalPosition, viewId);
  return result.path.any((entry) => entry.target == renderObject);
}
