import 'package:flutter/material.dart';

import 'hit_test_utils.dart';
import 'widget_matcher.dart';

/// Returns metadata for all interactive/text/keyed elements in the widget tree.
List<Map<String, dynamic>> findInteractiveElements() {
  final results = <Map<String, dynamic>>[];
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return results;

  void visit(Element element) {
    final widget = element.widget;
    final isInteractive = _isInteractiveWidget(widget.runtimeType);
    final text = _extractText(widget);
    final hasKey = widget.key is ValueKey<String>;

    if (isInteractive || text != null || hasKey) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox &&
          renderObject.hasSize &&
          renderObject.attached) {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final screenSize = view.physicalSize / view.devicePixelRatio;
        final screenRect = Offset.zero & screenSize;
        final elementRect = offset & size;
        final isVisible = screenRect.overlaps(elementRect);

        results.add({
          'type': widget.runtimeType.toString(),
          'key': hasKey ? (widget.key as ValueKey<String>).value : null,
          'text': text,
          'bounds': {
            'x': offset.dx,
            'y': offset.dy,
            'width': size.width,
            'height': size.height,
          },
          'visible': isVisible,
        });
      }

      // Don't recurse into interactive widgets (except GestureDetector/InkWell)
      // to avoid exposing internal sub-widgets.
      // Widgets that merely have text or a key are NOT pruned — only truly
      // interactive leaf widgets stop the traversal.
      if (isInteractive &&
          widget.runtimeType != GestureDetector &&
          widget.runtimeType != InkWell) {
        return; // skip children of interactive widgets only
      }
    }

    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return results;
}

/// Result of [findHittableElement].
///
/// [element] is the matched element (or null if none found or on error).
/// [matchCount] is the total number of hittable elements that matched.
typedef HittableElementResult = ({Element? element, int matchCount});

/// Finds the first (or Nth, if [matcher] has an index) hittable element
/// matching [matcher].
///
/// For [TextMatcher], if the matched element itself is not hittable (e.g. a
/// [Text] widget inside a button), walks up the ancestor chain to find the
/// nearest hittable ancestor and uses that for the tap target. This handles
/// the common case where `InkWell`/`GestureDetector` absorbs the hit instead
/// of the leaf `Text` render object.
///
/// Returns a record with the matched element and total match count.
/// When [matcher.index] is null and more than one element matches,
/// [element] is null and [matchCount] reflects the ambiguity.
HittableElementResult findHittableElement(WidgetMatcher matcher) {
  if (matcher is CoordinatesMatcher) return (element: null, matchCount: 0);

  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return (element: null, matchCount: 0);

  // For TextMatcher we need to track ancestors so we can walk up when the
  // matched Text element itself is not hittable.
  final bool needsAncestorWalk = matcher is TextMatcher;

  // Collect (matchedElement, resolvedHittableElement) pairs.
  // resolvedHittableElement may differ from matchedElement when we walk up.
  final matches = <Element>[];
  // Track resolved elements to avoid duplicates (e.g. two Text children of
  // the same button resolving to the same ancestor).
  final seen = <Element>{};

  void visit(Element element, List<Element> ancestors) {
    if (matcher.matches(element, extractText: _extractText)) {
      Element? hittable;
      if (isElementHittable(element)) {
        hittable = element;
      } else if (needsAncestorWalk) {
        // Walk up the ancestor chain (nearest first) to find a hittable one.
        for (var i = ancestors.length - 1; i >= 0; i--) {
          if (isElementHittable(ancestors[i])) {
            hittable = ancestors[i];
            break;
          }
        }
      }
      if (hittable != null && seen.add(hittable)) {
        matches.add(hittable);
      }
    }

    final nextAncestors =
        needsAncestorWalk ? [...ancestors, element] : const <Element>[];
    element.visitChildren((child) => visit(child, nextAncestors));
  }

  root.visitChildren((child) => visit(child, const []));

  if (matches.isEmpty) return (element: null, matchCount: 0);

  // Ambiguous: multiple matches and no index specified — caller must disambiguate.
  if (matcher.index == null && matches.length > 1) {
    return (element: null, matchCount: matches.length);
  }

  final targetIndex = matcher.index ?? 0;
  if (targetIndex >= matches.length) {
    return (element: null, matchCount: matches.length);
  }
  return (element: matches[targetIndex], matchCount: matches.length);
}

bool _isInteractiveWidget(Type type) =>
    type == Checkbox ||
    type == CheckboxListTile ||
    type == DropdownButton ||
    type == ElevatedButton ||
    type == FilledButton ||
    type == FloatingActionButton ||
    type == GestureDetector ||
    type == IconButton ||
    type == InkWell ||
    type == OutlinedButton ||
    type == PopupMenuButton ||
    type == Radio ||
    type == RadioListTile ||
    type == Slider ||
    type == Switch ||
    type == SwitchListTile ||
    type == TextButton ||
    type == TextField ||
    type == TextFormField;

String? _extractText(Widget widget) {
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is RichText) return widget.text.toPlainText();
  if (widget is EditableText) return widget.controller.text;
  return null;
}
