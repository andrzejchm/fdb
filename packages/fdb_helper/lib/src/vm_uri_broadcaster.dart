import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Emits the Dart VM service URI to the platform log so that `fdb attach`
/// can discover it automatically without the user copy-pasting the URL.
///
/// Platform behaviour:
/// - **iOS** (simulator + physical): `debugPrint` routes through the Flutter
///   engine's `syslog()` callback, which lands in the unified log. The
///   simulator log is readable via `xcrun simctl spawn <udid> log show`;
///   the physical-device log is readable via `idevicesyslog`.
/// - **Android**: `debugPrint` routes to logcat with tag `flutter`, readable
///   via `adb logcat -s flutter`.
/// - **macOS/Linux/Windows**: `debugPrint` writes to stdout. `fdb attach`
///   does not currently scan stdout for externally-launched apps on these
///   platforms — pass `--debug-url` manually if auto-discovery fails.
///
/// Called once from [FdbBinding.initServiceExtensions] (debug/profile only).
Future<void> broadcastVmUri() async {
  if (kReleaseMode) return;
  try {
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    if (uri == null) return;
    // Use debugPrint so it goes through the platform log on iOS/Android.
    debugPrint('[FDB_VM_URI] $uri');
  } catch (_) {
    // VM service not running in this build mode — silently ignore.
  }
}
