import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    final text = extractWidgetText(widget);
    final hasKey = widget.key is ValueKey<String>;

    if (isInteractive || text != null || hasKey) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox && renderObject.hasSize && renderObject.attached) {
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

      // Don't recurse into interactive widgets (except GestureDetector/InkWell/
      // InkResponse) to avoid exposing internal sub-widgets.
      // Widgets that merely have text or a key are NOT pruned — only truly
      // interactive leaf widgets stop the traversal.
      if (isInteractive &&
          widget.runtimeType != GestureDetector &&
          widget.runtimeType != InkWell &&
          widget.runtimeType != InkResponse) {
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
/// [element] is the element a gesture targets: the matched widget, or for a
/// non-interactive match its nearest interactive ancestor. [matched] is the
/// matched widget itself. Both are null if nothing matched or the match is
/// ambiguous. [matchCount] is the number of matches.
///
/// [tapPoint] is a global point inside the matched widget at which a pointer
/// reaches [element]. It is null when no such point exists, for example when
/// the match is covered by a dialog or an overlay; [unreachable] says why.
typedef HittableElementResult = ({
  Element? element,
  Element? matched,
  int matchCount,
  Offset? tapPoint,
  Unreachable? unreachable,
});

/// Why no pointer reaches a matched widget. [message] is the error to report;
/// [scrolledOut] is true when the widget is only scrolled out of a scroll view
/// the user can reach, not covered.
typedef Unreachable = ({String message, bool scrolledOut});

typedef _Match = ({Element matched, Element countedAs, Element? gestureOwner, bool ownsGestures});

/// Finds the first (or Nth, if [matcher] has an index) element matching
/// [matcher] and the point where a gesture on it should land.
///
/// A matched element that is interactive or has an interactive descendant (a
/// custom button) is the target itself. A non-interactive match (`--text
/// "Submit"` on the [Text] inside a button) targets its nearest interactive
/// ancestor. Either way the tap point lies inside the matched widget and must
/// reach the target there: the hit test at that point has to go through the
/// matched widget, or for a non-interactive match through its nearest
/// interactive ancestor before any other one. A widget covered by a dialog or
/// an overlay therefore gets no [HittableElementResult.tapPoint]; it never
/// falls back to tapping an unrelated big ancestor such as the Scaffold.
///
/// When [matcher.index] is null and more than one element matches,
/// [HittableElementResult.element] is null and `matchCount` reflects the
/// ambiguity.
HittableElementResult findHittableElement(WidgetMatcher matcher) {
  const none = (element: null, matched: null, matchCount: 0, tapPoint: null, unreachable: null);
  // Only Text, Key and Type matchers match elements in the tree.
  if (matcher is CoordinatesMatcher || matcher is FocusedMatcher) return none;

  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return none;

  final matches = <_Match>[];
  // Track counted render objects to avoid duplicates (e.g. Text and its child
  // RichText resolve to the same render object but are different elements).
  final seen = <RenderObject>{};
  final interactiveRenderObjects = <RenderObject>{};

  // Mutable ancestor stack: push before recursing, pop after (O(depth) memory).
  final ancestors = <Element>[];

  void visit(Element element) {
    final isInteractive = _isInteractiveWidget(element.widget.runtimeType);
    final elementRenderObject = isInteractive ? element.renderObject : null;
    if (elementRenderObject != null) interactiveRenderObjects.add(elementRenderObject);

    if (matcher.matches(element, extractText: extractWidgetText)) {
      // An interactive widget, or a custom one that owns its gesture handling
      // (e.g. a design-system button that builds its own GestureDetector).
      // Climbing past it would land on an unrelated outer detector, such as a
      // screen-level keyboard dismisser.
      final ownsGestures = isInteractive || _hasInteractiveDescendant(element);
      final countedAs = _countedAs(element, ownsGestures: ownsGestures, ancestors: ancestors);
      final countedRenderObject = countedAs?.renderObject;
      if (countedAs != null && countedRenderObject != null && seen.add(countedRenderObject)) {
        matches.add((
          matched: element,
          countedAs: countedAs,
          gestureOwner: ownsGestures
              ? element
              : ancestors.reversed.where((a) => _isInteractiveWidget(a.widget.runtimeType)).firstOrNull,
          ownsGestures: ownsGestures,
        ));
      }
    }

    ancestors.add(element);
    element.visitChildren(visit);
    ancestors.removeLast();
  }

  root.visitChildren(visit);

  // Stable-partition: user widgets first, framework widgets after.
  // List.sort is not guaranteed stable in Dart, so we split and rejoin.
  final userMatches = matches.where((m) => !_isFrameworkWidget(m.countedAs)).toList();
  final frameworkMatches = matches.where((m) => _isFrameworkWidget(m.countedAs)).toList();
  matches
    ..clear()
    ..addAll(userMatches)
    ..addAll(frameworkMatches);

  if (matches.isEmpty) return none;

  // Ambiguous: multiple matches and no index specified — caller must disambiguate.
  final targetIndex = matcher.index ?? 0;
  if ((matcher.index == null && matches.length > 1) || targetIndex >= matches.length) {
    return (element: null, matched: null, matchCount: matches.length, tapPoint: null, unreachable: null);
  }

  final match = matches[targetIndex];
  final tapPoint = _findTapPoint(match, interactiveRenderObjects);
  return (
    element: match.gestureOwner ?? match.matched,
    matched: match.matched,
    matchCount: matches.length,
    tapPoint: tapPoint,
    unreachable: tapPoint == null ? _describeUnreachable(match.matched) : null,
  );
}

/// The element and point at which a selector gesture (tap, long-press,
/// double-tap, swipe) starts, or the error to report when there is none.
///
/// With [allowScrolledOut], a match that is only scrolled out of view is
/// returned with its centre, for gestures that can invoke the callback
/// directly instead of hit-testing.
({({Element element, Offset point})? target, String? error}) findGestureTarget(
  WidgetMatcher matcher, {
  bool allowScrolledOut = false,
}) {
  final (:element, :matchCount, :tapPoint, :unreachable, matched: _) = findHittableElement(matcher);
  if (element == null) {
    final error = matchCount > 1
        ? 'Found $matchCount elements matching the selector. Use --index to specify which one (0-based).'
        : 'No hittable element found for matcher';
    return (target: null, error: error);
  }
  if (tapPoint != null) return (target: (element: element, point: tapPoint), error: null);
  final box = element.renderObject;
  if (allowScrolledOut && unreachable!.scrolledOut && box is RenderBox) {
    return (target: (element: element, point: box.localToGlobal(box.size.center(Offset.zero))), error: null);
  }
  return (target: null, error: unreachable!.message);
}

/// The element a match is counted and de-duplicated by. Unchanged from the
/// time this also picked the tap target, so match counts, `--index` and
/// `fdb wait` keep their behaviour. Never used as the tap target: tapping a
/// hittable ancestor here (a Scaffold, the Overlay) sent stray taps to the
/// screen centre when the match was covered.
Element? _countedAs(Element element, {required bool ownsGestures, required List<Element> ancestors}) {
  final matchedHittable = isElementHittable(element);
  if (ownsGestures && (matchedHittable || _isScrolledOutOfReachableView(element))) return element;

  Element? fallbackHittable;
  for (var i = ancestors.length - 1; i >= 0; i--) {
    if (!isElementHittable(ancestors[i])) continue;
    final ancestorType = ancestors[i].widget.runtimeType;
    if (_isInteractiveWidget(ancestorType)) return ancestors[i];
    if (fallbackHittable == null && !ancestorType.toString().startsWith('_') && !_isPassThroughWidget(ancestorType)) {
      fallbackHittable = ancestors[i];
    }
  }
  return matchedHittable ? element : fallbackHittable;
}

/// A point inside the matched widget where a pointer reaches the gesture
/// target of [match], or null.
///
/// A widget that owns its gestures (or has no interactive ancestor) must be
/// on the hit-test path itself. A non-interactive match must have its nearest
/// interactive ancestor as the first interactive widget on the path: that
/// accepts a Text inside a button, and rejects an opaque detector on top that
/// sits inside the same screen-level detector.
Offset? _findTapPoint(_Match match, Set<RenderObject> interactiveRenderObjects) {
  final box = match.matched.renderObject;
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  final owner = match.gestureOwner;
  for (final point in tapCandidatePoints(box)) {
    final path = hitTestAt(point).path;
    final reaches = match.ownsGestures || owner == null
        ? path.any((entry) => entry.target == box)
        : path.map((entry) => entry.target).where(interactiveRenderObjects.contains).firstOrNull == owner.renderObject;
    if (reaches) return point;
  }
  return null;
}

/// Why no pointer reaches [matched]: scrolled out of view, blocked by an
/// ignoring ancestor, or covered by another widget.
Unreachable _describeUnreachable(Element matched) {
  final type = matched.widget.runtimeType;
  Unreachable notHittable(String why, {String fix = 'Dismiss what covers it'}) =>
      (message: '$type is not hittable: $why. $fix or use --index/another selector', scrolledOut: false);

  final box = matched.renderObject;
  if (box is! RenderBox || !box.hasSize || !box.attached) {
    return notHittable('it has no laid-out box on screen', fix: 'Pick another widget');
  }

  if (visibleGlobalRect(box).isEmpty) {
    if (_isScrolledOutOfReachableView(matched)) {
      return (message: '$type is scrolled out of view. Bring it into view first with fdb scroll-to', scrolledOut: true);
    }
    return notHittable('it is outside the visible screen area', fix: 'Bring it on screen');
  }

  final point = visibleGlobalRect(box).center;
  final at = '${point.dx.toStringAsFixed(1)},${point.dy.toStringAsFixed(1)}';
  final blocker = _pointerBlocker(box);
  if (blocker != null) {
    return notHittable('it is inside $blocker, which blocks pointer events at $at', fix: 'Wait until it accepts taps');
  }
  final cover = _coveringWidget(hitTestAt(point).path, matched);
  if (cover == null) return notHittable('a tap at $at does not reach it');
  return notHittable('it is covered by $cover at $at');
}

/// The nearest render ancestor (or [box] itself) that drops pointer events
/// for its subtree: an ignoring [IgnorePointer], an absorbing [AbsorbPointer]
/// or an [Offstage] (which [Visibility] also uses).
String? _pointerBlocker(RenderBox box) {
  for (RenderObject? node = box; node != null; node = node.parent) {
    final blocks = (node is RenderIgnorePointer && node.ignoring) ||
        (node is RenderAbsorbPointer && node.absorbing) ||
        (node is RenderOffstage && node.offstage);
    if (blocks) return _creatorElement(node)?.widget.runtimeType.toString() ?? node.runtimeType.toString();
  }
  return null;
}

/// Names the widget on top of [matched] from the hit-test [path] at its centre.
///
/// Walks up from the deepest hit widget to just below the first ancestor it
/// shares with [matched]. Prefers a well-known covering widget (a barrier,
/// dialog, sheet or another screen), then the topmost user-level widget of
/// the covering subtree. Null when the deepest hit is an ancestor of [matched],
/// i.e. the tap falls through an empty part of it rather than being covered.
String? _coveringWidget(Iterable<HitTestEntry> path, Element matched) {
  final deepest = path.map((entry) => entry.target).whereType<RenderObject>().map(_creatorElement).nonNulls.firstOrNull;
  if (deepest == null) return null;

  final matchedAncestors = <Element>{matched};
  matched.visitAncestorElements((ancestor) => matchedAncestors.add(ancestor));
  if (matchedAncestors.contains(deepest)) return null;

  final coveringChain = [deepest];
  deepest.visitAncestorElements((ancestor) {
    if (matchedAncestors.contains(ancestor)) return false;
    coveringChain.add(ancestor);
    return true;
  });

  final known = coveringChain.where((e) => _coveringWidgetTypes.contains(e.widget.runtimeType)).firstOrNull;
  final topmost = coveringChain.reversed.where(_isUserLevelWidget).firstOrNull;
  return (known ?? topmost ?? deepest).widget.runtimeType.toString();
}

Element? _creatorElement(RenderObject renderObject) {
  final creator = renderObject.debugCreator;
  return creator is DebugCreator ? creator.element : null;
}

/// Widgets that typically cover the rest of the screen.
const _coveringWidgetTypes = {
  ModalBarrier,
  Dialog,
  AlertDialog,
  SimpleDialog,
  BottomSheet,
  Drawer,
  SnackBar,
  MaterialBanner,
  Scaffold,
  CupertinoAlertDialog,
  CupertinoActionSheet,
  CupertinoPopupSurface,
  CupertinoPageScaffold,
};

/// A public composite widget, the kind an app defines (a `LoadingOverlay`, a
/// `GestureDetector`), not layout, inherited or route plumbing.
bool _isUserLevelWidget(Element element) {
  final widget = element.widget;
  if (widget is ProxyWidget || widget is RenderObjectWidget) return false;
  if (widget is TickerMode || widget is PageStorage) return false;
  return !_isFrameworkWidget(element);
}

/// True when [element] sits in a [Scrollable] that is itself hittable: it is
/// only scrolled out of view, not covered by another route or a dialog.
bool _isScrolledOutOfReachableView(Element element) {
  var reachable = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Scrollable) reachable = isElementHittable(ancestor);
    return !reachable;
  });
  return reachable;
}

