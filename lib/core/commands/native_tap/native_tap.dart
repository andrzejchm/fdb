import 'dart:io';

import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:fdb/core/commands/tap/tap.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/native_tap/native_tap_models.dart';

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// On Android this goes through `adb shell input tap`, which reaches any
/// on-screen UI regardless of process.
///
/// On iOS simulator there is no dependency-free mechanism that crosses the
/// SpringBoard process boundary, so this delegates to the in-process
/// `UIApplication.sendEvent()` path (the same one `fdb tap --at` uses).
/// That path reaches `UIAlertController` and other in-app native overlays
/// but cannot reach SpringBoard-level system dialogs ("Allow location
/// access?", "Open in Test App?", etc.). The CLI adapter emits a WARNING
/// so callers know the limitation.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<NativeTapResult> nativeTap(NativeTapInput input) async {
  final platformInfo = readPlatformInfo();
  if (platformInfo == null) return const NativeTapNoSession();

  final platform = platformInfo.platform;
  final isEmulator = platformInfo.emulator;

  if (platform.startsWith('android')) {
    return _tapAndroid(input: input);
  }

  if (platform.startsWith('ios') && isEmulator) {
    return _tapIosSimulator(input: input);
  }

  if (platform.startsWith('ios') && !isEmulator) {
    return NativeTapPhysicalIosUnsupported(x: input.x, y: input.y);
  }

  if (platform.startsWith('darwin')) {
    return NativeTapMacosUnsupported(x: input.x, y: input.y);
  }

  return NativeTapPlatformUnsupported(platform);
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapAndroid({required NativeTapInput input}) async {
  final deviceId = readDevice();
  final deviceArgs = deviceId != null ? ['-s', deviceId] : <String>[];
  final x = input.x;
  final y = input.y;
  try {
    final result = await Process.run('adb', [
      ...deviceArgs,
      'shell',
      'input',
      'tap',
      x.toInt().toString(),
      y.toInt().toString(),
    ]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      return NativeTapAdbFailed(details);
    }
    return NativeTapAndroid(x: x.toInt(), y: y.toInt());
  } catch (e) {
    return NativeTapAdbExecutionFailed(e.toString());
  }
}

// ---------------------------------------------------------------------------
// iOS simulator — delegate to in-process tap (UIApplication.sendEvent)
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapIosSimulator({required NativeTapInput input}) async {
  final x = input.x;
  final y = input.y;
  final tapResult = await tapWidget((
    x: x,
    y: y,
    text: null,
    key: null,
    type: null,
    index: null,
    usedAt: true,
    describeRef: null,
    timeoutSeconds: 10,
  ));
  return NativeTapIosSimulator(x: x.toInt(), y: y.toInt(), tapResult: tapResult);
}
