import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/process_utils.dart';

/// Lists connected devices by running `flutter devices --machine` and
/// emitting one KEY=VALUE line per device.
Future<int> runDevices(List<String> args) async {
  final result = await Process.run('flutter', [
    'devices',
    '--machine',
  ]);

  if (result.exitCode != 0) {
    stderr.writeln('ERROR: flutter devices failed: ${result.stderr}');
    return 1;
  }

  final json = extractDevicesJson(result.stdout as String);
  if (json == null) {
    stderr.writeln('ERROR: No devices found');
    return 1;
  }

  final List<dynamic> devices;
  try {
    devices = jsonDecode(json) as List<dynamic>;
  } catch (e) {
    stderr.writeln('ERROR: Failed to parse flutter devices output: $e');
    return 1;
  }

  if (devices.isEmpty) {
    stderr.writeln('ERROR: No devices found');
    return 1;
  }

  for (final device in devices) {
    final d = device as Map<String, dynamic>;
    final id = d['id'] as String?;
    final name = d['name'] as String?;
    final platform = d['targetPlatform'] as String?;
    if (id == null || name == null || platform == null) {
      stderr.writeln(
        'WARNING: Skipping device with missing required fields: $d',
      );
      continue;
    }
    final emulator = d['emulator'] as bool? ?? false;
    stdout.writeln(
      'DEVICE_ID=$id NAME=$name PLATFORM=$platform EMULATOR=$emulator',
    );
  }
  return 0;
}
