import 'package:fdb/core/commands/native_tap/android_native_tap.dart' show defaultNativeTapTextTimeoutSeconds;
import 'package:fdb/core/commands/native_tap/ios_simulator_accessibility.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:fdb/core/commands/native_tap/native_text_match.dart';

/// Reads the simulator accessibility tree, as [iosSimulatorDescribe] does.
typedef IosSimulatorDescriber = Future<IosSimulatorDescribeResult> Function(String udid);

/// Taps a point in interface points, as [iosSimulatorHidTap] does.
typedef IosSimulatorTapper = Future<IosSimulatorHidResult> Function(String udid, double x, double y);

const _pollInterval = Duration(milliseconds: 300);

/// `fdb native-tap --text` on the iOS simulator: finds the element in the
/// simulator's accessibility tree (the frontmost app, or SpringBoard while a
/// system alert is up) and taps its frame center through the HID helper.
///
/// Reads the tree again every 300 ms until a match shows up or the timeout
/// passes. Right after an app launches the tree is a bare application
/// element, which simply has no match yet. There is no in-process fallback:
/// without the accessibility tree there is nothing to match against.
///
/// [describe], [tap], [now] and [sleep] are injectable for tests.
/// Never throws.
Future<NativeTapResult> nativeTapIosSimulatorText(
  NativeTapInput input, {
  required String? udid,
  IosSimulatorDescriber? describe,
  IosSimulatorTapper? tap,
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
}) async {
  final query = input.text!;
  final index = input.index;
  if (udid == null) {
    return const NativeTapIosSimulatorAccessibilityUnavailable('no simulator UDID recorded for this session');
  }
  final readTree = describe ?? (u) => iosSimulatorDescribe(udid: u);
  final tapAt = tap ?? (u, x, y) => iosSimulatorHidTap(udid: u, x: x, y: y);
  final clock = now ?? DateTime.now;
  final wait = sleep ?? Future<void>.delayed;

  try {
    final deadline = clock().add(Duration(seconds: input.timeoutSeconds ?? defaultNativeTapTextTimeoutSeconds));
    List<String> lastLabels = const [];
    var lastMatchCount = 0;

    while (true) {
      final described = await readTree(udid);
      final IosAxSnapshot snapshot;
      switch (described) {
        case IosSimulatorDescribeUnavailable(:final reason):
          return NativeTapIosSimulatorAccessibilityUnavailable(reason);
        case IosSimulatorDescribeOrientationUnknown(:final message):
          return NativeTapIosSimulatorOrientationUnknown(message);
        case IosSimulatorDescribed(:final json):
          switch (parseIosSimulatorAccessibility(json)) {
            case IosAxInvalid(:final reason):
              return NativeTapIosSimulatorAccessibilityUnavailable(reason);
            case IosAxParsed(snapshot: final parsed):
              snapshot = parsed;
          }
      }

      final matches = findIosAxMatches(snapshot, query);
      switch (pickNativeMatch(matches, index: index)) {
        case NativeMatchPicked(:final match):
          return _tap(tapAt, udid, match);
        case NativeMatchAmbiguous(:final matches):
          return NativeTapAmbiguous(
            query: query,
            candidates: [
              for (final m in matches) (label: oneLineLabel(m.label), x: m.x.round(), y: m.y.round()),
            ],
          );
        case NativeMatchNone():
          lastLabels = iosAxVisibleLabels(snapshot);
          lastMatchCount = matches.length;
      }
      if (!clock().isBefore(deadline)) break;
      await wait(_pollInterval);
    }

    if (index != null && lastMatchCount > 0) {
      return NativeTapIndexOutOfRange(query: query, index: index, count: lastMatchCount);
    }
    return NativeTapNoMatch(query: query, visibleLabels: lastLabels);
  } catch (e) {
    return NativeTapIosSimulatorAccessibilityUnavailable('$e');
  }
}

Future<NativeTapResult> _tap(IosSimulatorTapper tapAt, String udid, IosAxMatch match) async {
  final x = match.x;
  final y = match.y;
  switch (await tapAt(udid, x, y)) {
    case IosSimulatorHidTapped():
      return NativeTapIosSimulator(x: x.round(), y: y.round(), text: oneLineLabel(match.label));
    case IosSimulatorHidOutOfBounds(:final message):
      return NativeTapIosSimulatorOutOfBounds(message);
    case IosSimulatorHidOrientationUnknown(:final message):
      return NativeTapIosSimulatorOrientationUnknown(message);
    case IosSimulatorHidFailed(:final message):
      return NativeTapIosSimulatorFailed(message);
    case IosSimulatorHidUnavailable(:final reason):
      // Same binary as describe, so this is rare; the in-process tap is no
      // substitute for a SpringBoard alert, so do not fall back.
      return NativeTapIosSimulatorAccessibilityUnavailable(reason);
  }
}
