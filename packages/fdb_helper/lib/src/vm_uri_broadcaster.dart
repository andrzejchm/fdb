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
/// Called once from [FdbServiceExtensionsMixin.initServiceExtensions] (debug/profile only).
Future<void> broadcastVmUri() async {
  if (kReleaseMode) return;
  try {
    var info = await developer.Service.getInfo();
    var uri = info.serverUri;

    // In profile builds launched without Flutter tooling the VM service web
    // server may not be started automatically. Enable it explicitly so the
    // URI is available, matching the pattern from dart-lang/sdk#53262.
    if (uri == null) {
      info = await developer.Service.controlWebServer(enable: true);
      uri = info.serverUri;
    }

    if (uri == null) return;
    // Use debugPrint so it goes through the platform log on iOS/Android.
    debugPrint('[FDB_VM_URI] $uri');
  } catch (_) {
    // VM service not running in this build mode — silently ignore.
  }
}
