/// Parsing and matching for the iOS simulator accessibility tree that the
/// Swift helper's `describe` subcommand prints, used by
/// `fdb native-tap --text` on the iOS simulator.
///
/// Pure functions only: no process calls, so it is unit-testable without a
/// simulator.
library;

import 'dart:convert';

import 'package:fdb/core/commands/native_tap/native_text_match.dart';

/// A rectangle in points in the current interface orientation.
class IosAxFrame {
  const IosAxFrame({required this.x, required this.y, required this.width, required this.height});

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isEmpty => width <= 0 || height <= 0;

  double get centerX => x + width / 2;

  double get centerY => y + height / 2;
}

/// One accessibility element, in depth-first order.
class IosAxElement {
  const IosAxElement({
    required this.label,
    required this.role,
    required this.identifier,
    required this.value,
    required this.enabled,
    required this.pid,
    required this.depth,
    required this.frame,
  });

  /// `accessibilityLabel`, trimmed. Empty when the element has none.
  final String label;

  /// `accessibilityRole`, e.g. `AXButton`, `AXStaticText`, `AXApplication`.
  final String role;

  /// `accessibilityIdentifier` (a Flutter `Semantics(identifier:)`, a UIKit
  /// `accessibilityIdentifier`), or empty.
  final String identifier;

  /// `accessibilityValue`, or empty.
  final String value;

  final bool enabled;

  /// Process that owns the element: SpringBoard for system alerts.
  final int pid;

  final int depth;

  /// Frame in interface points, or null when the helper could not map it.
  final IosAxFrame? frame;

  bool get isApplication => role == 'AXApplication';
}

/// The tree the helper read.
class IosAxSnapshot {
  const IosAxSnapshot({
    required this.orientation,
    required this.screenWidth,
    required this.screenHeight,
    required this.elements,
  });

  /// `portrait`, `portraitUpsideDown`, `landscapeRight` or `landscapeLeft`.
  final String orientation;

  /// Screen size in points in the current interface orientation.
  final double screenWidth;
  final double screenHeight;

  /// Depth-first; the application element first. Empty while the frontmost
  /// application is not known yet.
  final List<IosAxElement> elements;
}

/// Outcome of [parseIosSimulatorAccessibility].
sealed class IosAxParse {
  const IosAxParse();
}

class IosAxParsed extends IosAxParse {
  const IosAxParsed(this.snapshot);
  final IosAxSnapshot snapshot;
}

class IosAxInvalid extends IosAxParse {
  const IosAxInvalid(this.reason);
  final String reason;
}

/// Parses the JSON the helper's `describe` subcommand prints.
IosAxParse parseIosSimulatorAccessibility(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw.trim());
  } on FormatException catch (e) {
    return IosAxInvalid('the accessibility tree is not valid JSON: ${e.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    return const IosAxInvalid('the accessibility tree is not a JSON object');
  }
  final screen = decoded['screen'];
  final elements = decoded['elements'];
  final width = screen is Map ? _number(screen['width']) : null;
  final height = screen is Map ? _number(screen['height']) : null;
  if (width == null || height == null || elements is! List) {
    return const IosAxInvalid('the accessibility tree has no screen size or element list');
  }
  return IosAxParsed(
    IosAxSnapshot(
      orientation: decoded['orientation'] is String ? decoded['orientation'] as String : '',
      screenWidth: width,
      screenHeight: height,
      elements: [
        for (final e in elements)
          if (e is Map) _element(e),
      ],
    ),
  );
}

IosAxElement _element(Map<dynamic, dynamic> e) {
  String text(String key) => e[key] is String ? (e[key] as String).trim() : '';
  final frame = e['frame'];
  final x = frame is Map ? _number(frame['x']) : null;
  final y = frame is Map ? _number(frame['y']) : null;
  final w = frame is Map ? _number(frame['width']) : null;
  final h = frame is Map ? _number(frame['height']) : null;
  return IosAxElement(
    label: text('label'),
    role: text('role'),
    identifier: text('identifier'),
    value: text('value'),
    enabled: e['enabled'] != false,
    pid: e['pid'] is int ? e['pid'] as int : 0,
    depth: e['depth'] is int ? e['depth'] as int : 0,
    frame: x != null && y != null && w != null && h != null ? IosAxFrame(x: x, y: y, width: w, height: h) : null,
  );
}

double? _number(Object? value) => value is num && value.isFinite ? value.toDouble() : null;

/// An element that matched a label, and where to tap it.
class IosAxMatch {
  const IosAxMatch(this.element);

  final IosAxElement element;

  /// Frame center in interface points: the tap point.
  double get x => element.frame!.centerX;

  double get y => element.frame!.centerY;

  /// What to report as the matched label.
  String get label => element.label.isNotEmpty ? element.label : element.identifier;
}

/// Finds the elements matching [query], in screen-reader order, in the first
/// tier that has any match (the same tiers as Android):
///
/// 1. Label equal to [query] (both trimmed).
/// 2. The same, ignoring case and curly quotes / no-break spaces, so
///    `Open in "Test App"?` matches `Open in “Test App”?`.
/// 3. Accessibility identifier equal to [query].
///
/// Skipped: the application element, disabled elements, and elements with no
/// frame, an empty frame or a center off screen (Flutter reports semantics
/// nodes scrolled out of view with a zero frame). Two matches with the same
/// tap point count once.
List<IosAxMatch> findIosAxMatches(IosAxSnapshot snapshot, String query) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final folded = foldNativeLabel(q);

  final tiers = <bool Function(IosAxElement)>[
    (e) => e.label == q,
    (e) => e.label.isNotEmpty && foldNativeLabel(e.label) == folded,
    (e) => e.identifier == q,
  ];

  for (final matches in tiers) {
    final result = <IosAxMatch>[];
    for (final element in snapshot.elements) {
      if (!element.enabled || !_tappable(snapshot, element) || !matches(element)) continue;
      final match = IosAxMatch(element);
      if (result.any((m) => m.x.round() == match.x.round() && m.y.round() == match.y.round())) continue;
      result.add(match);
    }
    if (result.isNotEmpty) return result;
  }
  return const [];
}

/// Distinct non-empty labels of on-screen elements, in order, each on one
/// line. Tells the caller what was on screen when nothing matched.
List<String> iosAxVisibleLabels(IosAxSnapshot snapshot) {
  final seen = <String>{};
  final labels = <String>[];
  for (final element in snapshot.elements) {
    if (!_tappable(snapshot, element)) continue;
    final label = oneLineLabel(element.label);
    if (label.isNotEmpty && seen.add(label)) labels.add(label);
  }
  return labels;
}

/// Not the application element, with a non-empty frame whose center is on
/// screen.
bool _tappable(IosAxSnapshot snapshot, IosAxElement element) {
  final frame = element.frame;
  if (element.isApplication || frame == null || frame.isEmpty) return false;
  final x = frame.centerX;
  final y = frame.centerY;
  return x >= 0 && y >= 0 && x <= snapshot.screenWidth && y <= snapshot.screenHeight;
}
