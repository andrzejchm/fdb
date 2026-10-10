import 'package:fdb/core/commands/tap/tap_models.dart';
import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [nativeTap].
///
/// Exactly one target: [x] and [y] together, or [text].
/// - [text]: label, content description or resource id of a native element
///   (Android only for now). [index] picks among several matches (0-based).
///   [timeoutSeconds] is how long to keep looking for a match.
/// - [logical]: [x]/[y] are Flutter logical pixels. On Android they are
///   multiplied by the device pixel ratio; on the iOS simulator they are
///   already points, so it changes nothing.
typedef NativeTapInput = ({
  double? x,
  double? y,
  String? text,
  int? index,
  int timeoutSeconds,
  bool logical,
});

/// Result of a [nativeTap] invocation.
sealed class NativeTapResult extends CommandResult {
  const NativeTapResult();
}

/// Android tap succeeded. [x]/[y] are the physical pixels that were tapped;
/// [text] is the matched label when the tap was by `--text`.
class NativeTapAndroid extends NativeTapResult {
  const NativeTapAndroid({required this.x, required this.y, this.text});
  final int x;
  final int y;
  final String? text;
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

/// The iOS Simulator interface orientation could not be mapped, so nothing
/// was tapped. No fallback tap is attempted: it could hit the app behind a
/// SpringBoard dialog instead of the dialog.
class NativeTapIosSimulatorOrientationUnknown extends NativeTapResult {
  const NativeTapIosSimulatorOrientationUnknown(this.message);
  final String message;
}

/// The iOS Simulator HID tap may have been partially delivered (e.g. touch
/// down sent, touch up failed). No fallback tap is attempted, since that could
/// tap twice.
class NativeTapIosSimulatorFailed extends NativeTapResult {
  const NativeTapIosSimulatorFailed(this.message);
  final String message;
}

/// `--text` on the iOS simulator. Not implemented yet (fdb-hwr).
class NativeTapTextUnsupportedOnIosSimulator extends NativeTapResult {
  const NativeTapTextUnsupportedOnIosSimulator();
}

/// No active fdb session found.
class NativeTapNoSession extends NativeTapResult {
  const NativeTapNoSession();
}

/// Physical iOS device — not yet supported. [x]/[y] are null for `--text`.
class NativeTapPhysicalIosUnsupported extends NativeTapResult {
  const NativeTapPhysicalIosUnsupported({required this.x, required this.y});
  final double? x;
  final double? y;
}

/// macOS — not supported. [x]/[y] are null for `--text`.
class NativeTapMacosUnsupported extends NativeTapResult {
  const NativeTapMacosUnsupported({required this.x, required this.y});
  final double? x;
  final double? y;
}

/// Unsupported platform.
class NativeTapPlatformUnsupported extends NativeTapResult {
  const NativeTapPlatformUnsupported(this.platform);
  final String platform;
}

/// `adb shell input tap` failed: non-zero exit, or an exception in its
/// output with exit code 0.
class NativeTapAdbFailed extends NativeTapResult {
  const NativeTapAdbFailed(this.details);
  final String details;
}

/// `adb` binary could not be launched.
class NativeTapAdbExecutionFailed extends NativeTapResult {
  const NativeTapAdbExecutionFailed(this.error);
  final String error;
}

/// Android refused the injected tap (`SecurityException` / `INJECT_EVENTS`).
/// Some OEM builds (Xiaomi/HyperOS, OPPO/OnePlus/Realme, vivo) block it until
/// a Developer options switch is on. [details] is what adb printed.
class NativeTapInputInjectionBlocked extends NativeTapResult {
  const NativeTapInputInjectionBlocked(this.details);
  final String details;
}

/// No native element matched [query] before the timeout. [visibleLabels]
/// are the labels in the last window dump, in document order.
class NativeTapNoMatch extends NativeTapResult {
  const NativeTapNoMatch({required this.query, required this.visibleLabels});
  final String query;
  final List<String> visibleLabels;
}

/// One element matching a `--text` query, for [NativeTapAmbiguous].
typedef NativeTapCandidate = ({String label, int x, int y});

/// Several native elements matched [query] and no `--index` was given.
class NativeTapAmbiguous extends NativeTapResult {
  const NativeTapAmbiguous({required this.query, required this.candidates});
  final String query;
  final List<NativeTapCandidate> candidates;
}

/// `--index` is past the last of the [count] matches for [query].
class NativeTapIndexOutOfRange extends NativeTapResult {
  const NativeTapIndexOutOfRange({required this.query, required this.index, required this.count});
  final String query;
  final int index;
  final int count;
}

/// No usable `uiautomator dump` before the timeout. [reason] is the last
/// failure, e.g. `ERROR: could not get idle state.`
class NativeTapUiDumpFailed extends NativeTapResult {
  const NativeTapUiDumpFailed(this.reason);
  final String reason;
}

/// `--logical` was given but neither the app nor `adb shell wm density`
/// reported a device pixel ratio.
class NativeTapDevicePixelRatioUnavailable extends NativeTapResult {
  const NativeTapDevicePixelRatioUnavailable(this.reason);
  final String reason;
}
