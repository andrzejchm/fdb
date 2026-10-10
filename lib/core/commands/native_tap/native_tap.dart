import 'dart:io';

import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:fdb/core/commands/tap/tap.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/native_tap/native_tap_models.dart';

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// On Android this goes through `adb shell input tap`, which reaches any
/// on-screen UI regardless of process.
///
/// On iOS simulator this compiles (once, cached) a small Swift helper that
/// injects the touch through SimulatorKit's HID client, so it reaches every
/// process on screen, including SpringBoard system dialogs ("Allow location
/// access?", "Open in Test App?", etc.). When the helper cannot be used (no
/// Xcode toolchain, unknown device, compile failure...) it falls back to the
/// in-process `UIApplication.sendEvent()` path (the same one `fdb tap --at`
/// uses), which cannot reach SpringBoard; the result carries the reason so
/// the CLI adapter can warn.
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
// iOS simulator — HID injection, falling back to in-process tap
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapIosSimulator({required NativeTapInput input}) async {
  final x = input.x;
  final y = input.y;

  final udid = readDevice();
  final String reason;
  if (udid == null) {
    reason = 'no simulator UDID recorded for this session';
  } else {
    final hid = await iosSimulatorHidTap(udid: udid, x: x, y: y);
    switch (hid) {
      case IosSimulatorHidTapped():
        return NativeTapIosSimulator(x: x.toInt(), y: y.toInt());
      case IosSimulatorHidOutOfBounds(:final message):
        return NativeTapIosSimulatorOutOfBounds(message);
      case IosSimulatorHidFailed(:final message):
        // Part of the touch may have gone out; falling back could double-tap.
        return NativeTapIosSimulatorFailed(message);
      case IosSimulatorHidUnavailable(reason: final unavailableReason):
        reason = unavailableReason;
    }
  }

  final tapResult = await tapWidget((
    x: x,
    y: y,
    text: null,
    key: null,
    type: null,
    index: null,
    usedAt: true,
    ref: null,
    expectText: null,
    expectType: null,
    timeoutSeconds: 10,
  ));
  return NativeTapIosSimulatorFallback(x: x.toInt(), y: y.toInt(), reason: reason, tapResult: tapResult);
}
