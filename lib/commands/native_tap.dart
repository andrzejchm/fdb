import 'dart:io';

import 'package:fdb/process_utils.dart';

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// Unlike [runTap], this command dispatches through the OS input system rather
/// than Flutter's [GestureBinding], making it suitable for tapping system
/// dialogs (iOS permission prompts, Android runtime-permission sheets, macOS
/// native dialogs) that sit outside the Flutter rendering surface.
///
/// Usage:
///   fdb native-tap --at 200,400
///   fdb native-tap --x 200 --y 400
///
/// Platforms and tools:
///   Android (device or emulator) — `adb shell input tap X Y`
///   iOS simulator                — `idb ui tap X Y` (IndigoHID path via SimulatorKit)
///   iOS physical                 — `idb ui tap X Y` (XCTest private API via WDA)
///   macOS                        — `cliclick c:SCREEN_X,SCREEN_Y` (CGEvent injection)
///
/// Coordinates:
///   Android  — Android logical pixels (dp), same as Flutter logical coords.
///   iOS      — iOS UIKit logical points (same coordinate space as Flutter).
///   macOS    — macOS screen coordinates (points). Use `fdb screenshot` to
///              determine the target position, then read coordinates from the
///              screenshot's pixel positions divided by the display scale.
Future<int> runNativeTap(List<String> args) async {
  double? x;
  double? y;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--x':
        final raw = args[++i];
        x = double.tryParse(raw);
        if (x == null) {
          stderr.writeln('ERROR: Invalid value for --x: $raw');
          return 1;
        }
      case '--y':
        final raw = args[++i];
        y = double.tryParse(raw);
        if (y == null) {
          stderr.writeln('ERROR: Invalid value for --y: $raw');
          return 1;
        }
      case '--at':
        final raw = args[++i];
        final parsed = _parseAt(raw);
        if (parsed == null) {
          stderr.writeln('ERROR: Invalid --at value: "$raw". Expected format: x,y (e.g. 200,400).');
          return 1;
        }
        x = parsed.$1;
        y = parsed.$2;
    }
  }

  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together.');
    return 1;
  }

  if (x == null || y == null) {
    stderr.writeln(
      'ERROR: No coordinates provided. Use --at x,y or --x <x> --y <y>.\n'
      'Usage: fdb native-tap --at 200,400',
    );
    return 1;
  }

  final platformInfo = readPlatformInfo();
  final deviceId = readDevice();

  if (platformInfo == null) {
    stderr.writeln('ERROR: No active fdb session found. Run fdb launch first.');
    return 1;
  }

  final platform = platformInfo.platform;
  final isEmulator = platformInfo.emulator;

  if (platform.startsWith('android')) {
    return _tapAndroid(deviceId: deviceId, x: x, y: y);
  }

  if (platform.startsWith('ios') && isEmulator) {
    return _tapIos(deviceId: deviceId, x: x, y: y, label: 'ios-simulator');
  }

  if (platform.startsWith('ios') && !isEmulator) {
    return _tapIos(deviceId: deviceId, x: x, y: y, label: 'ios-physical');
  }

  if (platform.startsWith('darwin')) {
    return _tapMacOs(x: x, y: y);
  }

  stderr.writeln('ERROR: native-tap is not supported on platform "$platform".');
  return 1;
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

/// Taps an Android device or emulator at ([x], [y]) via `adb shell input tap`.
///
/// Coordinates are in Android dp, which equals Flutter logical pixels.
Future<int> _tapAndroid({required String? deviceId, required double x, required double y}) async {
  final deviceArgs = deviceId != null ? ['-s', deviceId] : <String>[];
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
      stderr.writeln('ERROR: adb input tap failed: $details');
      return 1;
    }
    stdout.writeln('NATIVE_TAPPED=android X=${x.toInt()} Y=${y.toInt()}');
    return 0;
  } catch (e) {
    stderr.writeln(
      'ERROR: Failed to run adb: $e\n'
      '  Install adb: https://developer.android.com/studio/command-line/adb',
    );
    return 1;
  }
}

// ---------------------------------------------------------------------------
// iOS (simulator and physical)
// ---------------------------------------------------------------------------

