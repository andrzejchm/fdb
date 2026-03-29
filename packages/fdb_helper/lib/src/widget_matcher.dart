import 'package:flutter/widgets.dart';

/// Sealed class hierarchy for matching widgets in the element tree.
sealed class WidgetMatcher {
  /// Optional 0-based index for disambiguation when multiple widgets match.
  final int? index;

  const WidgetMatcher({this.index});

  /// Creates a [WidgetMatcher] from VM service extension params.
  ///
  /// Priority: key → text → type → coordinates → throws.
  factory WidgetMatcher.fromParams(Map<String, String> params) {
    final index =
        params['index'] != null ? int.tryParse(params['index']!) : null;

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
  bool matches(Element element, {String? Function(Widget)? extractText}) =>
      false;

  Offset get offset => Offset(x, y);
}
