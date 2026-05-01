import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
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

    // Cap: collect at most this many interactive entries to avoid
    // materialising huge or infinite eagerly-built lists (e.g. GridView.count
    // with thousands of items). Callers should paginate or scroll if they need
    // elements beyond this limit.
    const maxInteractive = 200;

    // Tracks the nearest enclosing Tooltip message while walking the tree.
    String? currentTooltip;

    // The route that was "current" the last time we saw a ModalRoute boundary
    // while descending. Used to detect when we enter a non-current route's
    // subtree so we can skip it entirely.
    ModalRoute<dynamic>? activeRouteContext;

    void visit(Element element) {
      // Stop collecting interactive entries once the cap is reached.
      if (interactive.length >= maxInteractive) return;

      final widget = element.widget;
      final typeName = widget.runtimeType.toString();

      // Skip entire subtrees wrapped in Offstage(offstage: true).
      if (typeName == 'Offstage') {
        try {
          final offstage = (widget as dynamic).offstage as bool;
          if (offstage) return;
        } catch (_) {}
      }

      // Skip subtrees belonging to non-current routes (e.g. underlying screens
      // kept alive by the Navigator stack). When a StatefulElement introduces a
      // new ModalRoute boundary that is not the current (topmost) route, its
      // entire subtree is off-screen from the user's perspective — even though
      // the render objects may report valid pixel coordinates — so we prune it.
      if (element is StatefulElement) {
        final route = ModalRoute.of(element);
        if (route != null && route != activeRouteContext) {
          // We have crossed into a new route boundary.
          if (!route.isCurrent) {
            // This route is not the topmost active route — skip its subtree.
            return;
          }
          // This is the current route: record it and collect the route name.
          activeRouteContext = route;
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
      if (renderObject is RenderBox && renderObject.hasSize && renderObject.attached) {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;

        // Skip zero-size widgets entirely.
        if (size.isEmpty) {
          element.visitChildren(visit);
          if (typeName == 'Tooltip') currentTooltip = previousTooltip;
          return;
        }

        final elementRect = offset & size;
        final isOnScreen = screenRect.overlaps(elementRect);

        // Collect visible text only for on-screen widgets to keep TEXT output
        // focused on what the user can currently see.
        if (isOnScreen) {
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
        }

        // Collect interactive widgets regardless of viewport position so that
        // off-screen children of eagerly-built scrollable collections
        // (GridView.count, ListView with explicit children, etc.) are included.
        // Off-screen items can be addressed via --key if they have a ValueKey
        // assigned; items without a key can only be reached by scrolling them
        // into view first.
        // Lazy-built sliver children (GridView.builder, ListView.builder) that
        // haven't scrolled into view won't exist in the element tree at all
        // and therefore cannot appear here — use fdb scroll-to to reveal them
        // before describing.
        if (_isDescribeInteractiveWidget(typeName)) {
          // GestureDetector / InkWell with no active callbacks are just
          // decoration wrappers — skip them but continue the walk into their
          // children so that nested interactive widgets are found.
          if (_isGestureTransparent(typeName) && !_hasActiveCallbacks(widget, typeName)) {
            element.visitChildren(visit);
            if (typeName == 'Tooltip') currentTooltip = previousTooltip;
            return;
          }

          // For on-screen widgets, require a successful hit test to confirm
          // the widget is actually reachable. For off-screen widgets the hit
          // test always fails (the point is outside the viewport), so we skip
          // it and include the element unconditionally.
          if (isOnScreen && !isElementHittable(element)) {
            if (typeName == 'Tooltip') currentTooltip = previousTooltip;
            // Still recurse: an unhittable ancestor may have hittable children
            // (e.g. Opacity(opacity:0) around individual buttons).
            element.visitChildren(visit);
            return;
          }

          final key = widget.key is ValueKey<String> ? (widget.key as ValueKey<String>).value : null;
          final visibleText = _extractDescribeText(element, tooltipHint: currentTooltip);
          final gestures = _extractGestures(widget, typeName);
          interactive.add({
            'type': typeName,
            'key': key,
            'text': visibleText,
            'x': offset.dx + size.width / 2,
            'y': offset.dy + size.height / 2,
            if (gestures != null) 'gestures': gestures,
          });

          // Pure gesture wrappers (GestureDetector, InkWell) — their children
          // may contain additional independent interactive widgets (e.g. buttons
          // inside a toolbar GestureDetector). Continue the walk.
          //
          // ListTile variants — their children include internal InkWell /
          // GestureDetector nodes that are framework implementation, not user-
          // authored targets. Stop the interactive walk (like self-contained
          // widgets) to avoid duplicating the tile as InkWell(tap) entries.
          //
          // Self-contained widgets (ElevatedButton, TextField, etc.) own their
          // entire subtree — descending into them would expose internal
          // framework InkWell/GestureDetector children as noise. Stop here.
          if (_isPureGestureWrapper(typeName)) {
            element.visitChildren(visit);
          } else if (isOnScreen) {
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
          }

          if (typeName == 'Tooltip') currentTooltip = previousTooltip;
          return;
        }
      }

      // Normal element walk: visits all active (in-viewport) children.
      element.visitChildren(visit);

      // For sliver multi-box adaptors (GridView, ListView, CustomScrollView),
      // element.visitChildren only reaches *active* (in-viewport) elements.
      // Items that have never been scrolled into view have no element or render
      // object at all. If the sliver widget exposes a SliverChildListDelegate
      // (GridView.count, ListView with explicit children), we can walk its full
      // widget list and inspect widgets that haven't been built into elements yet.
      // This MUST run after element.visitChildren so that active items are already
      // in the `interactive` list and can be used for deduplication by key.
      final ro = element.renderObject;
      if (ro is RenderSliverMultiBoxAdaptor && interactive.length < maxInteractive) {
        _collectUnbuiltDelegateWidgets(element, interactive, maxInteractive);
      }

      if (typeName == 'Tooltip') currentTooltip = previousTooltip;
    }

    root.visitChildren(visit);

    interactive.removeWhere((entry) {
      final text = entry['text'] as String?;
      final key = entry['key'] as String?;
      final gestures = (entry['gestures'] as List<dynamic>?)?.cast<String>() ?? [];
      final hasText = text != null && text.trim().isNotEmpty && text.runes.any((r) => r < 0xE000 || r > 0xF8FF);
      final hasKey = key != null;
      final hasInterestingGesture = gestures.any((g) => _interestingGestures.contains(g));
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

/// Inspects un-built widget children from a [SliverChildListDelegate].
///
/// [SliverMultiBoxAdaptorElement] only keeps the currently active (in-viewport)
/// children in the element tree. Items that were never scrolled into view have
/// no element or render object. If the sliver widget uses a
/// [SliverChildListDelegate] (GridView.count, ListView with explicit children),
/// we can read the full widget list and widget-level inspect each un-built entry.
void _collectUnbuiltDelegateWidgets(
  Element sliverElement,
  List<Map<String, dynamic>> interactive,
  int maxInteractive,
) {
  List<Widget>? allChildren;
  try {
    // Use a type guard to narrow the cast before accessing delegate.
    if (sliverElement.widget is SliverMultiBoxAdaptorWidget) {
      final delegate = (sliverElement.widget as SliverMultiBoxAdaptorWidget).delegate;
      if (delegate is SliverChildListDelegate) {
        allChildren = delegate.children;
      }
    }
  } catch (_) {
    return;
  }
  if (allChildren == null || allChildren.isEmpty) return;

  // Collect the delegate indices that are already built (active in the element
  // tree). SliverMultiBoxAdaptorElement stores each active child's index as its
  // slot (an int), so visitChildren gives us every built index. We skip those
  // positions to avoid duplicating items regardless of their key type.
  //
  // Safety net: if Flutter ever changes the slot type away from int, visitChildren
  // will still run but builtIndices will stay empty while childCount > 0. In that
  // case we fall back to key-based deduplication so we skip at least items with a
  // ValueKey<String> rather than emitting every item twice.
  final builtIndices = <int>{};
  var activeChildCount = 0;
  sliverElement.visitChildren((child) {
    activeChildCount++;
    final slot = child.slot;
    if (slot is int) builtIndices.add(slot);
  });

  // Determine whether slot-based dedup is trustworthy.
  final useIndexDedup = builtIndices.isNotEmpty || activeChildCount == 0;

  // Key-based fallback set (used only when slot type changed in a new Flutter version).
  final existingKeys = useIndexDedup
      ? const <String?>{}
      : <String?>{
          for (final entry in interactive)
            if (entry['key'] != null) entry['key'] as String,
        };

  for (var i = 0; i < allChildren.length; i++) {
    if (interactive.length >= maxInteractive) return;
    if (useIndexDedup) {
      // Primary path: skip indices that are already built in the element tree.
      if (builtIndices.contains(i)) continue;
    } else {
      // Fallback: slot type changed — deduplicate by ValueKey<String> only.
      final childKey = allChildren[i].key is ValueKey<String> ? (allChildren[i].key as ValueKey<String>).value : null;
      if (childKey != null && existingKeys.contains(childKey)) continue;
    }
    // Widget has not been built into an element yet — inspect at widget level.
    _collectInteractiveFromWidget(allChildren[i], interactive, maxInteractive);
  }
}

/// Recursively inspects a widget subtree (without building elements) to
/// collect interactive widgets. Used for un-built sliver delegate children.
void _collectInteractiveFromWidget(
  Widget widget,
  List<Map<String, dynamic>> interactive,
  int maxInteractive,
) {
  if (interactive.length >= maxInteractive) return;
  final typeName = widget.runtimeType.toString();

  if (_isDescribeInteractiveWidget(typeName)) {
    final key = widget.key is ValueKey<String> ? (widget.key as ValueKey<String>).value : null;
    final text = _extractWidgetLevelText(widget);
    final gestures = _extractGestures(widget, typeName);
    // Apply the same filtering logic as the post-filter in handleDescribe so
    // items that would be discarded later are never added (saves cap space).
    // - Text: must be non-empty AND contain at least one non-private-use-area
    //   codepoint (filters out icon-only text, codepoints 0xE000–0xF8FF).
    // - Gestures: must include at least one gesture from _interestingGestures.
    final hasText = text != null && text.trim().isNotEmpty && text.runes.any((r) => r < 0xE000 || r > 0xF8FF);
    final hasKey = key != null;
    final hasInterestingGesture = gestures != null && gestures.any((g) => _interestingGestures.contains(g));
    if (!hasText && !hasKey && !hasInterestingGesture) return;
    interactive.add({
      'type': typeName,
      'key': key,
      'text': text,
      // Off-screen/un-built: no real layout position available.
      // x/y are placeholders — do NOT use these coordinates to drive fdb tap
      // --at. Use --key (if the item has a ValueKey) to target off-screen items.
      // Callers can distinguish off-screen entries by the 'built': false field.
      'x': 0.0,
      'y': 9999999.0,
      'built': false,
      if (gestures != null) 'gestures': gestures,
    });
    return;
  }

  // Recurse into common single-child and multi-child widget shapes.
  _visitWidgetChildren(widget, interactive, maxInteractive);
}

void _visitWidgetChildren(
  Widget widget,
  List<Map<String, dynamic>> interactive,
  int maxInteractive,
) {
  if (interactive.length >= maxInteractive) return;
  // Single child.
  try {
    final child = (widget as dynamic).child;
    if (child is Widget) {
      _collectInteractiveFromWidget(child, interactive, maxInteractive);
      return;
    }
  } catch (_) {}
  // Multi-child.
  try {
    final children = (widget as dynamic).children;
    if (children is List) {
      for (final c in children) {
        if (interactive.length >= maxInteractive) return;
        if (c is Widget) _collectInteractiveFromWidget(c, interactive, maxInteractive);
      }
    }
  } catch (_) {}
}

/// Extracts text from a widget tree without building elements.
String? _extractWidgetLevelText(Widget widget) {
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is RichText) return widget.text.toPlainText();
  // Single child.
  try {
    final child = (widget as dynamic).child;
    if (child is Widget) {
      final t = _extractWidgetLevelText(child);
      if (t != null) return t;
    }
  } catch (_) {}
  // Multi-child.
  try {
    final children = (widget as dynamic).children;
    if (children is List) {
      for (final c in children) {
        if (c is Widget) {
          final t = _extractWidgetLevelText(c);
          if (t != null) return t;
        }
      }
    }
  } catch (_) {}
  return null;
}

/// Returns true for pure gesture wrappers whose children are user-authored
/// and may contain additional independent interactive widgets.
///
/// Only [GestureDetector] and [InkWell] qualify — they are transparent
/// passthrough wrappers. [ListTile] variants are NOT pure wrappers: their
/// children include internal framework widgets (`InkWell`, `Semantics`, etc.)
/// that would leak as duplicate entries if the walk continued.
bool _isPureGestureWrapper(String typeName) => const {
      'GestureDetector',
      'InkWell',
    }.contains(typeName);

/// Returns true for interactive widgets whose children may contain additional
/// independent interactive targets — the walk must continue into them.
///
/// [GestureDetector] and [InkWell] are pure gesture wrappers — their children
/// are user-authored and may contain buttons, other gesture detectors, etc.
///
/// [ListTile] variants are structural containers whose `leading`, `title`,
/// `subtitle`, and `trailing` slots frequently hold independently tappable
/// widgets (e.g. an [ElevatedButton] in `trailing`). Recording the tile (when
/// it has `onTap`) AND descending into its children lets agents see — and tap —
/// both the tile and the nested interactive widget.
///
/// Self-contained widgets (ElevatedButton, TextField, etc.) are NOT transparent:
/// their children are internal framework widgets that should not be surfaced.
bool _isGestureTransparent(String typeName) => const {
      'CheckboxListTile',
      'GestureDetector',
      'InkWell',
      'ListTile',
      'RadioListTile',
      'SwitchListTile',
    }.contains(typeName);

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

/// Returns true if the gesture-transparent widget has at least one active
/// gesture callback.
///
/// Used to skip gesture-transparent widgets that have no callbacks wired up.
/// An [InkWell] with no `onTap` inside a [ListTile] that has no `onTap`, or
/// a [GestureDetector] used purely for hover effects — these are decoration
/// wrappers, not actionable targets. Surfacing them would add noise.
///
/// For [ListTile] variants, this checks `onTap` and `onLongPress` — the only
/// user-facing callbacks. A tile without these is a display element, not an
/// interactive target (even if it has text and a key).
bool _hasActiveCallbacks(Widget widget, String typeName) {
  try {
    final w = widget as dynamic;
    if (typeName == 'GestureDetector') {
      return w.onTap != null ||
          w.onDoubleTap != null ||
          w.onLongPress != null ||
          w.onVerticalDragStart != null ||
          w.onVerticalDragUpdate != null ||
          w.onVerticalDragEnd != null ||
          w.onHorizontalDragStart != null ||
          w.onHorizontalDragUpdate != null ||
          w.onHorizontalDragEnd != null ||
          w.onPanStart != null ||
          w.onPanUpdate != null ||
          w.onPanEnd != null ||
          w.onScaleStart != null ||
          w.onScaleUpdate != null ||
          w.onScaleEnd != null ||
          w.onForcePressStart != null ||
          w.onForcePressPeak != null;
    }
    if (typeName == 'InkWell') {
      return w.onTap != null || w.onDoubleTap != null || w.onLongPress != null;
    }
    // ListTile variants — check onTap / onLongPress.
    if (typeName == 'ListTile' ||
        typeName == 'CheckboxListTile' ||
        typeName == 'RadioListTile' ||
        typeName == 'SwitchListTile') {
      return w.onTap != null || w.onLongPress != null;
    }
  } catch (_) {
    // Dynamic access failed — assume active to avoid hiding real targets.
    return true;
  }
  return true;
}

String? _extractDescribeText(
  Element element, {
  String? tooltipHint,
}) {
  final widget = element.widget;
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is RichText) return widget.text.toPlainText();
  if (widget is EditableText) return widget.controller.text;

  final fragments = <String>[];

  bool hasVisibleText(String s) => s.trim().isNotEmpty && s.runes.any((r) => r < 0xE000 || r > 0xF8FF);

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
      if (w.onVerticalDragStart != null || w.onVerticalDragUpdate != null || w.onVerticalDragEnd != null) {
        gestures.add('verticalDrag');
      }
      if (w.onHorizontalDragStart != null || w.onHorizontalDragUpdate != null || w.onHorizontalDragEnd != null) {
        gestures.add('horizontalDrag');
      }
      if (w.onPanStart != null || w.onPanUpdate != null || w.onPanEnd != null) {
        gestures.add('pan');
      }
      if (w.onScaleStart != null || w.onScaleUpdate != null || w.onScaleEnd != null) {
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
