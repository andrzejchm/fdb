import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/devices/devices_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/devices/devices_models.dart';

/// Runs `flutter devices --machine` and returns a structured result.
///
/// Never throws; never writes to stdio. All error conditions are represented
/// as distinct [DevicesResult] subtypes.
Future<DevicesResult> listDevices(DevicesInput _) async {
  final ProcessResult result;
  result = await Process.run('flutter', ['devices', '--machine']);

  if (result.exitCode != 0) {
    return DevicesFlutterFailed(result.stderr as String);
  }

  final json = extractDevicesJson(result.stdout as String);
  if (json == null) return const DevicesNotFound();

  final List<dynamic> raw;
  try {
    raw = jsonDecode(json) as List<dynamic>;
  } catch (e) {
    return DevicesParseFailed(e.toString());
  }

  if (raw.isEmpty) return const DevicesNotFound();

  final devices = <DeviceInfo>[];
  final skipped = <Map<String, dynamic>>[];

  for (final entry in raw) {
    final d = entry as Map<String, dynamic>;
    final id = d['id'] as String?;
    final name = d['name'] as String?;
    final platform = d['targetPlatform'] as String?;

    if (id == null || name == null || platform == null) {
      skipped.add(d);
      continue;
    }

    final emulator = d['emulator'] as bool? ?? false;
    devices.add((id: id, name: name, platform: platform, emulator: emulator));
  }

  return DevicesListed(devices: devices, skippedRaw: skipped);
}
