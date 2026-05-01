import 'dart:io';

import 'package:fdb/constants.dart';

String adbExecutable = 'adb';

int? readPid() {
  final file = File(pidFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return int.tryParse(content);
}

/// Reads the app VM PID from [appPidFile] written by `fdb launch` after
/// the VM service is confirmed reachable.
///
/// Returns null if the file does not exist or its content is not a valid
/// integer (e.g. the session was created by an older fdb version).
int? readAppPid() {
  final file = File(appPidFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return int.tryParse(content);
}

String projectPathFromSessionDir() {
  return Directory(sessionDirPath).parent.path;
}

String? readVmUri() {
  final file = File(vmUriFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return content.isEmpty ? null : content;
}

int? readControllerPid() {
  final file = File(controllerPidFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return int.tryParse(content);
}

int? readControllerPort() {
  final file = File(controllerPortFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return int.tryParse(content);
}

String? readControllerToken() {
  final file = File(controllerTokenFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return content.isEmpty ? null : content;
}

String? readDevice() {
  final file = File(deviceFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return content.isEmpty ? null : content;
}

/// Stores the Flutter target platform string and emulator flag for the active
/// session. Written by `fdb launch`, read by `fdb screenshot`.
///
/// Format: `<targetPlatform> <emulator>` e.g. `ios true` or `android-arm64 false`.
void writePlatformInfo(String targetPlatform, bool emulator) {
  File(platformFile).writeAsStringSync('$targetPlatform $emulator');
}

/// Returns `(platform, emulator)` from the platform file, or null if absent.
({String platform, bool emulator})? readPlatformInfo() {
  final file = File(platformFile);
  if (!file.existsSync()) return null;
  final parts = file.readAsStringSync().trim().split(' ');
  if (parts.length < 2) return null;
  return (platform: parts[0], emulator: parts[1] == 'true');
}

/// Read the log collector PID from its PID file.
int? readLogCollectorPid() {
  final file = File(logCollectorPidFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return int.tryParse(content);
}

/// Extracts the JSON array from `flutter devices --machine` output.
///
/// Flutter may prepend non-JSON text (download progress, upgrade banners)
/// before the actual JSON array. Scans for the first `[` to find the start.
String? extractDevicesJson(String output) {
  final start = output.indexOf('[');
  if (start == -1) return null;
  final end = output.lastIndexOf(']');
  if (end == -1 || end < start) return null;
  return output.substring(start, end + 1);
}

bool isProcessAlive(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

bool isAndroidTarget() {
  final info = readPlatformInfo();
  if (info == null) return false;
  return info.platform.toLowerCase().startsWith('android');
}

bool isAndroidAppPidAlive(int pid) {
  if (!isAndroidTarget()) return false;
  final device = readDevice();
  if (device == null || device.isEmpty) return false;
  final appId = readAppId();
  try {
    if (appId != null && appId.isNotEmpty) {
      final result = Process.runSync(adbExecutable, [
        '-s',
        device,
        'shell',
        'pidof',
        appId,
      ]);
      if (result.exitCode == 0) {
        final pids = (result.stdout as String)
            .trim()
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .map(int.tryParse)
            .whereType<int>();
        if (pids.contains(pid)) return true;
      }
    }
  } catch (_) {
    // Fall back to ps parsing below.
  }

  try {
    final result = Process.runSync(adbExecutable, [
      '-s',
      device,
      'shell',
      'ps',
      '-A',
    ]);
    if (result.exitCode != 0) return false;
    final pidText = pid.toString();
    final lines = (result.stdout as String).split('\n').where((line) => line.trim().isNotEmpty);
    for (final line in lines) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      if (fields[1] == pidText) return true;
    }
  } catch (_) {
    return false;
  }

  return false;
}

/// Reads the persisted app bundle id / package name from `.fdb/app_id.txt`.
///
/// Returns null if the file does not exist or is empty.
String? readAppId() {
  final file = File(appIdFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return content.isEmpty ? null : content;
}

/// Persists [appId] to `.fdb/app_id.txt` so later commands (e.g. crash-report)
/// can use it without requiring `--app-id`.
void writeAppId(String appId) {
  File(appIdFile).writeAsStringSync(appId);
}

void cleanupTempFiles() {
  for (final path in [
    pidFile,
    appPidFile,
    controllerPidFile,
    controllerPortFile,
    controllerTokenFile,
    logFile,
    logCollectorPidFile,
    logCollectorScript,
    vmUriFile,
    launcherScript,
    deviceFile,
    platformFile,
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
