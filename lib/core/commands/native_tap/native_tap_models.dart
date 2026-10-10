import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [nativeTap].
typedef NativeTapInput = ({double x, double y});

/// Result of a [nativeTap] invocation.
sealed class NativeTapResult extends CommandResult {
  const NativeTapResult();
}

/// Android tap succeeded.
class NativeTapAndroid extends NativeTapResult {
  const NativeTapAndroid({required this.x, required this.y});
  final int x;
  final int y;
}

/// iOS Simulator tap injected through the simulator's HID stack.
///
/// Reaches every process on screen, including SpringBoard system dialogs.
class NativeTapIosSimulator extends NativeTapResult {
  const NativeTapIosSimulator({required this.x, required this.y});
  final int x;
  final int y;
}

/// iOS Simulator HID tap was unavailable, so the tap went through the
/// in-process path (UIApplication.sendEvent) instead.
///
/// That path cannot reach SpringBoard-level system dialogs. [reason] says why
/// the HID path was skipped; [tapResult] is the outcome of the fallback tap.
class NativeTapIosSimulatorFallback extends NativeTapResult {
  const NativeTapIosSimulatorFallback({
    required this.x,
    required this.y,
    required this.reason,
    required this.tapResult,
  });
  final int x;
  final int y;
  final String reason;

  /// The result of the underlying [tapWidget] call.
  final TapResult tapResult;
}

/// The coordinates are outside the iOS Simulator screen.
class NativeTapIosSimulatorOutOfBounds extends NativeTapResult {
  const NativeTapIosSimulatorOutOfBounds(this.message);
  final String message;
}

/// The iOS Simulator HID tap may have been partially delivered (e.g. touch
/// down sent, touch up failed). No fallback tap is attempted, since that could
/// tap twice.
class NativeTapIosSimulatorFailed extends NativeTapResult {
  const NativeTapIosSimulatorFailed(this.message);
  final String message;
}

/// No active fdb session found.
class NativeTapNoSession extends NativeTapResult {
  const NativeTapNoSession();
}

/// Physical iOS device — not yet supported.
class NativeTapPhysicalIosUnsupported extends NativeTapResult {
  const NativeTapPhysicalIosUnsupported({required this.x, required this.y});
  final double x;
  final double y;
}

/// macOS — not supported.
class NativeTapMacosUnsupported extends NativeTapResult {
  const NativeTapMacosUnsupported({required this.x, required this.y});
  final double x;
  final double y;
}

/// Unsupported platform.
class NativeTapPlatformUnsupported extends NativeTapResult {
  const NativeTapPlatformUnsupported(this.platform);
  final String platform;
}

/// `adb shell input tap` exited non-zero.
class NativeTapAdbFailed extends NativeTapResult {
  const NativeTapAdbFailed(this.details);
  final String details;
}

/// `adb` binary could not be launched.
class NativeTapAdbExecutionFailed extends NativeTapResult {
  const NativeTapAdbExecutionFailed(this.error);
  final String error;
}
