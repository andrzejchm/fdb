// fdb_binding.dart — thin binding: registration only, zero logic
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'handlers/back_handler.dart';
import 'handlers/clean_handler.dart';
import 'handlers/describe_handler.dart';
import 'handlers/double_tap_handler.dart';
import 'handlers/input_handler.dart';
import 'handlers/screenshot_handler.dart';
import 'handlers/scroll_handler.dart';
import 'handlers/scroll_to_handler.dart';
import 'handlers/shared_prefs_handler.dart';
import 'handlers/swipe_handler.dart';
import 'handlers/tap_handler.dart';
import 'handlers/wait_handler.dart';

/// A custom binding that registers VM service extensions for widget interaction.
///
/// Usage in `main()`:
/// ```dart
/// void main() {
///   FdbBinding.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
///
/// This registers the following VM service extensions (in debug and profile mode only):
/// - `ext.fdb.elements` — list all interactive elements with bounds
/// - `ext.fdb.describe` — describe the current screen
/// - `ext.fdb.tap` — tap a widget by key, text, type, or coordinates
/// - `ext.fdb.longPress` — long-press a widget (same as tap with duration=500ms)
/// - `ext.fdb.doubleTap` — double-tap a widget by key, text, type, or coordinates
/// - `ext.fdb.enterText` — enter text into a text field
/// - `ext.fdb.scroll` — perform a swipe/scroll gesture
/// - `ext.fdb.scrollTo` — scroll until a target widget becomes visible
/// - `ext.fdb.waitFor` — wait until a widget or route is present or absent
/// - `ext.fdb.swipe` — swipe in a direction
/// - `ext.fdb.back` — trigger Navigator.maybePop()
/// - `ext.fdb.clean` — delete app storage directories
/// - `ext.fdb.sharedPrefs` — read/write shared preferences
/// - `ext.fdb.screenshot` — capture the Flutter rendering surface as base64 PNG
class FdbBinding extends WidgetsFlutterBinding {
  FdbBinding._();

  static FdbBinding? _instance;

  /// Returns the singleton [FdbBinding], creating it on first call.
  static FdbBinding ensureInitialized() {
    if (_instance == null) {
      FdbBinding._();
    }
    return _instance!;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();
    if (kReleaseMode) return;
    _registerExtension('ext.fdb.elements', handleElements);
    _registerExtension('ext.fdb.describe', handleDescribe);
    _registerExtension('ext.fdb.tap', handleTap);
    _registerExtension('ext.fdb.longPress', (method, params) {
      return handleTap(method, {
        ...params,
        if (!params.containsKey('duration')) 'duration': '500',
      });
    });
    _registerExtension('ext.fdb.doubleTap', handleDoubleTap);
    _registerExtension('ext.fdb.enterText', handleEnterText);
    _registerExtension('ext.fdb.scroll', handleScroll);
    _registerExtension('ext.fdb.scrollTo', handleScrollTo);
    _registerExtension('ext.fdb.waitFor', handleWaitFor);
    _registerExtension('ext.fdb.swipe', handleSwipe);
    _registerExtension('ext.fdb.back', handleBack);
    _registerExtension('ext.fdb.clean', handleClean);
    _registerExtension('ext.fdb.sharedPrefs', handleSharedPrefs);
    _registerExtension('ext.fdb.screenshot', handleScreenshot);
  }

  /// Registers a VM service extension, silently ignoring double-registration
  /// that can occur on hot reload.
  void _registerExtension(
    String name,
    Future<developer.ServiceExtensionResponse> Function(
      String method,
      Map<String, String> params,
    ) handler,
  ) {
    try {
      developer.registerExtension(name, handler);
    } on ArgumentError {
      // Already registered — happens on hot reload. Safe to ignore.
    }
  }
}
