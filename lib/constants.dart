import 'dart:io';

/// Base directory for all fdb state
String get fdbHome {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  return '$home/.fdb';
}

/// Device cache file path
String get deviceCachePath => '$fdbHome/devices.json';

/// Session directory for a given device ID
String sessionDir(String deviceId) {
  final hash = _shortHash(deviceId);
  return '$fdbHome/sessions/$hash';
}

/// Session state file for a given device ID
String sessionFile(String deviceId) => '${sessionDir(deviceId)}/session.json';

/// Log file for a given device ID
String logPath(String deviceId) => '${sessionDir(deviceId)}/logs.txt';

/// Launcher script for a given device ID
String launcherPath(String deviceId) => '${sessionDir(deviceId)}/launcher.sh';

/// Default screenshot path for a given device ID
String screenshotPath(String deviceId) =>
    '${sessionDir(deviceId)}/screenshot.png';

const launchTimeoutSeconds = 300;
const reloadTimeoutSeconds = 10;
const restartTimeoutSeconds = 10;
const killTimeoutSeconds = 10;
const pollIntervalMs = 3000;
const heartbeatIntervalSeconds = 15;

/// Deterministic hash of [input] — same input always produces same output.
/// Uses two rounds of djb2 with different seeds combined for 16 hex digits.
String _shortHash(String input) {
  var h1 = 5381;
  var h2 = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    h1 = ((h1 << 5) + h1 + c) & 0xFFFFFFFF;
    h2 = ((h2 ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h1.toRadixString(16).padLeft(8, '0') +
      h2.toRadixString(16).padLeft(8, '0');
}
