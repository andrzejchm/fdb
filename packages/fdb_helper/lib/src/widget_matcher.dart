import 'package:flutter/widgets.dart';

import 'widget_refs.dart';

/// Sealed class hierarchy for matching widgets in the element tree.
sealed class WidgetMatcher {
  /// Optional 0-based index for disambiguation when multiple widgets match.
  final int? index;

  const WidgetMatcher({this.index});

  /// Creates a [WidgetMatcher] from VM service extension params.
  ///
  /// Priority: describe ref → key → text → type → coordinates → throws.
  ///
  /// Throws [ArgumentError] with [staleRefMessage] for a stale `ref`.
  factory WidgetMatcher.fromParams(Map<String, String> params) {
    final index = params['index'] != null ? int.tryParse(params['index']!) : null;

    // `@N` from fdb describe. An fdb_helper without refs rejects the param
    // set ("params must contain ...") instead of matching something else.
    final rawRef = params['ref'];
    if (rawRef != null) {
      final ref = int.tryParse(rawRef);
      if (ref == null) throw ArgumentError('ref must be a number, got "$rawRef"');
      final resolved = resolveRef(ref);
      if (resolved == null) throw ArgumentError(staleRefMessage(ref));
      return RefMatcher(ref, element: resolved.element, widget: resolved.widget);
    }

    if (params.containsKey('key')) {
      return KeyMatcher(params['key']!, index: index);
    }
    if (params.containsKey('text')) {
      return TextMatcher(params['text']!, index: index);
    }
    if (params.containsKey('type')) {
      return TypeMatcher(params['type']!, index: index);
    }
    if (params.containsKey('x') && params.containsKey('y')) {
      final x = double.tryParse(params['x']!);
      final y = double.tryParse(params['y']!);
      if (x == null || y == null) {
        throw ArgumentError('x and y must be valid numbers');
      }
      return CoordinatesMatcher(x: x, y: y, index: index);
    }
    if (params.containsKey('focused')) {
      return FocusedMatcher(index: index);
    }
    throw ArgumentError(
      'params must contain at least one of: key, text, type, or both x and y',
    );
  }

  /// Returns true if [element] matches this matcher.
  bool matches(Element element, {String? Function(Widget)? extractText});
}

/// Matches a widget whose key is a [ValueKey<String>] with the given value.
class KeyMatcher extends WidgetMatcher {
  final String keyValue;

  const KeyMatcher(this.keyValue, {super.index});

  @override
  bool matches(Element element, {String? Function(Widget)? extractText}) {
    final key = element.widget.key;
    return key is ValueKey<String> && key.value == keyValue;
  }
}

/// Matches a widget whose extracted text content equals [text].
class TextMatcher extends WidgetMatcher {
  final String text;

  const TextMatcher(this.text, {super.index});

  @override
  bool matches(Element element, {String? Function(Widget)? extractText}) {
    if (extractText == null) return false;
    final extracted = extractText(element.widget);
    return extracted == text;
  }
}

/// Matches a widget whose [runtimeType.toString()] equals [typeName].
class TypeMatcher extends WidgetMatcher {
  final String typeName;

  const TypeMatcher(this.typeName, {super.index});

  @override
  bool matches(Element element, {String? Function(Widget)? extractText}) {
    return element.widget.runtimeType.toString() == typeName;
  }
}

/// Matches the widget an `fdb describe` ref names (see `widget_refs.dart`):
/// its [element] while mounted, or for a list child that was not built at
/// describe time, the element built from its [widget] instance.
///
/// Goes through the same hittability checks as a selector, so a covered,
/// disabled or scrolled-out widget fails instead of being tapped blindly.
class RefMatcher extends WidgetMatcher {
  final int ref;
  final Element? element;
  final Widget? widget;

  const RefMatcher(this.ref, {this.element, this.widget});

  @override
  bool matches(Element element, {String? Function(Widget)? extractText}) {
    final target = this.element;
    return target != null ? identical(element, target) : identical(element.widget, widget);
  }

  /// The error when no hittable element matches.
  String get notFoundMessage => element != null
      ? 'No hittable element found for @$ref'
      : '@$ref is not built on screen. Bring it into view with fdb scroll-to @$ref first';
}

/// Matches the currently focused element (no selector needed).
///
/// Used when `fdb input` is called without any selector — types into whatever
/// field currently holds focus via [FocusManager.instance.primaryFocus].
class FocusedMatcher extends WidgetMatcher {
  const FocusedMatcher({super.index});

  @override
  bool matches(Element element, {String? Function(Widget)? extractText}) =>
      false; // Resolved via FocusManager, not tree traversal.
}

/// Bypasses tree search and taps at the given global coordinates.
class CoordinatesMatcher extends WidgetMatcher {
  final double x;
  final double y;

  const CoordinatesMatcher({required this.x, required this.y, super.index});

  /// Always returns false — coordinates bypass element matching entirely.
  @override
  bool matches(Element element, {String? Function(Widget)? extractText}) => false;

  Offset get offset => Offset(x, y);
}