/// True for widgets fdb treats as tap targets (buttons, fields, detectors).
bool isInteractiveElement(Element element) => _isInteractiveWidget(element.widget.runtimeType);

bool _hasInteractiveDescendant(Element element) {
  var found = false;
  void visit(Element child) {
    if (found) return;
    if (_isInteractiveWidget(child.widget.runtimeType)) {
      found = true;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}

/// Returns true if [element] is a framework-internal widget that should not be
/// used as a tap target (e.g. Overlay, Navigator, ModalBarrier).
///
/// Private types (starting with `_`) are always considered framework widgets.
/// A curated set of known public framework container types is also excluded.
bool _isFrameworkWidget(Element element) {
  final typeName = element.widget.runtimeType.toString();
  if (typeName.startsWith('_')) return true;
  const frameworkTypes = {
    'Overlay',
    'Navigator',
    'IndexedStack',
    'Offstage',
    'ModalBarrier',
    'FocusScope',
    'FocusTrap',
    'Semantics',
    'Actions',
    'Shortcuts',
    'DefaultTextEditingShortcuts',
    'PrimaryScrollController',
    'ScrollConfiguration',
    'IgnorePointer',
    'AbsorbPointer',
  };
  return frameworkTypes.contains(typeName);
}

/// Returns true for pointer-routing wrappers that should never be a tap target.
/// These widgets exist to control pointer event propagation, not for user
/// interaction. Skipping them as fallback hittable prevents `fdb tap` from
/// reporting them as the tapped widget when a real interactive ancestor exists.
bool _isPassThroughWidget(Type type) => type == IgnorePointer || type == AbsorbPointer;

/// Closed-list of widget types that are user-meaningful tap targets.
///
/// Why a closed list instead of probing semantics: Flutter buttons build
/// internal `Semantics(button: true, ...)` and `RawGestureDetector` wrappers
/// that themselves declare interactive semantics. A tree walk that picks the
/// nearest semantically-interactive ancestor lands on those internal wrappers
/// (e.g. `Semantics`, `RawGestureDetector`) instead of the user-named widget
/// (`ElevatedButton`, `CupertinoButton`). The closed list anchors the result
/// on the named widget the user would recognise. Adding a new Flutter widget
/// here is a one-line change; the cost is acceptable in exchange for stable,
/// human-readable `TAPPED=...` tokens.
bool _isInteractiveWidget(Type type) =>
    // Material — buttons & chips
    type == ElevatedButton ||
    type == FilledButton ||
    type == OutlinedButton ||
    type == TextButton ||
    type == IconButton ||
    type == FloatingActionButton ||
    type == BackButton ||
    type == CloseButton ||
    type == DropdownButton ||
    type == DropdownMenu ||
    type == PopupMenuButton ||
    type == MenuItemButton ||
    type == SubmenuButton ||
    type == SegmentedButton ||
    type == ActionChip ||
    type == InputChip ||
    type == FilterChip ||
    type == ChoiceChip ||
    type == RawChip ||
    type == Chip ||
    // Material — selection
    type == Checkbox ||
    type == CheckboxListTile ||
    type == Radio ||
    type == RadioListTile ||
    type == Switch ||
    type == SwitchListTile ||
    type == Slider ||
    type == RangeSlider ||
    type == ToggleButtons ||
    // Material — input
    type == TextField ||
    type == TextFormField ||
    // Material — list/tile
    type == ListTile ||
    type == ExpansionTile ||
    type == Tab ||
    // Material — feedback / generic gesture
    type == GestureDetector ||
    type == InkWell ||
    type == InkResponse ||
    // Material — navigation
    type == NavigationBar ||
    type == NavigationDestination ||
    type == BottomNavigationBar ||
    type == NavigationRail ||
    type == NavigationRailDestination ||
    // Cupertino — buttons
    type == CupertinoButton ||
    type == CupertinoDialogAction ||
    type == CupertinoActionSheetAction ||
    type == CupertinoContextMenuAction ||
    type == CupertinoNavigationBarBackButton ||
    // Cupertino — selection
    type == CupertinoCheckbox ||
    type == CupertinoRadio ||
    type == CupertinoSwitch ||
    type == CupertinoSlider ||
    type == CupertinoSegmentedControl ||
    type == CupertinoSlidingSegmentedControl ||
    // Cupertino — input
    type == CupertinoTextField ||
    type == CupertinoTextFormFieldRow ||
    type == CupertinoSearchTextField ||
    // Cupertino — list/tile/picker
    type == CupertinoListTile ||
    type == CupertinoExpansionTile ||
    type == CupertinoPicker ||
    type == CupertinoDatePicker ||
    type == CupertinoTimerPicker;

/// Finds the first (or Nth, if [matcher] has an index) element that directly
/// matches [matcher], without walking up to a hittable ancestor.
///
/// Unlike [findHittableElement], this returns the raw matched element — e.g.
/// the [Text] widget itself when using [TextMatcher]. This is the correct
/// element to pass to [Scrollable.ensureVisible], which needs the actual
/// target element to compute its scroll offset, not an ancestor container.
///
/// An element is only included in results if it has a valid, sized, attached
/// [RenderBox]. If a matched element has no valid [RenderBox], it is silently
/// excluded from results (and its children are not recursed into either).
///
/// Note: when [matcher] is a [FocusedMatcher] or [CoordinatesMatcher], this
/// function always returns `null`. [FocusedMatcher.matches] always returns
/// `false`, and [CoordinatesMatcher] is not meaningful for tree traversal.
///
/// Returns null if no match is found.
Element? findScrollTargetElement(WidgetMatcher matcher) {
  if (matcher is CoordinatesMatcher) return null;
  // FocusedMatcher.matches() always returns false — skip the tree walk.
  if (matcher is FocusedMatcher) return null;

  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  final matches = <Element>[];

  void visit(Element element) {
    if (matcher.matches(element, extractText: extractWidgetText)) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox && renderObject.hasSize && renderObject.attached) {
        matches.add(element);
      }
      // Do not recurse into children of any matched element — we want the
      // most specific (deepest) match, and ensureVisible needs the actual
      // target element, not an ancestor that also happens to match.
      // This applies even when the matched element has no valid RenderBox.
      return;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);

  if (matches.isEmpty) return null;
  final targetIndex = matcher.index ?? 0;
  if (targetIndex >= matches.length) return null;
  return matches[targetIndex];
}

/// Extracts the plain-text content from a widget, or null if the widget
/// carries no text. Used as the [extractText] callback for [WidgetMatcher.matches].
String? extractWidgetText(Widget widget) {
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  if (widget is RichText) return widget.text.toPlainText();
  if (widget is EditableText) return widget.controller.text;
  return null;
}
