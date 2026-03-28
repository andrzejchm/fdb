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
      if (isInteractive &&
          widget.runtimeType != GestureDetector &&
          widget.runtimeType != InkWell) {
        return;
      }
    }

    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return results;
}

/// Finds the first (or Nth, if [matcher] has an index) hittable element
/// matching [matcher].
///
/// Returns null if no matching hittable element is found.
Element? findHittableElement(WidgetMatcher matcher) {
  if (matcher is CoordinatesMatcher) return null;

  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  final matches = <Element>[];

  void visit(Element element) {
    if (matcher.matches(element, extractText: _extractText)) {
      if (isElementHittable(element)) {
        matches.add(element);
      }
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);

  if (matches.isEmpty) return null;

  final targetIndex = matcher.index ?? 0;
  if (targetIndex >= matches.length) return null;
  return matches[targetIndex];
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
