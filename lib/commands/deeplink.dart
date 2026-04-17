import 'dart:io';

import 'package:fdb/process_utils.dart';

/// Opens a deep link URL on the connected device (Android or iOS simulator).
Future<int> runDeeplink(List<String> args) async {
  String? url;

  for (var i = 0; i < args.length; i++) {
    // First positional argument is the URL
    if (!args[i].startsWith('-')) {
      url = args[i];
    }
  }

  if (url == null) {
    stderr.writeln('ERROR: No URL provided');
    return 1;
  }

  // Use the session device ID to determine platform instead of probing
  // connected devices — avoids misdetecting Android when both platforms
  // are connected but the session is on iOS (or vice versa).
  final deviceId = readDevice();
  if (deviceId == null) {
    stderr.writeln('ERROR: No active fdb session found. Run fdb launch first.');
    return 1;
  }

  final isSimulator = await _isIosSimulatorId(deviceId);
  if (isSimulator) {
    return _openIos(url);
  }

  final isAndroid = await _isAndroidDeviceId(deviceId);
  if (isAndroid) {
    return _openAndroid(url);
  }

  stderr.writeln(
      'ERROR: Deep links are only supported on Android devices and iOS simulators');
  return 1;
}

Future<int> _openAndroid(String url) async {
  final result = await Process.run('adb', [
    'shell',
    'am',
    'start',
    '-W',
    '-a',
    'android.intent.action.VIEW',
    '-c',
    'android.intent.category.BROWSABLE',
    '-d',
    url,
  ]);

  final stdoutStr = result.stdout as String;
  final stderrStr = result.stderr as String;

  if (result.exitCode != 0 || stdoutStr.contains('Error:')) {
    final details = stderrStr.isNotEmpty ? stderrStr.trim() : stdoutStr.trim();
    stderr.writeln('ERROR: Failed to open deep link: $details');
    return 1;
  }

  stdout.writeln('DEEPLINK_OPENED=$url');
  return 0;
}

Future<int> _openIos(String url) async {
  // Warn about Universal Links potentially opening Safari
  if (url.startsWith('http://') || url.startsWith('https://')) {
    stderr.writeln(
      'WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator',
    );
  }

  final result =
      await Process.run('xcrun', ['simctl', 'openurl', 'booted', url]);

  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    stderr.writeln('ERROR: Failed to open deep link: $details');
    return 1;
  }

  stdout.writeln('DEEPLINK_OPENED=$url');
  return 0;
}

/// Returns true if [deviceId] is a booted iOS simulator UUID.
Future<bool> _isIosSimulatorId(String deviceId) async {
  try {
    final result =
        await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted']);
    return (result.stdout as String).contains(deviceId);
  } catch (_) {
    return false;
  }
}

/// Returns true if [deviceId] is an Android device connected via adb.
Future<bool> _isAndroidDeviceId(String deviceId) async {
  try {
    final result = await Process.run('adb', ['devices']);
    final output = result.stdout as String;
    return output.split('\n').any(
          (l) => l.startsWith(deviceId) && l.contains('\tdevice'),
        );
  } catch (_) {
    return false;
  }
}
