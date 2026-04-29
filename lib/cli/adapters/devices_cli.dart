import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/devices/devices.dart';

/// CLI adapter for `fdb devices`. Accepts no flags; emits one line per
/// device:
///
/// ```
///   DEVICE_ID=<id> NAME=<name> PLATFORM=<platform> EMULATOR=<bool>
/// ```
///
/// Errors are written to stderr prefixed with `ERROR:` or `WARNING:`.
Future<int> runDevicesCli(List<String> args) =>
    runCliAdapter(ArgParser(), args, _execute);

Future<int> _execute(ArgResults _) async {
  final result = await listDevices(());
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
      for (final d in devices) {
        stdout.writeln(
          'DEVICE_ID=${d.id} NAME=${d.name} PLATFORM=${d.platform} EMULATOR=${d.emulator}',
        );
      }
      return 0;
  }
}
