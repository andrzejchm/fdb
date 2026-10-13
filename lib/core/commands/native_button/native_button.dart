import 'dart:async';

import 'package:fdb/core/commands/native_button/native_button_models.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/native_button/native_button_models.dart';

/// Delivers one hardware button press to the recorded device without using the VM.
/// Lock is a power/lock button, not an idempotent request to lock or unlock.
/// Never retries uncertain delivery; never throws.
Future<NativeButtonResult> nativeButton(NativeButtonInput input, {HidProcessRunner? runner}) async {
  try {
    if (input.button != 'home' && input.button != 'lock') {
      return const NativeButtonError('Expected one button: home or lock.');
    }
    final info = readPlatformInfo();
    if (info == null) return const NativeButtonError('No fdb session platform metadata found. Run fdb launch first.');
    if (info.platform.startsWith('ios') && !info.emulator) {
      return const NativeButtonError('native-button is not supported on physical iOS devices.');
    }
    final android = info.platform.startsWith('android');
    if (!android && !info.platform.startsWith('ios')) {
      return NativeButtonError('native-button is not supported on platform "${info.platform}".');
    }
    final device = readDevice();
    if (device == null || device.trim().isEmpty) {
      return const NativeButtonError('No device ID recorded for this session. Run fdb launch --device <id> first.');
    }
    if (android) {
      final output = await (runner ?? runHidProcess)(
        'adb',
        ['-s', device, 'shell', 'input', 'keyevent', input.button == 'home' ? 'KEYCODE_HOME' : 'KEYCODE_POWER'],
        const Duration(seconds: 30),
      );
      final details = '${output.stderr}\n${output.stdout}'.trim();
      if (details.contains('INJECT_EVENTS') || details.contains('SecurityException')) {
        return NativeButtonError('Android blocked input injection (INJECT_EVENTS). Enable Developer options: '
            'Xiaomi/HyperOS "USB debugging (Security settings)", OPPO/OnePlus/Realme "Disable permission monitoring". '
            'adb said: $details');
      }
      if (output.exitCode != 0 || details.contains('Error:') || details.contains('Exception')) {
        return NativeButtonError('adb input keyevent failed; delivery may be partial (no retry): $details '
            '(exit ${output.exitCode})');
      }
    } else {
      switch (await iosSimulatorHidButton(udid: device, button: input.button, runner: runner)) {
        case IosSimulatorHidTapped():
          break;
        case IosSimulatorHidUnavailable(:final reason):
          return NativeButtonError('iOS simulator HID button unavailable: $reason');
        case IosSimulatorHidFailed(:final message):
          return NativeButtonError(message);
        case IosSimulatorHidOutOfBounds(:final message):
          return NativeButtonError(message);
        case IosSimulatorHidOrientationUnknown(:final message):
          return NativeButtonError(message);
      }
    }
    return NativeButtonSuccess(android ? 'android' : 'ios-simulator', input.button);
  } on TimeoutException {
    return const NativeButtonError('native-button timed out; delivery may be partial (no retry).');
  } catch (e) {
    return NativeButtonError('native-button failed: $e');
  }
}
