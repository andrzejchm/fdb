import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'handler_utils.dart';

/// Pops the frontmost screen, like the Android back button would.
///
/// Apps often nest navigators (an `AutoRouter` or tab shell inside the root
/// navigator), so the root navigator is not the one showing the front screen.
/// This pops the innermost visible navigator, and walks outwards only when that
/// navigator has nothing left to pop.
///
/// `WidgetsBinding.handlePopRoute` is not used on purpose: it is `@protected`
/// and, when no observer handles the pop, calls `SystemNavigator.pop()`, which
/// quits the app at the root screen instead of reporting `popped: false`.
Future<developer.ServiceExtensionResponse> handleBack(
  String method,
  Map<String, String> params,
) async {
  try {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      return errorResponse('No root element available');
    }
    final innermost = _findInnermostActiveNavigator(rootElement);
    if (innermost == null) {
      return errorResponse('No Navigator found');
    }
    var popped = false;
    for (NavigatorState? navigator = innermost; navigator != null && !popped;) {
      popped = await navigator.maybePop();
      navigator = navigator.mounted ? navigator.context.findAncestorStateOfType<NavigatorState>() : null;
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'status': 'Success', 'popped': popped}),
    );
  } catch (e) {
    return errorResponse('Back failed: $e');
  }
}

/// Returns the most deeply nested navigator that is currently showing.
///
/// A navigator is skipped, together with everything inside it, when it is not
/// onstage (e.g. a hidden tab, a route fully covered by an opaque one), when an
/// ancestor [Visibility] hides it (e.g. a tab of an [IndexedStack]), or when its
/// hosting route is covered by another route (e.g. a dialog pushed on the root
/// navigator). That way a dialog is dismissed before the screen below it. When
/// several navigators are equally deep (side by side panes), the one built last
/// wins.
NavigatorState? _findInnermostActiveNavigator(Element rootElement) {
  NavigatorState? innermost;
  var innermostDepth = -1;

  void visit(Element element, int depth) {
    var childDepth = depth;
    if (element is StatefulElement && element.state is NavigatorState) {
      final hostRoute = ModalRoute.of(element);
      if (hostRoute != null && !hostRoute.isCurrent) return;
      if (!Visibility.of(element)) return;
      childDepth = depth + 1;
      if (childDepth >= innermostDepth) {
        innermost = element.state as NavigatorState;
        innermostDepth = childDepth;
      }
    }
    element.debugVisitOnstageChildren((child) => visit(child, childDepth));
  }

  rootElement.debugVisitOnstageChildren((child) => visit(child, 0));
  return innermost;
}
