import 'dart:io';

import 'package:fdb/process_utils.dart';

/// Taps native (non-Flutter) UI elements using platform-specific tools.
///
/// Unlike [runTap], this command dispatches through the OS rather than Flutter's
/// [GestureBinding], making it suitable for system dialogs (iOS permission prompts,
/// Android runtime-permission sheets, macOS native windows).
///
/// Usage:
///   fdb native-tap --at 200,400
///   fdb native-tap --x 200 --y 400
///
/// Platforms:
///   Android (device or emulator) — `adb shell input tap X Y`
///   iOS simulator               — `cliclick` with CGWindowList-based offset
///   iOS physical                — `idb ui tap X Y` (requires idb to be installed)
///   macOS                       — `cliclick` with CGWindowList-based offset
///
/// Coordinates:
///   Android  — Android logical pixels (dp), same as Flutter logical coords.
///   iOS sim  — In-simulator logical points (same coordinate space as Flutter).
///   iOS phys — iOS UIKit logical points.
///   macOS    — Flutter logical coords relative to the app window content origin.
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
    stderr.writeln(
      'ERROR: No active fdb session found. Run fdb launch first.',
    );
    return 1;
  }

  final platform = platformInfo.platform;
  final isEmulator = platformInfo.emulator;

  if (platform.startsWith('android')) {
    return _tapAndroid(deviceId: deviceId, x: x, y: y);
  }

  if (platform.startsWith('ios') && isEmulator) {
    return _tapIosSimulator(deviceId: deviceId, x: x, y: y);
  }

  if (platform.startsWith('ios') && !isEmulator) {
    return _tapIosPhysical(x: x, y: y);
  }

  if (platform.startsWith('darwin')) {
    return _tapMacOs(x: x, y: y);
  }

  stderr.writeln(
    'ERROR: native-tap is not supported on platform "$platform".',
  );
  return 1;
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

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
    stderr
        .writeln('ERROR: Failed to run adb: $e\n  Install adb: https://developer.android.com/studio/command-line/adb');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// iOS simulator
// ---------------------------------------------------------------------------

/// Taps inside the iOS Simulator by computing the screen offset of the
/// simulator window and dispatching a mouse click via [cliclick].
///
/// Steps:
/// 1. Locate the Simulator.app window via [CGWindowList] (no AX permission needed).
/// 2. Compute the screen coordinate: win_origin + _kSimTitleBarHeight + sim_coord.
/// 3. Invoke `cliclick c:SCREEN_X,SCREEN_Y`.
///
/// The [_kSimTitleBarHeight] accounts for the macOS window title bar rendered
/// above the device content inside the Simulator window.
Future<int> _tapIosSimulator({required String? deviceId, required double x, required double y}) async {
  final winOffset = await _simulatorWindowOffset(deviceId);
  if (winOffset == null) {
    stderr.writeln(
      'ERROR: Could not locate the iOS Simulator window.\n'
      '  Make sure the Simulator app is open and the device is booted.',
    );
    return 1;
  }

  final screenX = (winOffset.$1 + x).round();
  final screenY = (winOffset.$2 + y).round();
  return _cliclick(screenX: screenX, screenY: screenY, label: 'ios-simulator');
}

