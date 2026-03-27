import 'dart:convert';
import 'dart:io';

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

  final json = _extractJson(result.stdout as String);
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
    final id = d['id'] as String;
    final name = d['name'] as String;
    final platform = d['targetPlatform'] as String;
    final emulator = d['emulator'] as bool;
    stdout.writeln(
      'DEVICE_ID=$id NAME=$name PLATFORM=$platform EMULATOR=$emulator',
    );
  }
  return 0;
}

/// Extracts the JSON array from `flutter devices --machine` output.
///
/// Flutter may prepend non-JSON text (download progress, upgrade banners)
/// before the actual JSON array. We scan for the first `[` to find the
/// array start.
String? _extractJson(String output) {
  final start = output.indexOf('[');
  if (start == -1) return null;
  // Find the matching closing bracket from the end
  final end = output.lastIndexOf(']');
  if (end == -1 || end < start) return null;
  return output.substring(start, end + 1);
}
