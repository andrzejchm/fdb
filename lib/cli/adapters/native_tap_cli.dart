import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/native_tap.dart';

/// CLI adapter for `fdb native-tap`.
///
/// Accepts:
///   `--x <n>`      X coordinate
///   `--y <n>`      Y coordinate
///   `--at <x,y>`   Coordinate shorthand (e.g. 200,400)
Future<int> runNativeTapCli(List<String> args) {
  final parser = ArgParser()
    ..addOption('x')
    ..addOption('y')
    ..addOption('at');

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

  // Validate coordinate completeness
  if ((x == null) != (y == null)) {
    stderr.writeln('ERROR: Both --x and --y are required together.');
    return 1;
  }

  if (x == null || y == null) {
    stderr.writeln(
      'ERROR: No coordinates provided. Use --at x,y or --x <x> --y <y>.\n'
      '  Usage: fdb native-tap --at 200,400',
    );
    return 1;
  }

  final result = await nativeTap((x: x, y: y));
  return _format(result);
}

int _format(NativeTapResult result) {
  switch (result) {
    case NativeTapAndroid(:final x, :final y):
      stdout.writeln('NATIVE_TAPPED=android X=$x Y=$y');
      return 0;
    case NativeTapIosSimulator(:final x, :final y):
      stdout.writeln('NATIVE_TAPPED=ios-simulator X=$x Y=$y');
      return 0;
    case NativeTapNoSession():
      stderr.writeln('ERROR: No active fdb session found. Run fdb launch first.');
      return 1;
    case NativeTapPhysicalIosUnsupported(:final x, :final y):
      stderr.writeln(
        'ERROR: native-tap is not yet supported on physical iOS devices.\n'
        '  Use `fdb tap --at $x,$y` instead — it performs in-process tap\n'
        '  injection via fdb_helper, which reaches UIAlertController and other\n'
        '  in-app native overlays on physical iOS devices.\n'
        '\n'
        '  Why: out-of-process tap injection on physical iOS requires\n'
        '  WebDriverAgent (a signed XCUITest runner installed on the device).\n'
        '  Tracking implementation in beads issue fdb-6sz.',
      );
      return 1;
    case NativeTapMacosUnsupported(:final x, :final y):
      stderr.writeln(
        'ERROR: native-tap is not supported on macOS.\n'
        '  Use `fdb tap --at $x,$y` instead — it performs in-process tap injection\n'
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
    case NativeTapAdbExecutionFailed(:final error):
      stderr.writeln(
        'ERROR: Failed to run adb: $error\n'
        '  Install adb: https://developer.android.com/studio/command-line/adb',
      );
      return 1;
    case NativeTapIndigoFailed(:final details):
      stderr.writeln('ERROR: IndigoHID tap failed:\n$details');
      return 1;
    case NativeTapIndigoUnexpectedOutput(:final output):
      stderr.writeln('ERROR: IndigoHID tap produced unexpected output: $output');
      return 1;
    case NativeTapSwiftFailed(:final error):
      stderr.writeln('ERROR: Failed to run swift for IndigoHID tap: $error');
      return 1;
  }
}