/// Returns the (screenX, screenY) of the top-left corner of the device
/// *content* area inside the Simulator window (i.e. window origin + title bar
/// height + any top device bezel that Simulator adds above the device screen).
///
/// Uses the same CGWindowList approach as [screenshot.dart] — no AX permission
/// required.
Future<(double, double)?> _simulatorWindowOffset(String? deviceId) async {
  // We need to find the correct Simulator window when multiple sims are booted.
  // The window title matches the device name from simctl.
  String? targetTitle;
  if (deviceId != null) {
    try {
      final result = await Process.run('xcrun', [
        'simctl',
        'list',
        'devices',
        'booted',
        '--json',
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Simple parse: find the udid and extract the name
        final udidPattern = RegExp('"udid" : "${RegExp.escape(deviceId)}"');
        if (udidPattern.hasMatch(output)) {
          // Walk backwards to find the "name" key in the same object
          final nameMatch = RegExp(r'"name"\s*:\s*"([^"]+)"').allMatches(output);
          final udidPos = udidPattern.firstMatch(output)?.start ?? -1;
          if (udidPos > 0) {
            // Find the name that precedes this udid entry
            String? closest;
            var closestDist = double.maxFinite.toInt();
            for (final m in nameMatch) {
              final dist = udidPos - m.end;
              if (dist > 0 && dist < closestDist) {
                closestDist = dist;
                closest = m.group(1);
              }
            }
            targetTitle = closest;
          }
        }
      }
    } catch (_) {}
  }

  final swiftArgs = targetTitle != null
      ? [
          '-e',
          '''
import Cocoa
let target = "$targetTitle"
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [NSDictionary] else { exit(1) }
for w in list {
    guard let owner = w[kCGWindowOwnerName] as? String, owner == "Simulator" else { continue }
    let title = w[kCGWindowName] as? String ?? ""
    if !target.isEmpty && !title.contains(target) { continue }
    guard let bounds = w[kCGWindowBounds] as? NSDictionary,
          let wx = bounds["X"] as? Double,
          let wy = bounds["Y"] as? Double else { continue }
    print("\\(wx) \\(wy)")
    exit(0)
}
exit(1)
''',
        ]
      : [
          '-e',
          '''
import Cocoa
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [NSDictionary] else { exit(1) }
for w in list {
    guard let owner = w[kCGWindowOwnerName] as? String, owner == "Simulator" else { continue }
    guard let bounds = w[kCGWindowBounds] as? NSDictionary,
          let wx = bounds["X"] as? Double,
          let wy = bounds["Y"] as? Double else { continue }
    print("\\(wx) \\(wy)")
    exit(0)
}
exit(1)
''',
        ];

  try {
    final result = await Process.run('swift', swiftArgs);
    if (result.exitCode != 0) return null;
    final parts = (result.stdout as String).trim().split(' ');
    if (parts.length < 2) return null;
    final wx = double.tryParse(parts[0]);
    final wy = double.tryParse(parts[1]);
    if (wx == null || wy == null) return null;
    // Add the macOS title bar + top device chrome so that coordinate (0,0)
    // maps to the very top-left of the device screen rendered by Simulator.
    return (wx + _kSimContentOffsetX, wy + _kSimContentOffsetY);
  } catch (_) {
    return null;
  }
}

/// Horizontal distance (pts) from the left edge of the Simulator window to the
/// left edge of the device screen content.
///
/// Measured empirically: for a standard iPhone simulator at the default window
/// size the left bezel is approximately 24 logical points.
const _kSimContentOffsetX = 24.0;

/// Vertical distance (pts) from the top edge of the Simulator window to the
/// top of the device screen content.
///
/// Breakdown: macOS window title bar (≈28 pts) + Simulator's top device chrome
/// (≈16 pts) = 44 pts total. Measured empirically on macOS 15 / Xcode 16.
const _kSimContentOffsetY = 44.0;

// ---------------------------------------------------------------------------
// iOS physical
// ---------------------------------------------------------------------------

/// Taps a physical iOS device via `idb ui tap X Y`.
///
/// Requires `idb_companion` from Meta (https://github.com/facebook/idb).
/// Install: `brew install facebook/fb/idb-companion` and `pip3 install fb-idb`.
Future<int> _tapIosPhysical({required double x, required double y}) async {
  // Check if idb is on PATH
  final which = await Process.run('which', ['idb']);
  if (which.exitCode != 0) {
    stderr.writeln(
      'ERROR: native-tap on physical iOS requires idb.\n'
      '  Install: brew install facebook/fb/idb-companion && pip3 install fb-idb\n'
      '  Docs: https://fbidb.io',
    );
    return 1;
  }

  try {
    final result = await Process.run('idb', [
      'ui',
      'tap',
      x.toInt().toString(),
      y.toInt().toString(),
    ]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      stderr.writeln('ERROR: idb ui tap failed: $details');
      return 1;
    }
    stdout.writeln('NATIVE_TAPPED=ios-physical X=${x.toInt()} Y=${y.toInt()}');
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run idb: $e');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// macOS
// ---------------------------------------------------------------------------

/// Taps within a macOS Flutter app window by computing the screen coordinate
/// from the stored PID and dispatching via [cliclick].
///
/// Finds the app window using the same CGWindowList approach as [screenshot.dart],
/// then adds the macOS window title bar height so coordinate (0,0) maps to the
/// top-left of the Flutter rendering surface.
Future<int> _tapMacOs({required double x, required double y}) async {
  final pid = readPid();
  if (pid == null) {
    stderr.writeln(
      'ERROR: No PID in session — cannot locate macOS window. Re-launch the app.',
    );
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
  return _cliclick(screenX: screenX, screenY: screenY, label: 'macos');
}

/// Returns the (screenX, screenY) offset of the top-left of the Flutter
/// rendering surface inside the macOS app window (i.e. window origin + title
/// bar height so that coordinate (0,0) = content top-left).
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
    // Add the macOS title bar height so (0,0) = Flutter content top-left.
    return (wx, wy + _kMacOsTitleBarHeight);
  } catch (_) {
    return null;
  }
}

/// Standard macOS window title bar height in logical points.
const _kMacOsTitleBarHeight = 28.0;

// ---------------------------------------------------------------------------
// cliclick dispatch
// ---------------------------------------------------------------------------

/// Clicks at ([screenX], [screenY]) in macOS screen coordinates using `cliclick`.
///
/// `cliclick` uses `CGEvent` for mouse injection and works without Accessibility
/// permission for most app windows. Install: `brew install cliclick`.
Future<int> _cliclick({required int screenX, required int screenY, required String label}) async {
  final which = await Process.run('which', ['cliclick']);
  if (which.exitCode != 0) {
    stderr.writeln(
      'ERROR: native-tap requires cliclick on macOS/iOS simulator.\n'
      '  Install: brew install cliclick',
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
    stdout.writeln('NATIVE_TAPPED=$label X=$screenX Y=$screenY');
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run cliclick: $e');
    return 1;
  }
}

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
