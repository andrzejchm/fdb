import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'element_tree_finder.dart';
import 'gesture_dispatcher.dart';
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
/// This registers four VM service extensions (in debug and profile mode only):
/// - `ext.fdb.elements` — list all interactive elements with bounds
/// - `ext.fdb.tap` — tap a widget by key, text, type, or coordinates
/// - `ext.fdb.enterText` — enter text into a text field
/// - `ext.fdb.scroll` — perform a swipe/scroll gesture
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
    _registerExtension('ext.fdb.tap', _handleTap);
    _registerExtension('ext.fdb.enterText', _handleEnterText);
    _registerExtension('ext.fdb.scroll', _handleScroll);
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

  Future<developer.ServiceExtensionResponse> _handleTap(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final matcher = WidgetMatcher.fromParams(params);

      if (matcher is CoordinatesMatcher) {
        await dispatchTap(matcher.offset);
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
      await dispatchTap(globalCenter);

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

  developer.ServiceExtensionResponse _errorResponse(String message) {
    return developer.ServiceExtensionResponse.error(
      -32000,
      jsonEncode({'error': message}),
    );
  }
}
