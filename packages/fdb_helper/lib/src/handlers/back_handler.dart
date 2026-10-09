import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'handler_utils.dart';

/// Presses the system back button, exactly like the Android back button or
/// back gesture does.
///
/// The engine delivers a back press as a `popRoute` call on the
/// `flutter/navigation` channel. This pushes that same message into the
/// framework, so the app decides what back does through its own wiring:
/// `WidgetsApp` / `Router` and its `BackButtonDispatcher` (auto_route,
/// go_router), `NavigatorPopHandler`, `PopScope`, dialogs.
///
/// `popped` is the framework's answer: `true` when something in the app
/// handled the back (popped a route, or a `PopScope` intercepted it).
///
/// When nothing in the app handles it, the framework would call
/// `SystemNavigator.pop()`. On Android that is what a real back press does
/// (the app leaves the foreground), so fdb does the same and reports
/// `passedToOs: true`. Other platforms have no system back button that reaches
/// the app, and there `SystemNavigator.pop()` can quit it (macOS), so fdb
/// leaves the app alone and reports `passedToOs: false`.
Future<developer.ServiceExtensionResponse> handleBack(
  String method,
  Map<String, String> params,
) async {
  try {
    final popped = await _pressSystemBack();
    final passedToOs = !popped && _hasSystemBackButton();
    if (passedToOs) await SystemNavigator.pop();
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'status': 'Success', 'popped': popped, 'passedToOs': passedToOs}),
    );
  } catch (e) {
    return errorResponse('Back failed: $e');
  }
}

bool _hasSystemBackButton() => !kIsWeb && Platform.isAndroid;

/// Delivers `popRoute` the way the engine does and returns whether the app
/// handled it.
///
/// [WidgetsBinding.handlePopRoute] asks its observers in registration order
/// and calls `SystemNavigator.pop()` when none of them handles the pop. A
/// temporary observer registered last answers only when every app observer
/// declined, which keeps the framework from calling `SystemNavigator.pop()`
/// itself, so [handleBack] can decide per platform.
Future<bool> _pressSystemBack() async {
  final unhandled = _UnhandledBackObserver();
  WidgetsBinding.instance.addObserver(unhandled);
  try {
    await _pushPopRoute();
    return !unhandled.reached;
  } finally {
    WidgetsBinding.instance.removeObserver(unhandled);
  }
}

Future<void> _pushPopRoute() {
  final channel = SystemChannels.navigation;
  final reply = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    channel.name,
    channel.codec.encodeMethodCall(const MethodCall('popRoute')),
    (ByteData? data) {
      if (data == null) {
        reply.completeError(StateError('the app has no handler for ${channel.name} (no WidgetsBinding?)'));
        return;
      }
      try {
        channel.codec.decodeEnvelope(data);
        reply.complete();
      } catch (e) {
        reply.completeError(e);
      }
    },
  );
  return reply.future;
}

/// Private exception to the no-classes rule for handler files:
/// [WidgetsBindingObserver] has no callback-based form.
class _UnhandledBackObserver with WidgetsBindingObserver {
  bool reached = false;

  @override
  Future<bool> didPopRoute() async {
    reached = true;
    return true;
  }
}
