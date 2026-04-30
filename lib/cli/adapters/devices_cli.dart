import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/devices/devices.dart';

/// CLI adapter for `fdb devices`.
///
/// Output contract — one line per device on stdout:
///
/// ```
///   DEVICE_ID=<id> NAME=<name> PLATFORM=<platform> EMULATOR=<bool> CONNECTED=<bool>
/// ```
///
/// With `--connected-only` only reachable devices are printed. For iOS
/// physical devices reachability is checked via `xcrun devicectl`; when
/// `xcrun` is unavailable all iOS devices pass through (backward-compatible).
///
/// Errors are written to stderr prefixed with `ERROR:` or `WARNING:`.
Future<int> runDevicesCli(List<String> args) {
  final parser = ArgParser()
    ..addFlag(
      'connected-only',
      abbr: 'c',
      negatable: false,
      help: 'Only list devices that are currently reachable',
    );
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final connectedOnly = results['connected-only'] as bool;
  final result = await listDevices((connectedOnly: connectedOnly));
  return _format(result);
}

int _format(DevicesResult result) {
  switch (result) {
    case DevicesFlutterFailed(:final stderrText):
      stderr.writeln('ERROR: flutter devices failed: $stderrText');
      return 1;
    case DevicesNotFound():
      stderr.writeln('ERROR: No devices found');
      return 1;
    case DevicesParseFailed(:final error):
      stderr.writeln('ERROR: Failed to parse flutter devices output: $error');
      return 1;
    case DevicesListed(:final devices, :final skippedRaw):
      for (final raw in skippedRaw) {
        stderr.writeln(
          'WARNING: Skipping device with missing required fields: $raw',
        );
      }
      if (devices.isEmpty) {
        stderr.writeln('ERROR: No devices found');
        return 1;
      }
      for (final d in devices) {
        stdout.writeln(
          'DEVICE_ID=${d.id} NAME=${d.name} PLATFORM=${d.platform} EMULATOR=${d.emulator} CONNECTED=${d.connected}',
        );
      }
      return 0;
  }
}
