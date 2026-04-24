import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'element_tree_finder.dart';
import 'gesture_dispatcher.dart';
import 'hit_test_utils.dart';
import 'text_input_simulator.dart';
import 'widget_matcher.dart';

/// A custom binding that registers VM service extensions for widget interaction.
///
/// Usage in `main()`:
/// ```dart
/// void main() {
///   FdbBinding.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
///
/// This registers the following VM service extensions (in debug and profile mode only):
/// - `ext.fdb.elements` — list all interactive elements with bounds
/// - `ext.fdb.tap` — tap a widget by key, text, type, or coordinates
/// - `ext.fdb.longPress` — long-press a widget (same as tap with duration=500ms)
/// - `ext.fdb.enterText` — enter text into a text field
/// - `ext.fdb.scroll` — perform a swipe/scroll gesture
/// - `ext.fdb.back` — trigger Navigator.maybePop()
/// - `ext.fdb.screenshot` — capture the Flutter rendering surface as base64 PNG
class FdbBinding extends WidgetsFlutterBinding {
  FdbBinding._();

  static FdbBinding? _instance;

  /// Returns the singleton [FdbBinding], creating it on first call.
  static FdbBinding ensureInitialized() {
    if (_instance == null) {
      FdbBinding._();
    }
    return _instance!;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    if (kReleaseMode) return;

    _registerExtension('ext.fdb.elements', _handleElements);
    _registerExtension('ext.fdb.describe', _handleDescribe);
    _registerExtension('ext.fdb.tap', _handleTap);
    _registerExtension('ext.fdb.longPress', (method, params) {
      // Long-press is identical to tap but defaults to 500 ms hold duration.
      final paramsWithDuration = {
        ...params,
        if (!params.containsKey('duration')) 'duration': '500',
      };
      return _handleTap(method, paramsWithDuration);
    });
    _registerExtension('ext.fdb.enterText', _handleEnterText);
    _registerExtension('ext.fdb.scroll', _handleScroll);
    _registerExtension('ext.fdb.swipe', _handleSwipe);
    _registerExtension('ext.fdb.back', _handleBack);
    _registerExtension('ext.fdb.clean', _handleClean);
    _registerExtension('ext.fdb.sharedPrefs', _handleSharedPrefs);
    _registerExtension('ext.fdb.screenshot', _handleScreenshot);
  }

  /// Registers a VM service extension, silently ignoring double-registration
  /// that can occur on hot reload.
  void _registerExtension(
    String name,
    Future<developer.ServiceExtensionResponse> Function(
      String method,
      Map<String, String> params,
    ) handler,
  ) {
    try {
      developer.registerExtension(name, handler);
    } on ArgumentError {
      // Already registered — happens on hot reload. Safe to ignore.
    }
  }

  // ---------------------------------------------------------------------------
  // Extension handlers
  // ---------------------------------------------------------------------------

