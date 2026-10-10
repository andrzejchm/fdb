import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/cli/adapters/tap_cli.dart';
import 'package:fdb/core/commands/native_tap/native_tap.dart';

/// Most labels listed in the no-match error.
const _maxVisibleLabels = 20;

/// CLI adapter for `fdb native-tap`.
///
/// Accepts:
///   `--x <n>`          X coordinate
///   `--y <n>`          Y coordinate
///   `--at <x,y>`       Coordinate shorthand (e.g. 200,400)
///   `--logical`        Coordinates are Flutter logical pixels (Android scales them)
///   `--text <label>`   Tap the native element with this label (Android)
///   `--index <n>`      Which `--text` match to tap (0-based)
///   `--timeout <secs>` How long `--text` waits for a match (default: 5)
Future<int> runNativeTapCli(List<String> args) {
  final parser = ArgParser()
    ..addOption('x')
    ..addOption('y')
    ..addOption('at')
    ..addFlag(
      'logical',
      negatable: false,
      help: 'Treat --at/--x/--y as Flutter logical pixels. Android multiplies them by the device pixel ratio; '
          'on the iOS simulator coordinates are already points, so it changes nothing.',
    )
    ..addOption(
      'text',
      help: 'Tap the native element whose text, content-desc or resource-id is this (Android only).',
    )
    ..addOption('index', help: 'With --text: which match to tap, 0-based, in screen order.')
    ..addOption('timeout', defaultsTo: '5', help: 'With --text: seconds to wait for a match.');

  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  // Parse --x
  double? x;
  if (results['x'] != null) {
    final rawX = results['x'] as String;
    x = double.tryParse(rawX);
    if (x == null) {
      stderr.writeln('ERROR: Invalid value for --x: $rawX');
      return 1;
    }
  }

  // Parse --y
  double? y;
  if (results['y'] != null) {
    final rawY = results['y'] as String;
    y = double.tryParse(rawY);
    if (y == null) {
      stderr.writeln('ERROR: Invalid value for --y: $rawY');
      return 1;
    }
  }

  // Parse --at
  if (results['at'] != null) {
    final rawAt = results['at'] as String;
    final parsed = parseXY(rawAt);
    if (parsed == null) {
      stderr.writeln(
        'ERROR: Invalid --at value: "$rawAt". Expected format: x,y (e.g. 200,400).',
      );
      return 1;
    }
    x = parsed.$1;
    y = parsed.$2;
  }

  // Parse --index
  int? index;
  final rawIndex = results.option('index');
  if (rawIndex != null) {
    index = int.tryParse(rawIndex);
    if (index == null || index < 0) {
      stderr.writeln('ERROR: Invalid value for --index: $rawIndex');
      return 1;
    }
  }

  // Parse --timeout
  final rawTimeout = results.option('timeout')!;
  final timeoutSeconds = int.tryParse(rawTimeout);
  if (timeoutSeconds == null || timeoutSeconds < 0) {
    stderr.writeln('ERROR: Invalid value for --timeout: $rawTimeout');
    return 1;
  }

  final text = results.option('text');
  final logical = results.flag('logical');
  final hasCoords = x != null || y != null;

  if (text != null) {
    if (hasCoords) {
      stderr.writeln('ERROR: --text cannot be combined with --at or --x/--y.');
      return 1;
    }
    if (logical) {
      stderr.writeln('ERROR: --logical only applies to --at or --x/--y, not --text.');
      return 1;
    }
    if (text.trim().isEmpty) {
      stderr.writeln('ERROR: --text must not be empty.');
      return 1;
    }
  } else {
    if (index != null) {
      stderr.writeln('ERROR: --index only applies to --text.');
      return 1;
    }

    // Validate coordinate completeness
    if ((x == null) != (y == null)) {
      stderr.writeln('ERROR: Both --x and --y are required together.');
      return 1;
    }

    if (x == null || y == null) {
      stderr.writeln(
        'ERROR: No coordinates provided. Use --at x,y or --x <x> --y <y>, or --text <label> on Android.\n'
        '  Usage: fdb native-tap --at 200,400',
      );
      return 1;
    }
  }

  final result = await nativeTap((
    x: x,
    y: y,
    text: text,
    index: index,
    timeoutSeconds: timeoutSeconds,
    logical: logical,
  ));
  return formatNativeTapResult(result);
}

