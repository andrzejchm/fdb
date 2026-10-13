import 'dart:async';

import 'package:fdb/core/commands/native_swipe/native_swipe_models.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/native_swipe/native_swipe_models.dart';

/// Injects an OS gesture on the recorded session device, without contacting the VM.
/// Coordinates are iOS points or Android physical pixels in the current orientation.
/// Never throws or falls back to Flutter gestures.
Future<NativeSwipeResult> nativeSwipe(NativeSwipeInput input, {HidProcessRunner? runner}) async {
  try {
    final invalid = validateNativeSwipe(input);
    if (invalid != null) return NativeSwipeError(invalid);
    final info = readPlatformInfo();
    if (info == null) return const NativeSwipeError('No fdb session platform metadata found. Run fdb launch first.');
    if (info.platform.startsWith('ios') && !info.emulator) {
      return const NativeSwipeError('native-swipe is not supported on physical iOS devices.');
    }
    final android = info.platform.startsWith('android');
    if (!android && !info.platform.startsWith('ios')) {
      return NativeSwipeError('native-swipe is not supported on platform "${info.platform}".');
    }
    final device = readDevice();
    if (device == null || device.trim().isEmpty) {
      return const NativeSwipeError('No device ID recorded for this session. Run fdb launch --device <id> first.');
    }
    if (android) {
      final run = runner ?? runHidProcess;
      final display = await run('adb', ['-s', device, 'shell', 'dumpsys', 'input'], const Duration(seconds: 15));
      final size = parseAndroidSwipeScreen(display.stdout);
      if (display.exitCode != 0 || size == null) {
        return const NativeSwipeError('Could not read Android display 0 bounds; no gesture delivered.');
      }
      if (input.fromX >= size.width ||
          input.toX >= size.width ||
          input.fromY >= size.height ||
          input.toY >= size.height) {
        return NativeSwipeError('coordinates are outside the screen (${size.width}x${size.height} physical pixels).');
      }
      // adb input owns the complete down/move/up sequence. Never retry it: a
      // failed transport or timeout can still mean the gesture reached the OS.
      final output = await run(
        'adb',
        [
          '-s',
          device,
          'shell',
          'input',
          'swipe',
          '${input.fromX}',
          '${input.fromY}',
          '${input.toX}',
          '${input.toY}',
          '${input.durationMs}'
        ],
        Duration(milliseconds: input.durationMs + 30000),
      );
      final details = '${output.stderr}\n${output.stdout}'.trim();
      if (details.contains('INJECT_EVENTS') || details.contains('SecurityException')) {
        return NativeSwipeError('Android blocked input injection (INJECT_EVENTS). Enable Developer options: '
            'Xiaomi/HyperOS "USB debugging (Security settings)", OPPO/OnePlus/Realme "Disable permission monitoring". '
            'adb said: $details');
      }
      if (output.exitCode != 0 || details.contains('Error:') || details.contains('Exception')) {
        return NativeSwipeError('adb input swipe failed; delivery may be partial (no retry): $details '
            '(exit ${output.exitCode})');
      }
      return NativeSwipeSuccess('android', input);
    }
    final hid = await iosSimulatorHidSwipe(
      udid: device,
      fromX: input.fromX,
      fromY: input.fromY,
      toX: input.toX,
      toY: input.toY,
      durationMs: input.durationMs,
      runner: runner,
    );
    return switch (hid) {
      IosSimulatorHidTapped() => NativeSwipeSuccess('ios-simulator', input),
      IosSimulatorHidOutOfBounds(:final message) => NativeSwipeError(message),
      IosSimulatorHidOrientationUnknown(:final message) => NativeSwipeError(message),
      IosSimulatorHidFailed(:final message) => NativeSwipeError(message),
      IosSimulatorHidUnavailable(:final reason) => NativeSwipeError('iOS simulator HID swipe unavailable: $reason'),
    };
  } on TimeoutException {
    return const NativeSwipeError('native-swipe timed out; delivery may be partial (no retry).');
  } catch (e) {
    return NativeSwipeError('native-swipe failed: $e');
  }
}

/// Reads the current display-0 input frame, already rotated and accounting for
/// resolution overrides. Refuses unknown dumps rather than using portrait wm size.
({int width, int height})? parseAndroidSwipeScreen(String dump) {
  final match = RegExp(r'Viewport[^\n]*\bdisplayId=0,[^\n]*logicalFrame=\[0,\s*0,\s*(\d+),\s*(\d+)\]').firstMatch(dump);
  if (match == null) return null;
  final width = int.tryParse(match.group(1)!);
  final height = int.tryParse(match.group(2)!);
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

/// Shared validation for CLI and library callers, before any native touch down.
String? validateNativeSwipe(NativeSwipeInput input) {
  final coordinates = [input.fromX, input.fromY, input.toX, input.toY];
  if (coordinates.any((n) => !n.isFinite || n < 0)) return 'Coordinates must be finite non-negative numbers.';
  if (input.durationMs < 1 || input.durationMs > 60000) {
    return '--duration must be an integer from 1 to 60000 milliseconds.';
  }
  if (input.fromX == input.toX && input.fromY == input.toY) return '--from and --to must be different points.';
  return null;
}