  Future<developer.ServiceExtensionResponse> _handleElements(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final elements = findInteractiveElements();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'status': 'Success', 'elements': elements}),
      );
    } catch (e) {
      return _errorResponse('Failed to list elements: $e');
    }
  }

  Future<developer.ServiceExtensionResponse> _handleDescribe(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) {
        return _errorResponse('No root element available');
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
        // Flutter uses Offstage to hide inactive routes, so this naturally
        // filters background route content from the describe output.
        if (typeName == 'Offstage') {
          try {
            final offstage = (widget as dynamic).offstage as bool;
            if (offstage) return;
          } catch (_) {}
        }

        // Collect route name from ModalRoute — no guard so the deepest
        // (topmost visible) route always wins over shallower ancestors.
        if (element is StatefulElement) {
          final route = ModalRoute.of(element);
          if (route != null) {
            routeName = route.settings.name;
          }
        }

        // Collect Scaffold title as screen name by walking AppBar children
        if (screenName == null && typeName == 'Scaffold') {
          // Walk children to find AppBar → title Text
          void findAppBarTitle(Element el) {
            if (screenName != null) return;
            final w = el.widget;
            final wType = w.runtimeType.toString();
            if (wType == 'AppBar' || wType == 'SliverAppBar') {
              // Walk AppBar children to find the title Text
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

          // Skip zero-size or off-screen widgets
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

          // Collect visible text
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

          // Collect interactive widgets
          if (_isDescribeInteractiveWidget(typeName)) {
            // Skip widgets obscured by a foreground route (e.g. GoRouter shell
            // routes where background pages aren't wrapped in Offstage).
            // If the hit test at this widget's center doesn't reach its render
            // object, a user can't interact with it — omit it and its children.
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

            // Still collect text from children for the TEXT section even
            // though we stop recursing for interactive-widget purposes.
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

            // Don't recurse into interactive widgets to avoid duplicates
            if (typeName == 'Tooltip') currentTooltip = previousTooltip;
            return;
          }
        }

        element.visitChildren(visit);
        if (typeName == 'Tooltip') currentTooltip = previousTooltip;
      }

      root.visitChildren(visit);

      // Remove interactive entries that provide no useful identity signal:
      // no text, no key, and no interesting gestures (drag/pan/longPress/scale).
      // A bare GestureDetector(tap) with no text/key is almost always an icon
      // or structural element that the agent cannot meaningfully reference.
      const _interestingGestures = {
        'horizontalDrag',
        'verticalDrag',
        'pan',
        'longPress',
        'scale',
        'doubleTap',
        'forcePress',
      };
      interactive.removeWhere((entry) {
        final text = entry['text'] as String?;
        final key = entry['key'] as String?;
        final gestures =
            (entry['gestures'] as List<dynamic>?)?.cast<String>() ?? [];
        // Text consisting only of Unicode PUA icon codepoints (U+E000-U+F8FF)
        // is not meaningful — treat it as empty.
        final hasText = text != null &&
            text.trim().isNotEmpty &&
            text.runes.any((r) => r < 0xE000 || r > 0xF8FF);
        final hasKey = key != null;
        final hasInterestingGesture =
            gestures.any((g) => _interestingGestures.contains(g));
        return !hasText && !hasKey && !hasInterestingGesture;
      });

      // Sort interactive elements top-to-bottom, left-to-right
      interactive.sort((a, b) {
        final yA = (a['y'] as double);
        final yB = (b['y'] as double);
        if ((yA - yB).abs() > 10) return yA.compareTo(yB);
        return (a['x'] as double).compareTo(b['x'] as double);
      });

      // Assign sequential refs
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
      return _errorResponse('describe failed: $e');
    }
  }

  /// Returns true for widget types that are interactive and should appear in
  /// the describe output. Extends [_isInteractiveWidget] with additional
  /// tappable container types.
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

  /// Extracts visible text from an interactive element by walking its children.
  ///
  /// Collects ALL text fragments (Text, RichText, EditableText), Tooltip
  /// messages, and Icon semantic labels, joining them with " · ".
  ///
  /// [tooltipHint] is the nearest enclosing Tooltip message discovered while
  /// walking the tree top-down; it is used as a fallback when no other text
  /// is found inside the widget.
  String? _extractDescribeText(
    Element element, {
    String? tooltipHint,
  }) {
    // Check the widget itself first (leaf cases).
    final widget = element.widget;
    if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
    if (widget is RichText) return widget.text.toPlainText();
    if (widget is EditableText) return widget.controller.text;

    // Collect all text fragments from the subtree.
    final fragments = <String>[];

    // Returns true if the string has at least one non-PUA character.
    bool hasVisibleText(String s) =>
        s.trim().isNotEmpty && s.runes.any((r) => r < 0xE000 || r > 0xF8FF);

    void findTextAndIcons(Element el) {
      final w = el.widget;

      if (w is Text) {
        final t = w.data ?? w.textSpan?.toPlainText();
        if (t != null && hasVisibleText(t)) fragments.add(t.trim());
        return; // Don't recurse into Text children
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

      // Extract Tooltip message (inner Tooltip, distinct from the ancestor one).
      if (wType == 'Tooltip') {
        try {
          final message = (w as dynamic).message as String?;
          if (message != null && message.trim().isNotEmpty) {
            fragments.add('[${message.trim()}]');
          }
        } catch (_) {}
      }

      // Extract Icon semantic label.
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

    // Fall back to the ancestor Tooltip hint when the widget has no own text.
    if (fragments.isEmpty && tooltipHint != null) {
      return '[${tooltipHint.trim()}]';
    }

    if (fragments.isEmpty) return null;
    final cleaned = fragments.where((f) => f.trim().isNotEmpty).toList();
    if (cleaned.isEmpty) return null;
    return cleaned.join(' · ');
  }

  /// Extracts the list of registered gestures for a widget.
  ///
  /// For [GestureDetector] and [InkWell], checks which callback properties
  /// are non-null using dynamic access. Returns a short list like
  /// `["tap", "longPress", "horizontalDrag"]` or null if not applicable.
  List<String>? _extractGestures(Widget widget, String typeName) {
    if (typeName != 'GestureDetector' && typeName != 'InkWell') return null;

    final gestures = <String>[];
    try {
      final w = widget as dynamic;
      // Tap gestures
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
        if (w.onPanStart != null ||
            w.onPanUpdate != null ||
            w.onPanEnd != null) {
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

  Future<developer.ServiceExtensionResponse> _handleTap(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final rawDuration = params['duration'];
      final durationMs = rawDuration != null ? int.tryParse(rawDuration) : null;
      if (rawDuration != null && durationMs == null) {
        return _errorResponse('Invalid duration value: $rawDuration');
      }
      final holdDuration = durationMs != null
          ? Duration(milliseconds: durationMs)
          : const Duration(milliseconds: 10);

      final matcher = WidgetMatcher.fromParams(params);

      if (matcher is CoordinatesMatcher) {
        await dispatchTap(matcher.offset, holdDuration: holdDuration);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'status': 'Success', 'x': matcher.x, 'y': matcher.y}),
        );
      }

      final (:element, :matchCount) = findHittableElement(matcher);
      if (element == null) {
        if (matchCount > 1) {
          return _errorResponse(
            'Found $matchCount elements matching the selector. '
            'Use --index to specify which one (0-based).',
          );
        }
        return _errorResponse('No hittable element found for matcher');
      }

      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        return _errorResponse('Element has no RenderBox');
      }

      final center = renderObject.size.center(Offset.zero);
      final globalCenter = renderObject.localToGlobal(center);
      await dispatchTap(globalCenter, holdDuration: holdDuration);

      final widgetType = element.widget.runtimeType.toString();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'widgetType': widgetType,
          'x': globalCenter.dx,
          'y': globalCenter.dy,
        }),
      );
    } on ArgumentError catch (e) {
      return _errorResponse(e.message.toString());
    } catch (e) {
      return _errorResponse('Tap failed: $e');
    }
  }

  Future<developer.ServiceExtensionResponse> _handleEnterText(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final input = params['input'];
      if (input == null) {
        return _errorResponse('Missing required param: input');
      }

      final matcher = WidgetMatcher.fromParams(params);

      if (matcher is FocusedMatcher) {
        // Type into the currently focused element.
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext == null) {
          return _errorResponse('No focused element found');
        }

        // Walk descendants to find the nearest EditableText element.
        // EditableText is a child of TextField, not a parent.
        Element? editableElement;

        void findEditableText(Element el) {
          if (editableElement != null) return;
          if (el.widget is EditableText) {
            editableElement = el;
            return;
          }
          el.visitChildElements(findEditableText);
        }

        if (focusContext is Element) {
          findEditableText(focusContext);
        }

        if (editableElement == null) {
          return _errorResponse(
            'Focused element is not an editable text field',
          );
        }

        await enterText(editableElement!, input);

        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'status': 'Success',
            'input': input,
            'widgetType': editableElement!.widget.runtimeType.toString(),
          }),
        );
      }

      final (:element, :matchCount) = findHittableElement(matcher);
      if (element == null) {
        if (matchCount > 1) {
          return _errorResponse(
            'Found $matchCount elements matching the selector. '
            'Use --index to specify which one (0-based).',
          );
        }
        return _errorResponse('No hittable element found for matcher');
      }

      await enterText(element, input);

      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'input': input,
          'widgetType': element.widget.runtimeType.toString(),
        }),
      );
    } on ArgumentError catch (e) {
      return _errorResponse(e.message.toString());
    } catch (e) {
      return _errorResponse('enterText failed: $e');
    }
  }

  Future<developer.ServiceExtensionResponse> _handleScroll(
    String method,
    Map<String, String> params,
  ) async {
    try {
      // Support two modes:
      // 1. direction + distance (+ optional at=x,y)
      // 2. raw startX/startY/endX/endY

      final direction = params['direction'];

      double startX;
      double startY;
      double endX;
      double endY;

      if (direction != null) {
        final distance = double.tryParse(params['distance'] ?? '') ?? 200.0;

        // Default start: center of screen
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final screenSize = view.physicalSize / view.devicePixelRatio;
        var centerX = screenSize.width / 2;
        var centerY = screenSize.height / 2;

        // Override with --at x,y
        final at = params['at'];
        if (at != null) {
          final parts = at.split(',');
          final atX = parts.length == 2 ? double.tryParse(parts[0]) : null;
          final atY = parts.length == 2 ? double.tryParse(parts[1]) : null;
          if (atX == null || atY == null) {
            return _errorResponse(
              'Invalid --at value: "$at". Expected format: x,y (e.g. 200,400).',
            );
          }
          centerX = atX;
          centerY = atY;
        }

        startX = centerX;
        startY = centerY;

        switch (direction) {
          case 'up':
            // Finger moves down → content scrolls up (reveals content above).
            endX = startX;
            endY = startY + distance;
          case 'down':
            // Finger moves up → content scrolls down (reveals content below).
            endX = startX;
            endY = startY - distance;
          case 'left':
            // Finger moves right → content scrolls left.
            endX = startX + distance;
            endY = startY;
          case 'right':
            // Finger moves left → content scrolls right.
            endX = startX - distance;
            endY = startY;
          default:
            return _errorResponse(
              'Invalid direction: $direction. Use up, down, left, or right.',
            );
        }
      } else {
        // Raw coordinates mode
        final sx = double.tryParse(params['startX'] ?? '');
        final sy = double.tryParse(params['startY'] ?? '');
        final ex = double.tryParse(params['endX'] ?? '');
        final ey = double.tryParse(params['endY'] ?? '');

        if (sx == null || sy == null || ex == null || ey == null) {
          return _errorResponse(
            'Provide direction (up/down/left/right) or '
            'startX, startY, endX, endY',
          );
        }

        startX = sx;
        startY = sy;
        endX = ex;
        endY = ey;
      }

      await dispatchScroll(
        start: Offset(startX, startY),
        end: Offset(endX, endY),
      );

      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'startX': startX,
          'startY': startY,
          'endX': endX,
          'endY': endY,
        }),
      );
    } catch (e) {
      return _errorResponse('Scroll failed: $e');
    }
  }

  Future<developer.ServiceExtensionResponse> _handleSwipe(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final direction = params['direction'];
      if (direction == null) {
        return _errorResponse('Missing required param: direction');
      }

      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final screenSize = view.physicalSize / view.devicePixelRatio;

      double startX;
      double startY;
      double swipeDistance;

      // Check if a widget selector was provided.
      final hasSelector = params.containsKey('key') ||
          params.containsKey('text') ||
          params.containsKey('type');

      if (hasSelector) {
        // Widget-targeted swipe: find the widget's bounds and compute
        // start = widget center, distance = 60% of widget dimension.
        final matcher = WidgetMatcher.fromParams(params);
        final (:element, :matchCount) = findHittableElement(matcher);

        if (element == null) {
          if (matchCount > 1) {
            return _errorResponse(
              'Found $matchCount elements matching the selector. '
              'Use --index to specify which one (0-based).',
            );
          }
          return _errorResponse('No hittable element found for matcher');
        }

        final renderObject = element.renderObject;
        if (renderObject is! RenderBox) {
          return _errorResponse('Element has no RenderBox');
        }

        final center = renderObject.size.center(Offset.zero);
        final globalCenter = renderObject.localToGlobal(center);
        startX = globalCenter.dx;
        startY = globalCenter.dy;

        // Smart default: 60% of widget width for left/right, height for up/down.
        final rawDistance = params['distance'];
        if (rawDistance != null) {
          swipeDistance = double.tryParse(rawDistance) ?? 200.0;
        } else {
          swipeDistance = switch (direction) {
            'left' || 'right' => renderObject.size.width * 0.6,
            'up' || 'down' => renderObject.size.height * 0.6,
            _ => 200.0,
          };
        }
      } else {
        // Fallback: screen center (or --at override) + fixed distance.
        var centerX = screenSize.width / 2;
        var centerY = screenSize.height / 2;

        final at = params['at'];
        if (at != null) {
          final parts = at.split(',');
          final atX = parts.length == 2 ? double.tryParse(parts[0]) : null;
          final atY = parts.length == 2 ? double.tryParse(parts[1]) : null;
          if (atX == null || atY == null) {
            return _errorResponse(
              'Invalid --at value: "$at". Expected format: x,y (e.g. 200,400).',
            );
          }
          centerX = atX;
          centerY = atY;
        }

        startX = centerX;
        startY = centerY;
        swipeDistance = double.tryParse(params['distance'] ?? '') ?? 200.0;
      }

      double endX;
      double endY;

      switch (direction) {
        case 'left':
          // Finger moves left → content/page moves left (next page).
          endX = startX - swipeDistance;
          endY = startY;
        case 'right':
          // Finger moves right → content/page moves right (previous page).
          endX = startX + swipeDistance;
          endY = startY;
        case 'up':
          // Finger moves up → content scrolls up.
          endX = startX;
          endY = startY - swipeDistance;
        case 'down':
          // Finger moves down → content scrolls down.
          endX = startX;
          endY = startY + swipeDistance;
        default:
          return _errorResponse(
            'Invalid direction: $direction. Use up, down, left, or right.',
          );
      }

      await dispatchScroll(
        start: Offset(startX, startY),
        end: Offset(endX, endY),
      );

      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'direction': direction,
          'distance': swipeDistance,
          'startX': startX,
          'startY': startY,
          'endX': endX,
          'endY': endY,
        }),
      );
    } on ArgumentError catch (e) {
      return _errorResponse(e.message.toString());
    } catch (e) {
      return _errorResponse('Swipe failed: $e');
    }
  }

  Future<developer.ServiceExtensionResponse> _handleBack(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final rootElement = WidgetsBinding.instance.rootElement;
      if (rootElement == null) {
        return _errorResponse('No root element available');
      }
      // Walk DOWN the tree to find the first NavigatorState.
      // Navigator.maybeOf(rootElement) walks UP from rootElement, but rootElement
      // is already the top of the tree — there is nothing above it to find.
      NavigatorState? navigator;
      void findNavigator(Element element) {
        if (navigator != null) return;
        if (element is StatefulElement && element.state is NavigatorState) {
          navigator = element.state as NavigatorState;
          return;
        }
        element.visitChildElements(findNavigator);
      }

      rootElement.visitChildElements(findNavigator);
      if (navigator == null) {
        return _errorResponse('No Navigator found');
      }
      final popped = await navigator!.maybePop();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'status': 'Success', 'popped': popped}),
      );
    } catch (e) {
      return _errorResponse('Back failed: $e');
    }
  }

  /// Handles `ext.fdb.sharedPrefs`.
  ///
  /// Params:
  ///   action — `get` | `getAll` | `set` | `remove` | `clear`
  ///   key    — required for get / set / remove
  ///   value  — required for set (always a string; type param determines cast)
  ///   type   — for set: `string` (default) | `bool` | `int` | `double`
  Future<developer.ServiceExtensionResponse> _handleSharedPrefs(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final action = params['action'] ?? '';

      switch (action) {
        case 'getAll':
          final keys = prefs.getKeys();
          final all = <String, dynamic>{};
          for (final key in keys) {
            all[key] = prefs.get(key);
          }
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'status': 'Success', 'values': all}),
          );

        case 'get':
          final key = params['key'];
          if (key == null || key.isEmpty) {
            return _errorResponse('missing key param');
          }
          final value = prefs.get(key);
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'status': 'Success',
              'key': key,
              'value': value,
              'exists': value != null,
            }),
          );

        case 'set':
          final key = params['key'];
          final raw = params['value'];
          final type = params['type'] ?? 'string';
          if (key == null || key.isEmpty) {
            return _errorResponse('missing key param');
          }
          if (raw == null) return _errorResponse('missing value param');
          switch (type) {
            case 'bool':
              await prefs.setBool(key, raw == 'true');
            case 'int':
              final n = int.tryParse(raw);
              if (n == null) return _errorResponse('invalid int: $raw');
              await prefs.setInt(key, n);
            case 'double':
              final d = double.tryParse(raw);
              if (d == null) return _errorResponse('invalid double: $raw');
              await prefs.setDouble(key, d);
            default:
              await prefs.setString(key, raw);
          }
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'status': 'Success', 'key': key, 'value': raw}),
          );

        case 'remove':
          final key = params['key'];
          if (key == null || key.isEmpty) {
            return _errorResponse('missing key param');
          }
          await prefs.remove(key);
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'status': 'Success', 'key': key}),
          );

        case 'clear':
          await prefs.clear();
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'status': 'Success'}),
          );

        default:
          return _errorResponse(
            'unknown action: $action. '
            'Use get | getAll | set | remove | clear',
          );
      }
    } catch (e) {
      return _errorResponse('sharedPrefs failed: $e');
    }
  }

  Future<developer.ServiceExtensionResponse> _handleClean(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final dirs = <Directory>[];

      // Cache dir — getTemporaryDirectory() on iOS/Android
      try {
        dirs.add(await getTemporaryDirectory());
      } catch (_) {}

      // App support dir — persistent but non-user-facing storage
      try {
        dirs.add(await getApplicationSupportDirectory());
      } catch (_) {}

      // App documents dir — user-facing documents
      try {
        dirs.add(await getApplicationDocumentsDirectory());
      } catch (_) {}

      final cleaned = <String>[];
      var totalFiles = 0;

      for (final dir in dirs) {
        if (!dir.existsSync()) continue;
        final entities = dir.listSync(recursive: false);
        for (final entity in entities) {
          try {
            if (entity is File) {
              entity.deleteSync();
              totalFiles++;
            } else if (entity is Directory) {
              entity.deleteSync(recursive: true);
              totalFiles++;
            }
          } catch (_) {}
        }
        cleaned.add(dir.path);
      }

      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'status': 'Success',
          'dirs': cleaned,
          'deletedEntries': totalFiles,
        }),
      );
    } catch (e) {
      return _errorResponse('clean failed: $e');
    }
  }

  /// Handles `ext.fdb.screenshot`.
  ///
  /// Renders the current Flutter surface to a PNG and returns it as a
  /// base64-encoded string under the `screenshot` key.
  ///
  /// Used as a fallback capture backend on platforms that have no native
  /// screenshot CLI (physical iOS, Windows, Linux Wayland).
  Future<developer.ServiceExtensionResponse> _handleScreenshot(
    String method,
    Map<String, String> params,
  ) async {
    ui.Scene? scene;
    ui.Image? image;
    try {
      final renderViews = WidgetsBinding.instance.renderViews;
      if (renderViews.isEmpty) {
        return _errorResponse('No render views available');
      }

      final view = renderViews.first;
      final flutterView = view.flutterView;

      // Ensure the frame is painted before capturing.
      // ignore: invalid_use_of_protected_member
      if (view.debugNeedsPaint || view.layer == null) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }

      // ignore: invalid_use_of_protected_member
      final layer = view.layer;
      if (layer == null) {
        return _errorResponse('Render view layer is null');
      }

      // Capture at physical pixel resolution.
      final size = flutterView.physicalSize;
      final width = size.width.ceil();
      final height = size.height.ceil();

      if (width <= 0 || height <= 0) {
        return _errorResponse('Invalid view size: ${width}x$height');
      }

      final builder = ui.SceneBuilder();
      layer.addToScene(builder);
      scene = builder.build();
      image = await scene.toImage(width, height);

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return _errorResponse('Failed to encode image as PNG');
      }

      final base64Data = base64Encode(byteData.buffer.asUint8List());
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'screenshot': base64Data}),
      );
    } catch (e) {
      return _errorResponse('Screenshot failed: $e');
    } finally {
      scene?.dispose();
      image?.dispose();
    }
  }

  developer.ServiceExtensionResponse _errorResponse(String message) {
    return developer.ServiceExtensionResponse.error(
      -32000,
      jsonEncode({'error': message}),
    );
  }
}
