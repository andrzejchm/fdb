import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/src/controller/fdb_controller.dart';
import 'package:fdb/core/commands/kill/kill_models.dart';
import 'package:fdb/core/process_utils.dart';
export 'package:fdb/core/commands/kill/kill_models.dart';

/// Stops the running app process referenced by the session's PID file.
///
/// Returns [KillSuccess] on success, [KillNoSession] if no PID file is
/// present, or [KillFailed] if the process refused to die after `SIGKILL`.
Future<KillResult> killApp(KillInput _) async {
  if (!hasMeaningfulSessionFiles()) {
    return const KillNoSession();
  }

  final logCollectorStopped = await _stopLogCollector();
  final controllerStopped = await _stopThroughController();
  if (controllerStopped) {
    final visibleProcessesStopped = await _stopVisibleSessionProcesses();
    if (logCollectorStopped && visibleProcessesStopped) {
      cleanupTempFiles();
      return const KillSuccess();
    }

    return const KillFailed();
  }

  final fallbackStopped = await _stopVisibleSessionProcesses();
  cleanupTempFiles();
  if (logCollectorStopped && fallbackStopped) {
    return const KillSuccess();
  }

  return const KillFailed();
}

Future<bool> _stopThroughController() async {
  try {
    final response = await sendControllerCommand(
      ControllerCommand.kill,
      timeout: const Duration(seconds: killTimeoutSeconds),
    );
    return response.field('stopped') == true;
  } on ControllerCommandFailed {
    return false;
  } on ControllerUnavailable {
    return false;
  } on AppDiedException {
    return false;
  }
}

Future<bool> _stopLogCollector() async {
  final collectorPid = readLogCollectorPid();
  if (collectorPid == null) {
    return true;
  }

  return _terminateProcess(collectorPid);
}

Future<bool> _stopVisibleSessionProcesses() async {
  final pidsToStop = <int>{};
  var allStopped = true;

  if (isAndroidTarget()) {
    final androidStopped = _forceStopAndroidApp();
    if (!androidStopped) {
      allStopped = false;
    }
  }

  final flutterToolPid = readPid();
  if (flutterToolPid != null) {
    pidsToStop.add(flutterToolPid);
  }

  final controllerPid = readControllerPid();
  if (controllerPid != null) {
    pidsToStop.add(controllerPid);
  }

  final appPid = readAppPid();
  if (appPid != null && canKillAppPidOnHost()) {
    pidsToStop.add(appPid);
  }

  for (final pid in pidsToStop) {
    final stopped = await _terminateProcess(pid);
    if (!stopped) {
      allStopped = false;
    }
  }

  return allStopped;
}

bool _forceStopAndroidApp() {
  final device = readDevice();
  final appId = readAppId();
  if (device == null || device.isEmpty || appId == null || appId.isEmpty) {
    return readAppPid() == null;
  }

  try {
    final result = Process.runSync(adbExecutable, [
      '-s',
      device,
      'shell',
      'am',
      'force-stop',
      appId,
    ]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> _terminateProcess(int pid) async {
  if (!isProcessAlive(pid)) {
    return true;
  }

  try {
    Process.killPid(pid, ProcessSignal.sigterm);
  } catch (_) {
    return !isProcessAlive(pid);
  }

  if (await _waitForExit(pid)) {
    return true;
  }

  try {
    Process.killPid(pid, ProcessSignal.sigkill);
  } catch (_) {
    return !isProcessAlive(pid);
  }

  return _waitForExit(pid);
}

Future<bool> _waitForExit(int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: killTimeoutSeconds));
  while (DateTime.now().isBefore(deadline)) {
    if (!isProcessAlive(pid)) {
      return true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  return !isProcessAlive(pid);
}
