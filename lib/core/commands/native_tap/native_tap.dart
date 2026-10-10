import 'package:fdb/core/commands/native_tap/android_native_tap.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:fdb/core/commands/tap/tap.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/native_tap/native_tap_models.dart';

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// On Android this goes through `adb shell input tap`, which reaches any
/// on-screen UI regardless of process. `--text` finds the element in a
/// `uiautomator dump` first (see `android_native_tap.dart`); `--logical`
/// scales the coordinates by the device pixel ratio.
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
    return nativeTapAndroid(input, deviceId: readDevice());
  }

  if (platform.startsWith('ios') && isEmulator) {
    // fdb-hwr: read the simulator accessibility tree and tap by label.
    if (input.text != null) return const NativeTapTextUnsupportedOnIosSimulator();
    // --logical is a no-op here: iOS coordinates are already points.
    return _tapIosSimulator(x: input.x!, y: input.y!);
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
// iOS simulator — HID injection, falling back to in-process tap
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapIosSimulator({required double x, required double y}) async {
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
      case IosSimulatorHidOrientationUnknown(:final message):
        // The fallback would not tap a SpringBoard dialog the caller may be aiming at.
        return NativeTapIosSimulatorOrientationUnknown(message);
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
