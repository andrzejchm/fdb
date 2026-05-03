import 'dart:io';
import 'dart:isolate';

import 'package:fdb_controller/src/session.dart';
import 'package:fdb_controller/src/process_utils.dart';

typedef ControllerLogSink = void Function(String line);

class LogCollectorManager {
  LogCollectorManager({required ControllerLogSink logWarning}) : _logWarning = logWarning;

  final ControllerLogSink _logWarning;
  String? _vmUri;

  Future<void> start(String wsUri) async {
    final existingCollectorPid = readLogCollectorPid();
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

    stop();
    try {
      await Process.start(
        Platform.resolvedExecutable,
        [
          collectorEntrypoint,
          wsUri,
          logFile,
          logCollectorPidFile,
        ],
        mode: ProcessStartMode.detached,
      );
      _vmUri = wsUri;
    } catch (e) {
      _logWarning('WARNING: Log collector failed to start: $e');
    }
  }

  void stop() {
    final collectorPid = readLogCollectorPid();
    if (collectorPid == null || !isProcessAlive(collectorPid)) return;
    if (!Process.killPid(collectorPid, ProcessSignal.sigterm)) {
      _logWarning('WARNING: Failed to stop old log collector process with PID $collectorPid');
    }
  }

  Future<String?> _resolveEntrypoint() async {
    const relativePath = 'bin/log_collector.dart';
    final packageUri = Uri.parse('package:fdb/commands/launch.dart');
    final resolved = await Isolate.resolvePackageUri(packageUri);
    if (resolved != null) {
      final packageRoot = File.fromUri(resolved).parent.parent.parent;
      final candidate = File('${packageRoot.path}/$relativePath');
      if (candidate.existsSync()) {
        return candidate.path;
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
