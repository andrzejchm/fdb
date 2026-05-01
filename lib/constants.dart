import 'dart:io';

/// fdb version — update this AND pubspec.yaml on every release.
const version = '1.6.0';

/// Name of the session directory created inside the Flutter project.
const sessionDirName = '.fdb';

/// The active session directory. Defaults to `<CWD>/.fdb/`.
/// [initSessionDir] overrides this for commands like `launch` that receive an
/// explicit `--project` path.
/// [resolveSessionDir] auto-locates an existing `.fdb/` by walking up the tree.
String _sessionDir = '${Directory.current.path}/$sessionDirName';

/// Override the session directory (e.g. from `--project`).
/// The path is resolved to absolute so that detached processes (launcher
/// script, log collector) can find it regardless of their CWD.
void initSessionDir(String projectPath) {
  final absolute = Directory(projectPath).absolute.path;
  _sessionDir = '$absolute/$sessionDirName';
}

/// Override the session directory from an explicit `--session-dir` flag.
/// Skips auto-resolution entirely — the caller is responsible for the path.
void initSessionDirFromPath(String sessionDirPath) {
  _sessionDir = Directory(sessionDirPath).absolute.path;
}

/// Auto-locate the session directory by walking up from [start] (defaults to
/// CWD) looking for an existing `.fdb/` directory whose PID file points at a
/// live process.
///
/// Walk stops at `$HOME` or the filesystem root, whichever comes first.
///
/// - If a live `.fdb/` is found in a *parent* of [start], logs one `INFO:`
///   line to stderr so the user knows which directory was picked.
/// - If no live `.fdb/` is found anywhere, returns `null` and leaves
///   `_sessionDir` at the CWD default so commands like `status` can handle
///   the missing-session case themselves.
///
/// Returns the resolved session-dir path, or `null` if no live session was found.
String? resolveSessionDir({Directory? start}) {
  final cwd = (start ?? Directory.current).absolute.path;
  final home = Platform.environment['HOME'] ?? '/';

  var current = Directory(cwd);

  while (true) {
    final candidate = Directory('${current.path}/$sessionDirName');
    if (candidate.existsSync()) {
      final pidPath = '${candidate.path}/fdb.pid';
      final pidFile = File(pidPath);
      bool alive;
      if (pidFile.existsSync()) {
        final raw = pidFile.readAsStringSync().trim();
        final pid = int.tryParse(raw);
        if (pid != null) {
          try {
            alive = Process.runSync('kill', ['-0', pid.toString()]).exitCode == 0;
          } catch (_) {
            alive = false;
          }
        } else {
          alive = false;
        }
      } else {
        // No PID file — only treat as a valid candidate if a vm_uri.txt
        // exists, indicating an interrupted launch that left a recoverable
        // VM service session. A bare .fdb/ with neither file is a leftover
        // directory that should not attract walk-up resolution.
        alive = File('${candidate.path}/vm_uri.txt').existsSync();
      }

      if (alive) {
        final resolved = candidate.absolute.path;
        if (resolved != Directory('$cwd/$sessionDirName').absolute.path) {
          stderr.writeln('INFO: Using session dir from ${current.path}');
        }
        _sessionDir = resolved;
        return resolved;
      }
    }

    // Stop at $HOME or filesystem root — never walk past either.
    final parent = current.parent;
    final atHome = current.absolute.path == Directory(home).absolute.path;
    final atRoot = parent.path == current.path;
    if (atHome || atRoot) break;
    current = parent;
  }

  // No live session found — keep _sessionDir at <CWD>/.fdb/ so commands like
  // `status` can handle the missing-session case themselves.
  _sessionDir = '$cwd/$sessionDirName';
  return null;
}

/// Ensure the session directory exists and return its path.
String ensureSessionDir() {
  final dir = Directory(_sessionDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return _sessionDir;
}

String get pidFile => '$_sessionDir/fdb.pid';
String get appPidFile => '$_sessionDir/fdb.app_pid';
String get logFile => '$_sessionDir/logs.txt';
String get logCollectorPidFile => '$_sessionDir/log_collector.pid';
String get logCollectorScript => '$_sessionDir/log_collector.dart';
String get vmUriFile => '$_sessionDir/vm_uri.txt';
String get launcherScript => '$_sessionDir/launcher.sh';
String get deviceFile => '$_sessionDir/device.txt';
String get platformFile => '$_sessionDir/platform.txt';
String get appIdFile => '$_sessionDir/app_id.txt';
String get defaultScreenshotPath => '$_sessionDir/screenshot.png';

const launchTimeoutSeconds = 300; // 5 minutes
const reloadTimeoutSeconds = 10;
const restartTimeoutSeconds = 10;
const killTimeoutSeconds = 10;
const pollIntervalMs = 3000;
const heartbeatIntervalSeconds = 15;
