import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'handler_utils.dart';

/// Reports the app's current [AppLifecycleState] so the fdb CLI can warn when
/// the app is not in the foreground (another app or the home screen covers it).
///
/// Response: `{"status": "Success", "lifecycleState": "resumed"}`.
/// `lifecycleState` is null when the engine has not reported a state yet.
Future<developer.ServiceExtensionResponse> handleLifecycle(
  String method,
  Map<String, String> params,
) async {
  try {
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'lifecycleState': WidgetsBinding.instance.lifecycleState?.name,
      }),
    );
  } catch (e) {
    return errorResponse('Lifecycle failed: $e');
  }
}
