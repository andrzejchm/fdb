import 'package:fdb/core/commands/native_tap/ios_simulator_accessibility.dart';
import 'package:fdb/core/commands/native_tap/ios_simulator_hid.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:fdb/core/commands/native_tap/native_text_match.dart';

/// Reads the simulator accessibility tree, as [iosSimulatorDescribe] does,
/// giving up after [timeout].
typedef IosSimulatorDescriber = Future<IosSimulatorDescribeResult> Function(String udid, Duration timeout);

/// Taps a point in interface points, as [iosSimulatorHidTap] does.
typedef IosSimulatorTapper = Future<IosSimulatorHidResult> Function(String udid, double x, double y);

/// Shortest limit for one tree read, even when less of `--timeout` is left:
/// the first read on a freshly booted simulator can take several seconds.
const iosSimulatorMinDescribeTimeout = Duration(seconds: 10);

/// `fdb native-tap --text` on the iOS simulator: finds the element in the
/// simulator's accessibility tree (the frontmost app, or SpringBoard while a
/// system alert is up) and taps its frame center through the HID helper.
///
/// Reads the tree again every 300 ms until a match shows up or the timeout
/// passes. Retried, with the last problem reported at the deadline: a tree
/// with nothing matching yet (right after an app launches it is a bare
/// application element), an incomplete tree whose answer depends on what is
/// missing, a tree whose frames can't be placed on screen, an unknown
/// orientation and failed reads. Problems a retry can't fix (no toolchain,
/// unknown simulator, missing API) fail at once. Each read may take up to
/// the time left, but at least [iosSimulatorMinDescribeTimeout].
///
/// There is no in-process fallback: without the accessibility tree there is
/// nothing to match against.
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
    return const NativeTapIosSimulatorTapUnavailable('no simulator UDID recorded for this session');
  }
  final readTree = describe ?? (u, timeout) => iosSimulatorDescribe(udid: u, timeout: timeout);
  final tapAt = tap ?? (u, x, y) => iosSimulatorHidTap(udid: u, x: x, y: y);
  final clock = now ?? DateTime.now;
  final wait = sleep ?? Future<void>.delayed;

  try {
    final deadline = clock().add(Duration(seconds: input.timeoutSeconds ?? defaultNativeTapTextTimeoutSeconds));
    // What to report if the deadline passes now.
    NativeTapResult? last;

    while (true) {
      final left = deadline.difference(clock());
      final described =
          await readTree(udid, left > iosSimulatorMinDescribeTimeout ? left : iosSimulatorMinDescribeTimeout);
      final atDeadline = !clock().isBefore(deadline);
      switch (described) {
        case IosSimulatorDescribeUnavailable(:final reason):
          return NativeTapIosSimulatorAccessibilityUnavailable(reason);
        case IosSimulatorDescribeOrientationUnknown(:final message):
          last = NativeTapIosSimulatorOrientationUnknown(message);
        case IosSimulatorDescribeFailed(:final reason):
          last = NativeTapIosSimulatorTreeUnreadable(reason);
        case IosSimulatorDescribed(:final json):
          switch (parseIosSimulatorAccessibility(json)) {
            case IosAxInvalid(:final reason):
              last = NativeTapIosSimulatorTreeUnreadable(reason);
            case IosAxParsed(:final snapshot):
              // An incomplete tree may be missing a match or a second
              // candidate: only trust a count-dependent answer at the deadline.
              final trusted = snapshot.complete || atDeadline;
              final matches = findIosAxMatches(snapshot, query);
              switch (pickNativeMatch(matches, index: index)) {
                case NativeMatchPicked(:final match):
                  if (index == null || trusted) return _tap(tapAt, udid, match);
                case NativeMatchAmbiguous(:final matches):
                  final ambiguous = NativeTapAmbiguous(
                    query: query,
                    candidates: [
                      for (final m in matches) (label: oneLineLabel(m.label), x: m.x.round(), y: m.y.round()),
                    ],
                  );
                  if (trusted) return ambiguous;
                  last = ambiguous;
                case NativeMatchNone():
                  last = _noTap(snapshot, query: query, index: index, matchCount: matches.length);
              }
          }
      }
      if (atDeadline) break;
      await wait(nativeTapTextPollInterval);
    }
    return last ?? NativeTapNoMatch(query: query, visibleLabels: const []);
  } catch (e) {
    return NativeTapIosSimulatorTreeUnreadable('$e');
  }
}

/// Why nothing matched [query] on [snapshot].
NativeTapResult _noTap(IosAxSnapshot snapshot, {required String query, required int? index, required int matchCount}) {
  if (iosAxLabelsWithoutFrames(snapshot)) {
    return NativeTapIosSimulatorFramesUnmapped(
      query: query,
      orientation: snapshot.orientation,
      labels: [
        for (final e in snapshot.elements)
          if (!e.isApplication && e.label.isNotEmpty) oneLineLabel(e.label),
      ],
    );
  }
  if (index != null && matchCount > 0) {
    return NativeTapIndexOutOfRange(query: query, index: index, count: matchCount);
  }
  return NativeTapNoMatch(query: query, visibleLabels: iosAxVisibleLabels(snapshot));
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
      // The in-process tap is no substitute for a SpringBoard alert, so do
      // not fall back.
      return NativeTapIosSimulatorTapUnavailable(reason);
  }
}
