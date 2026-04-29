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

/// iOS Simulator tap delegated to in-process tap (UIApplication.sendEvent).
///
/// SpringBoard-level system dialogs are unreachable from within the app
/// process; [tapResult] reflects the outcome of the in-process tap attempt.
class NativeTapIosSimulator extends NativeTapResult {
  const NativeTapIosSimulator({required this.x, required this.y, required this.tapResult});
  final int x;
  final int y;

  /// The result of the underlying [tapWidget] call.
  final TapResult tapResult;
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
