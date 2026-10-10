/// Parsing and matching for Android `uiautomator dump` output, used by
/// `fdb native-tap --text` on Android.
///
/// Pure functions only: no process calls, so it is unit-testable without a
/// device.
library;

/// One `<node>` from a uiautomator window dump.
class AndroidUiNode {
  AndroidUiNode({
    required this.text,
    required this.contentDesc,
    required this.resourceId,
    required this.className,
    required this.clickable,
    required this.bounds,
    required this.parent,
  });

  /// `text`, trimmed.
  final String text;

  /// `content-desc`, trimmed.
  final String contentDesc;

  /// `resource-id`, e.g. `com.android.permissioncontroller:id/permission_allow_button`.
  final String resourceId;

  /// `class`, e.g. `android.widget.Button`.
  final String className;

  final bool clickable;

  /// Bounds in physical pixels, or null when the attribute is missing or malformed.
  final AndroidBounds? bounds;

  final AndroidUiNode? parent;

  /// The label a person would read: [text], else [contentDesc].
  String get label => text.isNotEmpty ? text : contentDesc;
}

/// A `[left,top][right,bottom]` rectangle in physical pixels.
class AndroidBounds {
  const AndroidBounds(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  bool get isEmpty => right <= left || bottom <= top;

  int get centerX => (left + right) ~/ 2;

  int get centerY => (top + bottom) ~/ 2;

  @override
  bool operator ==(Object other) =>
      other is AndroidBounds &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => '[$left,$top][$right,$bottom]';
}

/// Outcome of [parseAndroidUiDump].
sealed class AndroidUiDumpParse {
  const AndroidUiDumpParse();
}

/// The dump held a complete `<hierarchy>`; [nodes] are in document order.
class AndroidUiDumpParsed extends AndroidUiDumpParse {
  const AndroidUiDumpParsed(this.nodes);
  final List<AndroidUiNode> nodes;
}

/// The dump is unusable. [reason] says why, e.g. the `ERROR: could not get
/// idle state.` line uiautomator prints (with exit code 0) while the screen
/// is animating.
class AndroidUiDumpInvalid extends AndroidUiDumpParse {
  const AndroidUiDumpInvalid(this.reason);
  final String reason;
}

/// Parses raw `uiautomator dump` output.
///
/// Tolerates text around the XML (the trailing `UI hierchary dumped to: ...`
/// line, warnings before it). Requires a `<hierarchy` root and its closing
/// tag, so an error line or a truncated dump is never mistaken for an empty
/// screen.
AndroidUiDumpParse parseAndroidUiDump(String raw) {
  final start = raw.indexOf('<hierarchy');
  final end = raw.lastIndexOf('</hierarchy>');
  if (start < 0 || end < start) {
    // A self-closing root means an empty window; still a valid dump.
    final selfClosing = RegExp(r'<hierarchy\b[^>]*/>').firstMatch(raw);
    if (selfClosing != null) return const AndroidUiDumpParsed([]);
    return AndroidUiDumpInvalid(_invalidReason(raw, start: start));
  }

  final xml = raw.substring(start, end);
  final nodes = <AndroidUiNode>[];
  final stack = <AndroidUiNode?>[];
  var i = 0;
  while (i < xml.length) {
    final lt = xml.indexOf('<', i);
    if (lt < 0) break;
    if (xml.startsWith('</node', lt)) {
      if (stack.isNotEmpty) stack.removeLast();
      final gt = xml.indexOf('>', lt);
      i = gt < 0 ? xml.length : gt + 1;
      continue;
    }
    if (!xml.startsWith('<node', lt) || !_isNameEnd(xml, lt + 5)) {
      i = lt + 1;
      continue;
    }
    final tag = _readTag(xml, lt + 5);
    final attrs = tag.attributes;
    final node = AndroidUiNode(
      text: (attrs['text'] ?? '').trim(),
      contentDesc: (attrs['content-desc'] ?? '').trim(),
      resourceId: (attrs['resource-id'] ?? '').trim(),
      className: attrs['class'] ?? '',
      clickable: attrs['clickable'] == 'true',
      bounds: parseAndroidBounds(attrs['bounds']),
      parent: stack.isEmpty ? null : stack.last,
    );
    nodes.add(node);
    if (!tag.selfClosing) stack.add(node);
    i = tag.end;
  }
  return AndroidUiDumpParsed(nodes);
}

String _invalidReason(String raw, {required int start}) {
  final error = RegExp(r'^.*ERROR:.*$', multiLine: true).firstMatch(raw)?.group(0)?.trim();
  if (error != null) return error;
  if (start >= 0) return 'truncated window dump (no closing </hierarchy>)';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'empty window dump';
  final firstLine = trimmed.split('\n').first.trim();
  return 'no <hierarchy> in window dump: $firstLine';
}

bool _isNameEnd(String s, int i) => i >= s.length || ' \t\r\n/>'.contains(s[i]);

/// Parses `[l,t][r,b]`. Returns null for anything else.
AndroidBounds? parseAndroidBounds(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$').firstMatch(raw.trim());
  if (m == null) return null;
  return AndroidBounds(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
  );
}

/// Reads attributes from just after a tag name to the closing `>`, honouring
/// quotes so a `>` inside a value doesn't end the tag.
({Map<String, String> attributes, bool selfClosing, int end}) _readTag(String s, int from) {
  final attributes = <String, String>{};
  var i = from;
  while (i < s.length) {
    final c = s[i];
    if (c == '>') {
      return (attributes: attributes, selfClosing: false, end: i + 1);
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '>') {
      return (attributes: attributes, selfClosing: true, end: i + 2);
    }
    if (' \t\r\n'.contains(c)) {
      i++;
      continue;
    }
    final eq = s.indexOf('=', i);
    if (eq < 0) break;
    final name = s.substring(i, eq).trim();
    var q = eq + 1;
    while (q < s.length && ' \t\r\n'.contains(s[q])) {
      q++;
    }
    if (q >= s.length) break;
    final quote = s[q];
    if (quote != '"' && quote != "'") {
      // Unquoted value: not valid XML, read up to whitespace or tag end.
      var e = q;
      while (e < s.length && !' \t\r\n/>'.contains(s[e])) {
        e++;
      }
      attributes[name] = decodeXmlEntities(s.substring(q, e));
      i = e;
      continue;
    }
    final close = s.indexOf(quote, q + 1);
    if (close < 0) break;
    attributes[name] = decodeXmlEntities(s.substring(q + 1, close));
    i = close + 1;
  }
  return (attributes: attributes, selfClosing: false, end: s.length);
}

/// Decodes the XML entities uiautomator writes: `&amp;` `&lt;` `&gt;`
/// `&quot;` `&apos;` and numeric references like `&#10;` / `&#x1F600;`.
/// Unknown entities are left as they are.
String decodeXmlEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    if (code == null || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  });
}