/// Taps an iOS device (simulator or physical) at ([x], [y]) via `idb ui tap`.
///
/// For the simulator, idb injects the touch through IndigoHID via the
/// SimulatorKit private framework — the same path the Simulator.app uses
/// internally. This correctly reaches native OS dialogs that sit outside
/// Flutter's rendering surface.
///
/// For physical devices, idb drives an on-device XCTest runner (WebDriverAgent
/// style) that synthesizes the touch through XCTest private APIs.
///
/// Requires idb_companion (macOS host) and idb (Python CLI client):
///   brew install facebook/fb/idb-companion
///   pip3 install fb-idb
///
/// Docs: https://fbidb.io
Future<int> _tapIos({
  required String? deviceId,
  required double x,
  required double y,
  required String label,
}) async {
  final which = await Process.run('which', ['idb']);
  if (which.exitCode != 0) {
    stderr.writeln(
      'ERROR: native-tap on iOS requires idb.\n'
      '  Install: brew install facebook/fb/idb-companion && pip3 install fb-idb\n'
      '  Docs: https://fbidb.io',
    );
    return 1;
  }

  // idb uses the stored device UDID to target the right simulator/device.
  final udidArgs = deviceId != null ? ['--udid', deviceId] : <String>[];
  try {
    final result = await Process.run('idb', [
      'ui',
      'tap',
      x.toInt().toString(),
      y.toInt().toString(),
      ...udidArgs,
    ]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      stderr.writeln('ERROR: idb ui tap failed: $details');
      return 1;
    }
    stdout.writeln('NATIVE_TAPPED=$label X=${x.toInt()} Y=${y.toInt()}');
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run idb: $e');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// macOS
// ---------------------------------------------------------------------------

/// Taps within a macOS Flutter app window at ([x], [y]) via `cliclick`.
///
/// Locates the Flutter app window using CGWindowList (same approach as
/// `fdb screenshot`) to find the window's screen origin, then offsets by the
/// macOS title bar height so that coordinate (0,0) maps to the top-left of the
/// Flutter rendering surface.
///
/// `cliclick` injects the click via CGEvent at the Quartz HID event level,
/// which reaches AppKit/native windows. This works without Accessibility
/// permission for most app windows.
///
/// Install: brew install cliclick
Future<int> _tapMacOs({required double x, required double y}) async {
  final which = await Process.run('which', ['cliclick']);
  if (which.exitCode != 0) {
    stderr.writeln(
      'ERROR: native-tap on macOS requires cliclick.\n'
      '  Install: brew install cliclick',
    );
    return 1;
  }

  final pid = readPid();
  if (pid == null) {
    stderr.writeln('ERROR: No PID in session — cannot locate macOS window. Re-launch the app.');
    return 1;
  }

  final winOffset = await _macOsWindowOffset(pid);
  if (winOffset == null) {
    stderr.writeln(
      'ERROR: Could not find macOS window for PID $pid.\n'
      '  Make sure the Flutter macOS app is running and its window is visible.',
    );
    return 1;
  }

  final screenX = (winOffset.$1 + x).round();
  final screenY = (winOffset.$2 + y).round();

  // Verify Accessibility permission is granted — cliclick silently drops
  // CGEvent injections when it is missing. We check upfront so the error is
  // visible rather than a silent no-op.
  final axCheck = await Process.run('swift', [
    '-e',
    'import Cocoa; '
        'let trusted = AXIsProcessTrusted(); '
        'print(trusted ? "trusted" : "denied"); '
        'exit(trusted ? 0 : 1)',
  ]);
  if (axCheck.exitCode != 0) {
    stderr.writeln(
      'ERROR: native-tap on macOS requires Accessibility permission.\n'
      '  Grant it in: System Settings → Privacy & Security → Accessibility\n'
      '  Add the app or terminal that runs fdb (e.g. Terminal, iTerm2).\n'
      '  Note: native-tap targets native OS dialogs in other processes,\n'
      '  not Flutter content (use `fdb tap` for Flutter widgets).',
    );
    return 1;
  }

  try {
    final result = await Process.run('cliclick', ['c:$screenX,$screenY']);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      stderr.writeln('ERROR: cliclick failed: $details');
      return 1;
    }
    stdout.writeln('NATIVE_TAPPED=macos X=$screenX Y=$screenY');
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run cliclick: $e');
    return 1;
  }
}

/// Returns the (screenX, screenY) offset of the top-left of the Flutter
/// rendering surface inside the macOS app window.
///
/// Walks the process tree rooted at [pid] to handle the case where `flutter
/// run` spawns the actual .app as a child — same strategy as screenshot.dart.
Future<(double, double)?> _macOsWindowOffset(int pid) async {
  final pids = <int>[pid];
  try {
    final pg = await Process.run('pgrep', ['-P', '$pid']);
    if (pg.exitCode == 0) {
      for (final line in (pg.stdout as String).trim().split('\n')) {
        final child = int.tryParse(line.trim());
        if (child != null) pids.add(child);
      }
    }
  } catch (_) {}

  final pidsArg = pids.join(',');
  try {
    final result = await Process.run('swift', [
      '-e',
      '''
import Cocoa
let pidStrs = "$pidsArg".split(separator: ",")
let pids = pidStrs.compactMap { Int32(\$0) }
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [NSDictionary] else { exit(1) }
for w in list {
    guard let ownerPid = w[kCGWindowOwnerPID] as? Int32, pids.contains(ownerPid) else { continue }
    guard let bounds = w[kCGWindowBounds] as? NSDictionary,
          let wx = bounds["X"] as? Double,
          let wy = bounds["Y"] as? Double else { continue }
    print("\\(wx) \\(wy)")
    exit(0)
}
exit(1)
''',
    ]);
    if (result.exitCode != 0) return null;
    final parts = (result.stdout as String).trim().split(' ');
    if (parts.length < 2) return null;
    final wx = double.tryParse(parts[0]);
    final wy = double.tryParse(parts[1]);
    if (wx == null || wy == null) return null;
    // Add the macOS window title bar height so (0,0) = Flutter content top-left.
    return (wx, wy + _kMacOsTitleBarHeight);
  } catch (_) {
    return null;
  }
}

/// Standard macOS window title bar height in logical points.
const _kMacOsTitleBarHeight = 28.0;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

(double, double)? _parseAt(String raw) {
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final px = double.tryParse(parts[0].trim());
  final py = double.tryParse(parts[1].trim());
  if (px == null || py == null) return null;
  return (px, py);
}
