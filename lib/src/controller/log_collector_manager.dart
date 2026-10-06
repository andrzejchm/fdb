import 'dart:io';
import 'dart:isolate';

import 'package:fdb/src/controller/session.dart';
import 'package:fdb/src/controller/process_utils.dart';

typedef ControllerLogSink = void Function(String line);

class LogCollectorManager {
  LogCollectorManager({required ControllerLogSink logWarning}) : _logWarning = logWarning;

  final ControllerLogSink _logWarning;
  String? _vmUri;

  /// PID of the collector this manager started. Tracked in memory so [stop]
  /// still finds it if the PID file was removed or overwritten.
  int? _pid;

  Future<void> start(String wsUri) async {
    final existingCollectorPid = _pid;
    if (_vmUri == wsUri && existingCollectorPid != null && isProcessAlive(existingCollectorPid)) {
      return;
    }

    final collectorEntrypoint = await _resolveEntrypoint();
    if (collectorEntrypoint == null) {
      _logWarning(
        'WARNING: Log collector entrypoint not found; developer.log() events may be missing',
      );
      return;
    }

    await stop();
    try {
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          collectorEntrypoint,
          wsUri,
          logFile,
          logCollectorPidFile,
        ],
        mode: ProcessStartMode.detached,
      );
      _pid = process.pid;
      // Written here as well as by the collector itself, so `fdb kill` can
      // find it even before the collector has booted.
      File(logCollectorPidFile).writeAsStringSync('${process.pid}');
      _vmUri = wsUri;
    } catch (e) {
      _logWarning('WARNING: Log collector failed to start: $e');
    }
  }

  /// Stops the collector this manager started and waits for it to exit.
  ///
  /// Uses the in-memory PID rather than the PID file: by the time a replaced
  /// controller shuts down, the file may already belong to a newer session.
  Future<void> stop() async {
    final collectorPid = _pid;
    _pid = null;
    _vmUri = null;
    if (collectorPid == null) return;

    if (!await terminateProcess(collectorPid, timeout: const Duration(seconds: 3))) {
      _logWarning('WARNING: Failed to stop log collector process with PID $collectorPid');
    }
    try {
      if (readLogCollectorPid() == collectorPid) File(logCollectorPidFile).deleteSync();
    } on FileSystemException catch (_) {
      // The collector removed its own PID file in the meantime.
    }
  }

  Future<String?> _resolveEntrypoint() async {
    const relativePath = 'bin/log_collector.dart';
    final packageUri = Uri.parse('package:fdb/constants.dart');
    final resolved = await Isolate.resolvePackageUri(packageUri);
    if (resolved != null) {
      var current = File.fromUri(resolved).parent;
      while (true) {
        final candidate = File('${current.path}/$relativePath');
        if (candidate.existsSync()) {
          return candidate.path;
        }
        if (current.parent.path == current.path) {
          break;
        }
        current = current.parent;
      }
    }

    final scriptDir = Directory.fromUri(Platform.script).parent;
    final packageRoot = scriptDir.parent;
    final fallback = File('${packageRoot.path}/$relativePath');
    if (fallback.existsSync()) {
      return fallback.path;
    }

    return null;
  }
}
