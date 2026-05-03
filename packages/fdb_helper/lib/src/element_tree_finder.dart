import 'package:flutter/cupertino.dart';
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
/// [element] is the matched element (or null if none found or on error).
/// [matchCount] is the total number of hittable elements that matched.
typedef HittableElementResult = ({Element? element, int matchCount});

/// Finds the first (or Nth, if [matcher] has an index) hittable element
/// matching [matcher].
///
/// For [TextMatcher], [KeyMatcher], and [TypeMatcher], always prefers the
/// nearest interactive ancestor over a non-interactive matched element. This
/// means tapping `--text "Submit"` returns the enclosing button widget, not
/// the [Text] leaf. Pass-through wrappers ([IgnorePointer], [AbsorbPointer])
/// are skipped as fallback targets so route-level wrappers never leak as tap
/// results.
///
/// Returns a record with the matched element and total match count.
/// When [matcher.index] is null and more than one element matches,
/// [element] is null and [matchCount] reflects the ambiguity.
HittableElementResult findHittableElement(WidgetMatcher matcher) {
  if (matcher is CoordinatesMatcher) return (element: null, matchCount: 0);

  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return (element: null, matchCount: 0);

  // For TextMatcher, KeyMatcher, and TypeMatcher we need to track ancestors so
  // we can walk up when the matched element itself is not hittable.
  final needsAncestorWalk = matcher is TextMatcher || matcher is KeyMatcher || matcher is TypeMatcher;

  // Collect resolved hittable elements for each match.
  final matches = <Element>[];
  // Track resolved render objects to avoid duplicates (e.g. Text and its child
  // RichText both resolve to the same render object but are different elements).
  final seen = <RenderObject>{};

  // Mutable ancestor stack: push before recursing, pop after (O(depth) memory).
  final ancestors = <Element>[];

  void visit(Element element) {
    if (matcher.matches(element, extractText: extractWidgetText)) {
      Element? hittable;
      final matchedHittable = isElementHittable(element);
      final matchedInteractive = _isInteractiveWidget(element.widget.runtimeType);

      if (matchedHittable && matchedInteractive) {
        // Matched element is itself an interactive widget — use it directly.
        hittable = element;
      } else if (needsAncestorWalk) {
        // Prefer the nearest interactive ancestor over a non-interactive
        // matched element (handles Text inside ElevatedButton). Fall back to a
        // non-private, non-pass-through hittable ancestor, then to the matched
        // element itself if hittable.
        Element? fallbackHittable;
        for (var i = ancestors.length - 1; i >= 0; i--) {
          if (!isElementHittable(ancestors[i])) continue;
          if (_isInteractiveWidget(ancestors[i].widget.runtimeType)) {
            hittable = ancestors[i];
            break; // best match — stop immediately
          }
          final ancestorType = ancestors[i].widget.runtimeType;
          if (fallbackHittable == null &&
              !ancestorType.toString().startsWith('_') &&
              !_isPassThroughWidget(ancestorType)) {
            fallbackHittable = ancestors[i];
          }
        }
        // No interactive ancestor — fall back to matched element if hittable,
        // otherwise to the best non-pass-through ancestor.
        hittable ??= matchedHittable ? element : null;
        hittable ??= fallbackHittable;
      } else if (matchedHittable) {
        hittable = element;
      }

      if (hittable != null) {
        final renderObject = hittable.renderObject;
        if (renderObject != null && seen.add(renderObject)) {
          matches.add(hittable);
        }
      }
    }

    if (needsAncestorWalk) ancestors.add(element);
    element.visitChildren(visit);
    if (needsAncestorWalk) ancestors.removeLast();
  }

  root.visitChildren(visit);

  // Stable-partition: user widgets first, framework widgets after.
  // List.sort is not guaranteed stable in Dart, so we split and rejoin.
  final userMatches = matches.where((e) => !_isFrameworkWidget(e)).toList();
  final frameworkMatches = matches.where((e) => _isFrameworkWidget(e)).toList();
  matches
    ..clear()
    ..addAll(userMatches)
    ..addAll(frameworkMatches);

  if (matches.isEmpty) return (element: null, matchCount: 0);

  // Ambiguous: multiple matches and no index specified — caller must disambiguate.
  if (matcher.index == null && matches.length > 1) {
    return (element: null, matchCount: matches.length);
  }

  final targetIndex = matcher.index ?? 0;
  if (targetIndex >= matches.length) {
    return (element: null, matchCount: matches.length);
  }
  return (element: matches[targetIndex], matchCount: matches.length);
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
