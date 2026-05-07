import 'dart:async';
import 'dart:io';

import 'package:fdb/core/commands/status/status_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/status/status_models.dart';

/// Checks whether the Flutter app session is running.
///
/// Never throws. Returns a [StatusResult] with [StatusResult.running] set to
/// `false` when there is no active session.
Future<StatusResult> getStatus(StatusInput _) async {
  final controllerStatus = await _readControllerStatus();
  final vmServiceUri = await _readReachableVmServiceUri(
    readVmUri() ?? controllerStatus?.vmServiceUri,
  );
  final appPid = _readLiveAppPid();
  final flutterToolPid = _readLiveFlutterToolPid();
  final running = vmServiceUri != null || appPid != null || flutterToolPid != null;

  if (!running) {
    return const StatusResult(running: false);
  }

  return StatusResult(
    running: true,
    pid: appPid ?? controllerStatus?.pid ?? flutterToolPid,
    vmServiceUri: vmServiceUri,
  );
}

class _ControllerStatusSnapshot {
  const _ControllerStatusSnapshot({
    required this.running,
    required this.pid,
    required this.vmServiceUri,
  });

  final bool running;
  final int? pid;
  final String? vmServiceUri;
}

Future<_ControllerStatusSnapshot?> _readControllerStatus() async {
  try {
    final response = await sendControllerCommand(
      ControllerCommand.status,
      timeout: const Duration(seconds: 3),
    );

    return _ControllerStatusSnapshot(
      running: response.field('running') == true,
      pid: response.field('pid') as int?,
      vmServiceUri: response.field('vmServiceUri') as String?,
    );
  } on ControllerCommandFailed {
    return null;
  } on ControllerUnavailable {
    return null;
  } on AppDiedException {
    return null;
  }
}

int? _readLiveAppPid() {
  final appPid = readAppPid();
  if (appPid == null || !isAppPidAlive(appPid)) {
    return null;
  }

  return appPid;
}

int? _readLiveFlutterToolPid() {
  final flutterToolPid = readPid();
  if (flutterToolPid == null || !isProcessAlive(flutterToolPid)) {
    return null;
  }

  return flutterToolPid;
}

Future<String?> _readReachableVmServiceUri(String? vmServiceUri) async {
  if (vmServiceUri == null || vmServiceUri.isEmpty) {
    return null;
  }

  try {
    final socket = await WebSocket.connect(
      _normaliseVmServiceUri(vmServiceUri),
    ).timeout(const Duration(seconds: 3));
    await socket.close();
    return vmServiceUri;
  } catch (_) {
    return null;
  }
}

String _normaliseVmServiceUri(String vmServiceUri) {
  return vmServiceUri.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
}
