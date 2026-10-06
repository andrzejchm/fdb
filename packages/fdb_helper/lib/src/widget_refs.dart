import 'package:flutter/widgets.dart';

/// Stable `@N` refs for `fdb describe` entries, modelled on agent-browser's
/// element refs.
///
/// A ref names one [Element]. The element keeps its ref across describes
/// while it stays mounted: rebuilds, state changes and scrolling inside a
/// list that keeps it built do not change it. An element that is replaced
/// (removed, rebuilt under another key or type, its route popped) leaves its
/// ref stale, and the new element gets a new ref. Ids are never reused while
/// the isolate lives. Hot reload keeps them; hot restart starts again at 1.
///
/// A describe entry for a list child that is not built yet (a
/// `SliverChildListDelegate` child out of view) has no element. Its ref names
/// the widget instance instead, for as long as the mounted sliver still lists
/// it, and the element later built from that instance takes the ref over, so
/// the entry keeps its ref when it scrolls into view.
final _elementRefs = Expando<int>('fdb element ref');
final _widgetRefs = Expando<int>('fdb widget ref');
final _targets = <int, _RefTarget>{};
var _lastId = 0;
var _lastDescribed = <int>{};

class _RefTarget {
  _RefTarget({Element? element, this.listing}) : element = element == null ? null : WeakReference(element);

  final WeakReference<Element>? element;
  final _Listing? listing;
}

/// Where a not-built [widget] comes from: [child] of the delegate of the
/// [sliver] element ([widget] is [child] or inside it).
class _Listing {
  _Listing({required Widget widget, required Widget child, required Element sliver})
      : widget = WeakReference(widget),
        child = WeakReference(child),
        sliver = WeakReference(sliver);

  final WeakReference<Widget> widget;
  final WeakReference<Widget> child;
  final WeakReference<Element> sliver;

  /// [widget] while the mounted sliver still lists [child], else null.
  Widget? get listedWidget {
    final sliver = this.sliver.target;
    final child = this.child.target;
    if (sliver == null || child == null || !sliver.mounted) return null;
    final sliverWidget = sliver.widget;
    if (sliverWidget is! SliverMultiBoxAdaptorWidget) return null;
    final delegate = sliverWidget.delegate;
    if (delegate is! SliverChildListDelegate || !delegate.children.any((c) => identical(c, child))) return null;
    return widget.target;
  }
}

/// What a ref names right now: its mounted [element], or the [widget] of a
/// list child that is not built (or no longer built).
typedef ResolvedRef = ({Element? element, Widget? widget});

/// The ref of [element], assigning the next id on first sight.
int refForElement(Element element) {
  final existing = _elementRefs[element];
  if (existing != null) return existing;
  final widgetRef = _widgetRefs[element.widget];
  final id = widgetRef != null && _mountedElement(widgetRef) == null ? widgetRef : ++_lastId;
  _elementRefs[element] = id;
  _targets[id] = _RefTarget(element: element, listing: _targets[id]?.listing);
  return id;
}

/// The ref of [widget], which has no element yet: it is [child] of the
/// delegate of [sliver], or inside it.
int refForUnbuiltWidget(Widget widget, {required Widget child, required Element sliver}) {
  final existing = _widgetRefs[widget];
  if (existing != null && resolveRef(existing) != null) return existing;
  final id = ++_lastId;
  _widgetRefs[widget] = id;
  _targets[id] = _RefTarget(listing: _Listing(widget: widget, child: child, sliver: sliver));
  return id;
}

/// What [id] names now, or null when the ref is stale (its widget was
/// removed or rebuilt) or was never handed out.
ResolvedRef? resolveRef(int id) {
  final element = _mountedElement(id);
  if (element != null) return (element: element, widget: null);
  final widget = _targets[id]?.listing?.listedWidget;
  return widget == null ? null : (element: null, widget: widget);
}

/// Records the refs of the describe that just ran and returns the refs of
/// the previous describe that are stale now. Forgets stale refs.
List<int> takeRemovedRefs(Iterable<int> described) {
  final removed = _lastDescribed.where((id) => resolveRef(id) == null).toList()..sort();
  _lastDescribed = described.toSet();
  final stale = _targets.keys.where((id) => resolveRef(id) == null).toList();
  stale.forEach(_targets.remove);
  return removed;
}

Element? _mountedElement(int id) {
  final element = _targets[id]?.element?.target;
  return element != null && element.mounted ? element : null;
}

/// The error for a ref that names nothing.
String staleRefMessage(int id) => '@$id is stale: the widget was removed or rebuilt. Run fdb describe again.';
