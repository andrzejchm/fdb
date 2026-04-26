import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../element_tree_finder.dart';
import '../widget_matcher.dart';
import 'handler_utils.dart';

const _pollInterval = Duration(milliseconds: 200);

Future<developer.ServiceExtensionResponse> handleWaitFor(
  String method,
  Map<String, String> params,
) async {
  try {
    final condition = params['condition'];
    if (condition != 'present' && condition != 'absent') {
      return errorResponse('condition must be present or absent');
    }
    final resolvedCondition = condition as String;

    final timeout = int.tryParse(params['timeout'] ?? '10000');
    if (timeout == null) {
      return errorResponse('timeout must be a valid integer');
    }

    final route = params['route'];
    WidgetMatcher? matcher;
    if (route == null) {
      matcher = WidgetMatcher.fromParams(params);
      if (matcher is FocusedMatcher || matcher is CoordinatesMatcher) {
        return errorResponse('wait supports only --key, --text, --type, or --route');
      }
    }

    final selectorDescription = _selectorDescription(
      key: params['key'],
      text: params['text'],
      type: params['type'],
      route: route,
    );
    if (selectorDescription == null) {
      return errorResponse('Missing selector: use --key, --text, --type, or --route');
    }

    final deadline = DateTime.now().add(Duration(milliseconds: timeout));

    while (true) {
      if (_conditionMet(
        condition: resolvedCondition,
        matcher: matcher,
        route: route,
      )) {
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'status': 'Success',
            'condition': resolvedCondition,
            'selector': selectorDescription,
          }),
        );
      }

      if (DateTime.now().isAfter(deadline) || DateTime.now().isAtSameMomentAs(deadline)) {
        return errorResponse(
          'Timeout after ${timeout}ms waiting for $resolvedCondition $selectorDescription',
        );
      }

      await Future<void>.delayed(_pollInterval);
    }
  } on ArgumentError catch (e) {
    return errorResponse(e.message.toString());
  } catch (e) {
    return errorResponse('waitFor failed: $e');
  }
}

bool _conditionMet({
  required String condition,
  required WidgetMatcher? matcher,
  required String? route,
}) {
  if (route != null) {
    final currentRouteName = _currentRouteName();
    return condition == 'present' ? currentRouteName == route : currentRouteName != route;
  }

  final result = findHittableElement(matcher!);
  if (condition == 'present') {
    return result.element != null;
  }
  return result.element == null && result.matchCount == 0;
}

String? _currentRouteName() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  String? routeName;

  void visit(Element element) {
    final route = ModalRoute.of(element);
    if (route != null && route.isCurrent && route.settings.name != null) {
      routeName = route.settings.name;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return routeName;
}

String? _selectorDescription({
  required String? key,
  required String? text,
  required String? type,
  required String? route,
}) {
  if (key != null) return 'KEY=$key';
  if (text != null) return 'TEXT=$text';
  if (type != null) return 'TYPE=$type';
  if (route != null) return 'ROUTE=$route';
  return null;
}
