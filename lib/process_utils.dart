import 'dart:async';
import 'dart:io';

import 'package:fdb/constants.dart';

int? readPid() {
  final file = File(pidFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return int.tryParse(content);
}

String? readVmUri() {
  final file = File(vmUriFile);
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

/// Returns true if the VM service at [uri] is reachable by opening a WebSocket
/// and waiting for the first byte (or a clean open). Times out quickly so
/// `fdb status` does not block for long when the app is truly dead.
///
/// This is used as a fallback by `fdb status` when the PID file is missing or
/// points to a dead process — a common scenario when `fdb launch` was killed by
/// an agent timeout after the app started but before `APP_STARTED` was printed.
Future<bool> isVmServiceReachable(String uri) async {
  try {
    final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 3));
    await ws.close();
    return true;
  } on TimeoutException {
    rethrow;
  } catch (_) {
    return false;
  }
}

void cleanupTempFiles() {
  for (final path in [
    pidFile,
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