/// A node that matched a label, and the node fdb taps for it.
class AndroidUiMatch {
  const AndroidUiMatch({required this.node, required this.target, required this.bounds});

  /// The node whose text, content-desc or resource-id matched.
  final AndroidUiNode node;

  /// The node to tap: [node] when clickable, else its nearest clickable
  /// ancestor, else [node] itself.
  final AndroidUiNode target;

  /// [target]'s bounds; their center is the tap point.
  final AndroidBounds bounds;

  /// What to report as the matched label.
  String get label => node.label.isNotEmpty ? node.label : node.resourceId;
}

/// Finds the nodes matching [query], in document order, in the first tier
/// that has any match:
///
/// 1. `text` or `content-desc` equal to [query] (both trimmed).
/// 2. The same, ignoring case.
/// 3. `resource-id` equal to [query], either the full `package:id/name` or
///    the bare `name`.
///
/// Nodes without on-screen bounds are skipped. Matches that resolve to the
/// same tap target (a clickable row and the label inside it) count once.
List<AndroidUiMatch> findAndroidUiMatches(List<AndroidUiNode> nodes, String query) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final lower = q.toLowerCase();

  final tiers = <bool Function(AndroidUiNode)>[
    (n) => n.text == q || n.contentDesc == q,
    (n) => n.text.toLowerCase() == lower || n.contentDesc.toLowerCase() == lower,
    (n) => n.resourceId.isNotEmpty && (n.resourceId == q || n.resourceId.split(':id/').last == q),
  ];

  for (final matches in tiers) {
    final result = <AndroidUiMatch>[];
    final seenTargets = <AndroidUiNode>{};
    for (final node in nodes) {
      if (!matches(node)) continue;
      final target = _tapTarget(node);
      final bounds = target.bounds;
      if (bounds == null || bounds.isEmpty) continue;
      if (!seenTargets.add(target)) continue;
      result.add(AndroidUiMatch(node: node, target: target, bounds: bounds));
    }
    if (result.isNotEmpty) return result;
  }
  return const [];
}

/// Outcome of [pickAndroidUiMatch].
sealed class AndroidUiPick {
  const AndroidUiPick();
}

class AndroidUiPicked extends AndroidUiPick {
  const AndroidUiPicked(this.match);
  final AndroidUiMatch match;
}

/// Several matches and no index.
class AndroidUiPickAmbiguous extends AndroidUiPick {
  const AndroidUiPickAmbiguous(this.matches);
  final List<AndroidUiMatch> matches;
}

/// Nothing to tap: no matches, or the index is past the last one.
class AndroidUiPickNone extends AndroidUiPick {
  const AndroidUiPickNone();
}

/// Picks the match to tap: the one at [index] (0-based, document order, like
/// `fdb tap --index`), or the only match when [index] is null.
AndroidUiPick pickAndroidUiMatch(List<AndroidUiMatch> matches, {required int? index}) {
  if (matches.isEmpty) return const AndroidUiPickNone();
  if (index != null) {
    return index >= 0 && index < matches.length ? AndroidUiPicked(matches[index]) : const AndroidUiPickNone();
  }
  if (matches.length == 1) return AndroidUiPicked(matches.single);
  return AndroidUiPickAmbiguous(matches);
}

AndroidUiNode _tapTarget(AndroidUiNode node) {
  for (AndroidUiNode? n = node; n != null; n = n.parent) {
    if (n.clickable && n.bounds != null && !n.bounds!.isEmpty) return n;
  }
  return node;
}

/// Distinct non-empty labels (text, else content-desc) of nodes with on-screen
/// bounds, in document order. Used to tell the caller what was on screen when
/// nothing matched.
List<String> androidVisibleLabels(List<AndroidUiNode> nodes) {
  final seen = <String>{};
  final labels = <String>[];
  for (final node in nodes) {
    final bounds = node.bounds;
    if (bounds == null || bounds.isEmpty) continue;
    for (final label in [node.text, node.contentDesc]) {
      final oneLine = label.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (oneLine.isNotEmpty && seen.add(oneLine)) labels.add(oneLine);
    }
  }
  return labels;
}
