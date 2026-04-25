import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleBack(
  String method,
  Map<String, String> params,
) async {
  try {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      return errorResponse('No root element available');
    }
    // Walk DOWN the tree to find the first NavigatorState.
    NavigatorState? navigator;
    void findNavigator(Element element) {
      if (navigator != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
        return;
      }
      element.visitChildElements(findNavigator);
    }

    rootElement.visitChildElements(findNavigator);
    if (navigator == null) {
      return errorResponse('No Navigator found');
    }
    final popped = await navigator!.maybePop();
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'status': 'Success', 'popped': popped}),
    );
  } catch (e) {
    return errorResponse('Back failed: $e');
  }
}