/// Writes the stdout tokens / stderr lines for [result] and returns the exit code.
int formatNativeTapResult(NativeTapResult result) {
  switch (result) {
    case NativeTapAndroid(:final x, :final y, :final text):
      final textSuffix = text != null ? ' TEXT="$text"' : '';
      stdout.writeln('NATIVE_TAPPED=android X=$x Y=$y$textSuffix');
      return 0;
    case NativeTapIosSimulator(:final x, :final y):
      stdout.writeln('NATIVE_TAPPED=ios-simulator X=$x Y=$y');
      return 0;
    case NativeTapIosSimulatorFallback(:final x, :final y, :final reason, :final tapResult):
      stderr.writeln(
        'WARNING: iOS simulator HID tap unavailable ($reason); fell back to in-process tap '
        '(UIApplication.sendEvent), which cannot reach SpringBoard system dialogs.',
      );
      final tapExitCode = formatTapResult(tapResult);
      if (tapExitCode != 0) return tapExitCode;
      stdout.writeln('NATIVE_TAPPED=ios-simulator X=$x Y=$y');
      return 0;
    case NativeTapIosSimulatorOutOfBounds(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case NativeTapIosSimulatorOrientationUnknown(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case NativeTapIosSimulatorFailed(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
    case NativeTapTextUnsupportedOnIosSimulator():
      stderr.writeln('ERROR: native-tap --text is not supported on the iOS simulator yet; use --at x,y');
      return 1;
    case NativeTapNoSession():
      stderr.writeln('ERROR: No active fdb session found. Run fdb launch first.');
      return 1;
    case NativeTapPhysicalIosUnsupported(:final x, :final y):
      final at = _atArg(x, y);
      stderr.writeln(
        'ERROR: native-tap is not yet supported on physical iOS devices.\n'
        '  Use `fdb tap --at $at` instead — it performs in-process tap\n'
        '  injection via fdb_helper, which reaches UIAlertController and other\n'
        '  in-app native overlays on physical iOS devices.\n'
        '\n'
        '  Why: out-of-process tap injection on physical iOS requires\n'
        '  WebDriverAgent (a signed XCUITest runner installed on the device).\n'
        '  Tracking implementation in beads issue fdb-6sz.',
      );
      return 1;
    case NativeTapMacosUnsupported(:final x, :final y):
      final at = _atArg(x, y);
      stderr.writeln(
        'ERROR: native-tap is not supported on macOS.\n'
        '  Use `fdb tap --at $at` instead — it performs in-process tap injection\n'
        '  via fdb_helper and does not require Accessibility permission.\n'
        '\n'
        '  Why: cross-process tap injection on macOS requires Accessibility\n'
        '  permission, which is only grantable to signed .app bundles. Homebrew\n'
        '  CLIs are unsigned and cannot be added to the Accessibility list.',
      );
      return 1;
    case NativeTapPlatformUnsupported(:final platform):
      stderr.writeln('ERROR: native-tap is not supported on platform "$platform".');
      return 1;
    case NativeTapAdbFailed(:final details):
      stderr.writeln('ERROR: adb input tap failed: $details');
      return 1;
    case NativeTapInputInjectionBlocked(:final details):
      stderr.writeln(
        'ERROR: Android blocked input injection (INJECT_EVENTS). Enable it in Developer options: '
        'Xiaomi/HyperOS "USB debugging (Security settings)", OPPO/OnePlus/Realme "Disable permission monitoring", '
        'vivo "USB Security Permissions".\n'
        '  adb said: ${_firstLine(details)}',
      );
      return 1;
    case NativeTapNoMatch(:final query, :final visibleLabels):
      stderr.writeln('ERROR: No native element matching "$query". Visible labels: ${_labelList(visibleLabels)}');
      return 1;
    case NativeTapAmbiguous(:final query, :final candidates):
      final lines = [
        for (var i = 0; i < candidates.length; i++)
          '  [$i] "${candidates[i].label}" at ${candidates[i].x},${candidates[i].y}',
      ];
      stderr.writeln(
        'ERROR: Found ${candidates.length} native elements matching "$query". '
        'Use --index to specify which one (0-based):\n'
        '${lines.join('\n')}',
      );
      return 1;
    case NativeTapIndexOutOfRange(:final query, :final index, :final count):
      stderr.writeln(
        'ERROR: --index $index is out of range: found $count native element${count == 1 ? '' : 's'} '
        'matching "$query" (0-based).',
      );
      return 1;
    case NativeTapUiDumpFailed(:final reason):
      final idle = reason.contains('idle state');
      stderr.writeln(
        'ERROR: Could not read the Android UI hierarchy (uiautomator dump): $reason'
        '${idle ? '\n  uiautomator needs the screen to stop animating. Retry, or tap by coordinates with --at x,y.' : ''}',
      );
      return 1;
    case NativeTapDevicePixelRatioUnavailable(:final reason):
      stderr.writeln('ERROR: Could not determine the device pixel ratio for --logical: $reason');
      return 1;
    case NativeTapAdbExecutionFailed(:final error):
      stderr.writeln(
        'ERROR: Failed to run adb: $error\n'
        '  Install adb: https://developer.android.com/studio/command-line/adb',
      );
      return 1;
  }
}

String _atArg(double? x, double? y) => x != null && y != null ? '$x,$y' : 'x,y';

String _firstLine(String s) {
  final lines = s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  return lines.isEmpty ? '(no output)' : lines.first;
}

String _labelList(List<String> labels) {
  if (labels.isEmpty) return 'none';
  final shown = labels.take(_maxVisibleLabels).map((l) => '"$l"').join(', ');
  final more = labels.length - _maxVisibleLabels;
  return more > 0 ? '$shown, ... ($more more)' : shown;
}
