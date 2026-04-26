import 'dart:io';

/// fdb version — update this AND pubspec.yaml on every release.
const version = '1.2.0';

/// Name of the session directory created inside the Flutter project.
const sessionDirName = '.fdb';

/// The active session directory. Defaults to `<CWD>/.fdb/`.
/// [initSessionDir] overrides this for commands like `launch` that receive an
/// explicit `--project` path.
String _sessionDir = '${Directory.current.path}/$sessionDirName';

/// Override the session directory (e.g. from `--project`).
/// The path is resolved to absolute so that detached processes (launcher
/// script, log collector) can find it regardless of their CWD.
void initSessionDir(String projectPath) {
  final absolute = Directory(projectPath).absolute.path;
  _sessionDir = '$absolute/$sessionDirName';
}

/// Ensure the session directory exists and return its path.
String ensureSessionDir() {
  final dir = Directory(_sessionDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return _sessionDir;
}

String get pidFile => '$_sessionDir/fdb.pid';
String get logFile => '$_sessionDir/logs.txt';
String get logCollectorPidFile => '$_sessionDir/log_collector.pid';
String get logCollectorScript => '$_sessionDir/log_collector.dart';
String get vmUriFile => '$_sessionDir/vm_uri.txt';
String get launcherScript => '$_sessionDir/launcher.sh';
String get deviceFile => '$_sessionDir/device.txt';
String get platformFile => '$_sessionDir/platform.txt';
String get defaultScreenshotPath => '$_sessionDir/screenshot.png';

const launchTimeoutSeconds = 300; // 5 minutes
const reloadTimeoutSeconds = 10;
const restartTimeoutSeconds = 10;
const killTimeoutSeconds = 10;
const pollIntervalMs = 3000;
const heartbeatIntervalSeconds = 15;
