import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../version.dart';
import 'handler_utils.dart';

/// Reports the app's current [AppLifecycleState] so the fdb CLI can warn when
/// the app is not in the foreground (another app or the home screen covers it).
///
/// Response: `{"status": "Success", "lifecycleState": "resumed", "fdbHelperVersion": "1.13.0", "devicePixelRatio": 3.75}`.
/// `lifecycleState` is null when the engine has not reported a state yet.
/// `fdbHelperVersion` lets the CLI detect an app still running an older build.
/// `devicePixelRatio` is the main view's ratio (null without a view); `fdb
/// native-tap --logical` uses it to turn logical pixels into physical ones.
Future<developer.ServiceExtensionResponse> handleLifecycle(
  String method,
  Map<String, String> params,
) async {
  try {
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'Success',
        'lifecycleState': WidgetsBinding.instance.lifecycleState?.name,
        'fdbHelperVersion': fdbHelperVersion,
        'devicePixelRatio': _devicePixelRatio(),
      }),
    );
  } catch (e) {
    return errorResponse('Lifecycle failed: $e');
  }
}

double? _devicePixelRatio() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  return (dispatcher.implicitView ?? dispatcher.views.firstOrNull)?.devicePixelRatio;
}
