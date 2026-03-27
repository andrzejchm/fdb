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
  return file.readAsStringSync().trim();
}

String? readDevice() {
  final file = File(deviceFile);
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync().trim();
  return content.isEmpty ? null : content;
}

bool isProcessAlive(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void cleanupTempFiles() {
  for (final path in [
    pidFile,
    logFile,
    vmUriFile,
    launcherScript,
    deviceFile
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
