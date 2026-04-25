import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../element_tree_finder.dart';
import '../hit_test_utils.dart';
import 'handler_utils.dart';

const _interestingGestures = {
  'horizontalDrag',
  'verticalDrag',
  'pan',
  'longPress',
  'scale',
  'doubleTap',
  'forcePress',
};

Future<developer.ServiceExtensionResponse> handleElements(
  String method,
  Map<String, String> params,
) async {
  try {
    final elements = findInteractiveElements();
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'status': 'Success', 'elements': elements}),
    );
  } catch (e) {
    return errorResponse('Failed to list elements: $e');
  }
}

Future<developer.ServiceExtensionResponse> handleDescribe(
  String method,
  Map<String, String> params,
) async {
  try {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return errorResponse('No root element available');
    }

    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;
    final screenRect = Offset.zero & screenSize;

    final interactive = <Map<String, dynamic>>[];
    final texts = <String>{};
    String? screenName;
    String? routeName;

    // Tracks the nearest enclosing Tooltip message while walking the tree.
    String? currentTooltip;

    void visit(Element element) {
      final widget = element.widget;
      final typeName = widget.runtimeType.toString();

      // Skip entire subtrees wrapped in Offstage(offstage: true).
      if (typeName == 'Offstage') {
        try {
          final offstage = (widget as dynamic).offstage as bool;
          if (offstage) return;
        } catch (_) {}
      }

      // Collect route name from ModalRoute.
      if (element is StatefulElement) {
        final route = ModalRoute.of(element);
        if (route != null) {
          routeName = route.settings.name;
        }
      }

      // Collect Scaffold title as screen name by walking AppBar children.
      if (screenName == null && typeName == 'Scaffold') {
        void findAppBarTitle(Element el) {
          if (screenName != null) return;
          final w = el.widget;
          final wType = w.runtimeType.toString();
          if (wType == 'AppBar' || wType == 'SliverAppBar') {
            void findTitle(Element titleEl) {
              if (screenName != null) return;
              final tw = titleEl.widget;
              if (tw is Text) {
                final t = tw.data ?? tw.textSpan?.toPlainText();
                if (t != null && t.trim().isNotEmpty) {
                  screenName = t.trim();
                }
                return;
              }
              titleEl.visitChildren(findTitle);
            }

            el.visitChildren(findTitle);
            return;
          }
          el.visitChildren(findAppBarTitle);
        }

        element.visitChildren(findAppBarTitle);
      }

      // Track Tooltip context so inner interactive widgets can inherit it.
      String? previousTooltip;
      if (typeName == 'Tooltip') {
        previousTooltip = currentTooltip;
        try {
          final msg = (widget as dynamic).message as String?;
          if (msg != null && msg.trim().isNotEmpty) {
            currentTooltip = msg.trim();
          }
        } catch (_) {}
      }

      final renderObject = element.renderObject;
      if (renderObject is RenderBox &&
          renderObject.hasSize &&
          renderObject.attached) {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;

        // Skip zero-size or off-screen widgets.
        if (size.isEmpty) {
          element.visitChildren(visit);
          if (typeName == 'Tooltip') currentTooltip = previousTooltip;
          return;
        }
        final elementRect = offset & size;
        if (!screenRect.overlaps(elementRect)) {
          element.visitChildren(visit);
          if (typeName == 'Tooltip') currentTooltip = previousTooltip;
          return;
        }

        // Collect visible text.
        if (widget is Text) {
          final text = widget.data ?? widget.textSpan?.toPlainText();
          if (text != null && text.trim().isNotEmpty) {
            texts.add(text.trim());
          }
        } else if (widget is RichText) {
          final text = widget.text.toPlainText().trim();
          if (text.isNotEmpty) texts.add(text);
        } else if (widget is EditableText) {
          final text = widget.controller.text.trim();
          if (text.isNotEmpty) texts.add(text);
        }

        // Collect interactive widgets.
        if (_isDescribeInteractiveWidget(typeName)) {
          if (!isElementHittable(element)) {
            if (typeName == 'Tooltip') currentTooltip = previousTooltip;
            return;
          }

          final key = widget.key is ValueKey<String>
              ? (widget.key as ValueKey<String>).value
              : null;
          final visibleText =
              _extractDescribeText(element, tooltipHint: currentTooltip);
          final gestures = _extractGestures(widget, typeName);
          interactive.add({
            'type': typeName,
            'key': key,
            'text': visibleText,
            'x': offset.dx + size.width / 2,
            'y': offset.dy + size.height / 2,
            if (gestures != null) 'gestures': gestures,
          });

          // Still collect text from children for the TEXT section.
          void collectText(Element el) {
            final w = el.widget;
            if (w is Text) {
              final t = w.data ?? w.textSpan?.toPlainText();
              if (t != null && t.trim().isNotEmpty) texts.add(t.trim());
            } else if (w is RichText) {
              final t = w.text.toPlainText().trim();
              if (t.isNotEmpty) texts.add(t);
            }
            el.visitChildren(collectText);
          }

          element.visitChildren(collectText);

          if (typeName == 'Tooltip') currentTooltip = previousTooltip;
          return;
        }
      }

      element.visitChildren(visit);
      if (typeName == 'Tooltip') currentTooltip = previousTooltip;
    }

    root.visitChildren(visit);

    interactive.removeWhere((entry) {
      final text = entry['text'] as String?;
      final key = entry['key'] as String?;
      final gestures =
          (entry['gestures'] as List<dynamic>?)?.cast<String>() ?? [];
      final hasText = text != null &&
          text.trim().isNotEmpty &&
          text.runes.any((r) => r < 0xE000 || r > 0xF8FF);
      final hasKey = key != null;
      final hasInterestingGesture =
          gestures.any((g) => _interestingGestures.contains(g));
      return !hasText && !hasKey && !hasInterestingGesture;
    });

    interactive.sort((a, b) {
      final yA = (a['y'] as double);
      final yB = (b['y'] as double);
      if ((yA - yB).abs() > 10) return yA.compareTo(yB);
      return (a['x'] as double).compareTo(b['x'] as double);
    });

    for (var i = 0; i < interactive.length; i++) {
      interactive[i]['ref'] = i + 1;
    }

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'screen': screenName,
        'route': routeName,
        'interactive': interactive,
        'texts': texts.toList(),
      }),
    );
  } catch (e) {
    return errorResponse('describe failed: $e');
  }
}

