import 'dart:io';

import 'package:fdb/src/controller/pid_liveness.dart';

/// Name of the session directory created inside the Flutter project.
const sessionDirName = '.fdb';

/// The active session directory. Defaults to `<CWD>/.fdb/`.
String _sessionDir = '${Directory.current.path}/$sessionDirName';

/// Override the session directory from a Flutter project path.
void initSessionDir(String projectPath) {
  final absolute = Directory(projectPath).absolute.path;
  _sessionDir = '$absolute/$sessionDirName';
}

/// Override the session directory from an explicit `--session-dir` flag.
void initSessionDirFromPath(String sessionDirPath) {
  _sessionDir = Directory(sessionDirPath).absolute.path;
}

/// Auto-locate the session directory by walking up from [start].
String? resolveSessionDir({Directory? start}) {
  final cwd = (start ?? Directory.current).absolute.path;
  final home = Platform.environment['HOME'] ?? '/';

  var current = Directory(cwd);

  while (true) {
    final candidate = Directory('${current.path}/$sessionDirName');
    if (candidate.existsSync()) {
      final alive = _hasLiveSessionState(candidate.path);

      if (alive) {
        final resolved = candidate.absolute.path;
        if (resolved != Directory('$cwd/$sessionDirName').absolute.path) {
          stderr.writeln('INFO: Using session dir from ${current.path}');
        }
        _sessionDir = resolved;
        return resolved;
      }
    }

    final parent = current.parent;
    final atHome = current.absolute.path == Directory(home).absolute.path;
    final atRoot = parent.path == current.path;
    if (atHome || atRoot) break;
    current = parent;
  }

  _sessionDir = '$cwd/$sessionDirName';
  return null;
}

bool _hasLiveSessionState(String candidatePath) {
  for (final path in [
    '$candidatePath/controller.pid',
    '$candidatePath/fdb.app_pid',
    '$candidatePath/fdb.pid',
  ]) {
    if (_isPidFileAlive(path)) {
      return true;
    }
  }

  return File('$candidatePath/vm_uri.txt').existsSync();
}

bool _isPidFileAlive(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return false;
  }

  final pid = int.tryParse(file.readAsStringSync().trim());
  if (pid == null) {
    return false;
  }

  return isProcessAlive(pid);
}

/// Ensure the session directory exists and return its path.
String ensureSessionDir() {
  final dir = Directory(_sessionDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return _sessionDir;
}

String get sessionDirPath => _sessionDir;

String get pidFile => '$_sessionDir/fdb.pid';
String get appPidFile => '$_sessionDir/fdb.app_pid';
String get controllerPidFile => '$_sessionDir/controller.pid';
String get controllerPortFile => '$_sessionDir/controller.port';
String get controllerTokenFile => '$_sessionDir/controller.token';
String get logFile => '$_sessionDir/logs.txt';
String get logCollectorPidFile => '$_sessionDir/log_collector.pid';
String get logCollectorScript => '$_sessionDir/log_collector.dart';
String get vmUriFile => '$_sessionDir/vm_uri.txt';
String get launcherScript => '$_sessionDir/launcher.sh';
String get deviceFile => '$_sessionDir/device.txt';
String get platformFile => '$_sessionDir/platform.txt';
String get appIdFile => '$_sessionDir/app_id.txt';
String get defaultScreenshotPath => '$_sessionDir/screenshot.png';