bool _isDescribeInteractiveWidget(String typeName) => const {
      'Checkbox',
      'CheckboxListTile',
      'DropdownButton',
      'ElevatedButton',
      'FilledButton',
      'FloatingActionButton',
      'GestureDetector',
      'IconButton',
      'InkWell',
      'ListTile',
      'OutlinedButton',
      'PopupMenuButton',
      'Radio',
      'RadioListTile',
      'Slider',
      'Switch',
      'SwitchListTile',
      'Tab',
      'TextButton',
      'TextField',
      'TextFormField',
    }.contains(typeName);

String? _extractDescribeText(
  Element element, {
  String? tooltipHint,
}) {
  final widget = element.widget;
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is RichText) return widget.text.toPlainText();
  if (widget is EditableText) return widget.controller.text;

  final fragments = <String>[];

  bool hasVisibleText(String s) =>
      s.trim().isNotEmpty && s.runes.any((r) => r < 0xE000 || r > 0xF8FF);

  void findTextAndIcons(Element el) {
    final w = el.widget;

    if (w is Text) {
      final t = w.data ?? w.textSpan?.toPlainText();
      if (t != null && hasVisibleText(t)) fragments.add(t.trim());
      return;
    }
    if (w is RichText) {
      final t = w.text.toPlainText().trim();
      if (hasVisibleText(t)) fragments.add(t);
      return;
    }
    if (w is EditableText) {
      final t = w.controller.text.trim();
      if (hasVisibleText(t)) fragments.add(t);
      return;
    }

    final wType = w.runtimeType.toString();

    if (wType == 'Tooltip') {
      try {
        final message = (w as dynamic).message as String?;
        if (message != null && message.trim().isNotEmpty) {
          fragments.add('[${message.trim()}]');
        }
      } catch (_) {}
    }

    if (wType == 'Icon') {
      try {
        final label = (w as dynamic).semanticLabel as String?;
        if (label != null && label.trim().isNotEmpty) {
          fragments.add('[icon: ${label.trim()}]');
        }
      } catch (_) {}
    }

    el.visitChildren(findTextAndIcons);
  }

  element.visitChildren(findTextAndIcons);

  if (fragments.isEmpty && tooltipHint != null) {
    return '[${tooltipHint.trim()}]';
  }

  if (fragments.isEmpty) return null;
  final cleaned = fragments.where((f) => f.trim().isNotEmpty).toList();
  if (cleaned.isEmpty) return null;
  return cleaned.join(' · ');
}

List<String>? _extractGestures(Widget widget, String typeName) {
  if (typeName != 'GestureDetector' && typeName != 'InkWell') return null;

  final gestures = <String>[];
  try {
    final w = widget as dynamic;
    if (typeName == 'GestureDetector') {
      if (w.onTap != null) gestures.add('tap');
      if (w.onDoubleTap != null) gestures.add('doubleTap');
      if (w.onLongPress != null) gestures.add('longPress');
      if (w.onVerticalDragStart != null ||
          w.onVerticalDragUpdate != null ||
          w.onVerticalDragEnd != null) {
        gestures.add('verticalDrag');
      }
      if (w.onHorizontalDragStart != null ||
          w.onHorizontalDragUpdate != null ||
          w.onHorizontalDragEnd != null) {
        gestures.add('horizontalDrag');
      }
      if (w.onPanStart != null || w.onPanUpdate != null || w.onPanEnd != null) {
        gestures.add('pan');
      }
      if (w.onScaleStart != null ||
          w.onScaleUpdate != null ||
          w.onScaleEnd != null) {
        gestures.add('scale');
      }
      if (w.onForcePressStart != null || w.onForcePressPeak != null) {
        gestures.add('forcePress');
      }
    } else if (typeName == 'InkWell') {
      if (w.onTap != null) gestures.add('tap');
      if (w.onDoubleTap != null) gestures.add('doubleTap');
      if (w.onLongPress != null) gestures.add('longPress');
    }
  } catch (_) {
    // Dynamic access failed — widget API changed; return what we have.
  }
  return gestures.isEmpty ? null : gestures;
}
