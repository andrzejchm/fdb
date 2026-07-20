import 'dart:async';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/attach/attach_models.dart';
import 'package:fdb/core/commands/attach/vm_uri_discovery.dart';
import 'package:fdb/core/commands/launch/launch.dart';
import 'package:fdb/core/flutter_binary.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/attach/attach_models.dart';
export 'package:fdb/core/commands/attach/vm_uri_discovery.dart' show discoverVmServiceUrl;

void _noop(String _) {}

/// Attaches fdb to an already-running Flutter app and waits for the VM service.
///
/// Never throws. All error conditions are represented as sealed result cases.
Future<AttachResult> attachApp(
  AttachInput input, {
  void Function(String) onProgress = _noop,
}) async {
  try {
    final device = input.device;
    final project = input.project ?? Directory.current.path;
    final flutterSdk = input.flutterSdk;
    final appId = input.appId;
    String? deviceLabel;

    if (device == null) return const AttachMissingDevice();
    onProgress('attach: preparing session');

    initLaunchSession(project: project, sessionDir: input.sessionDir);
    _stopPreviousSessionProcesses();
    cleanupLaunchSessionFiles();

    ensureSessionDir();
    ensureGitignored(project);
    File(deviceFile).writeAsStringSync(device);

    final flutter = resolveFlutterBinary(
      project,
      explicitSdk: flutterSdk,
      onWarning: onProgress,
    );

    deviceLabel = await writePlatformInfoForLaunch(device, flutter);
    writeAppIdFromProjectForLaunch(project, flavor: input.flavor);
    if (appId != null && appId.isNotEmpty) {
      writeAppId(appId);
    }

    // Resolve the debug URL: use the explicit flag when provided; otherwise
    // try to auto-discover it from device logs (Android logcat, iOS unified
    // log, or idevicesyslog on physical devices).
    String? debugUrl;
    if (input.debugUrl != null) {
      debugUrl = normalizeAttachDebugUrl(input.debugUrl!);
    } else {
      final platformInfo = readPlatformInfo();
      if (platformInfo != null) {
        onProgress('attach: attempting VM service URI auto-discovery');

        // Physical iOS log collection (idevicesyslog archive) typically takes
        // 10–15 s; use a 30 s timeout so the archive has time to complete.
        final isPhysicalIos =
            (platformInfo.platform == 'ios' || platformInfo.platform.startsWith('ios-')) && !platformInfo.emulator;
        final discoveryTimeout = isPhysicalIos ? const Duration(seconds: 30) : const Duration(seconds: 5);

        debugUrl = await discoverVmServiceUrl(
          device: device,
          platformInfo: platformInfo,
          timeout: discoveryTimeout,
          onProgress: onProgress,
        );
        if (debugUrl != null) {
          onProgress('attach: discovered VM service URI — $debugUrl');
        } else {
          onProgress('attach: VM service URI not found in device logs; falling back to mDNS discovery');
        }
      }
    }

    final controllerLaunch = resolveControllerLaunch();
    final controllerArgs = buildAttachControllerArgs(
      controllerLaunch.arguments,
      sessionDir: ensureSessionDir(),
      project: project,
      device: device,
      flutter: flutter,
      target: input.target,
      appId: appId,
      debugUrl: debugUrl,
      verbose: input.verbose,
    );

    late final Process controllerProcess;
    try {
      onProgress('attach: starting controller');
      controllerProcess = await Process.start(
        controllerLaunch.executable,
        controllerArgs,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      return AttachControllerFailed(e.toString());
    }
    File(controllerPidFile).writeAsStringSync(controllerProcess.pid.toString());

    final sigintSub = ProcessSignal.sigint.watch().listen((_) {
      _killPid(controllerProcess.pid);
      exit(1);
    });
    // ProcessSignal.sigterm.watch() throws a synchronous SignalException on
    // Windows (sigterm/sigusr1/sigusr2/sigwinch are not watchable there).
    // Skip it on Windows; sigint (Ctrl-C) above still works.
    final sigtermSub = Platform.isWindows
        ? null
        : ProcessSignal.sigterm.watch().listen((_) {
            _killPid(controllerProcess.pid);
            exit(1);
          });

    final stopwatch = Stopwatch()..start();
    var lastHeartbeat = 0;
    var reportedLogLines = 0;
    String? vmUri;
    onProgress('attach: waiting for Flutter app on ${deviceLabel ?? 'device $device'}');

    try {
      while (stopwatch.elapsed.inSeconds < launchTimeoutSeconds) {
        await Future<void>.delayed(const Duration(milliseconds: pollIntervalMs));

        final elapsedSeconds = stopwatch.elapsed.inSeconds;
        if (elapsedSeconds ~/ heartbeatIntervalSeconds > lastHeartbeat) {
          lastHeartbeat = elapsedSeconds ~/ heartbeatIntervalSeconds;
          onProgress(
            'attach: still waiting for VM service (${elapsedSeconds}s elapsed)',
          );
        }

        if (!isProcessAlive(controllerProcess.pid)) {
          final logExists = File(logFile).existsSync();
          if (logExists) {
            final logContent = File(logFile).readAsStringSync();
            return AttachProcessDied(fullLog: logContent);
          }
          return const AttachProcessDied(noLogFile: true);
        }

        if (File(logFile).existsSync()) {
          final lines = File(logFile).readAsLinesSync();
          if (lines.length > reportedLogLines) {
            for (final line in lines.skip(reportedLogLines)) {
              final progress = _progressFromLogLine(line);
              if (progress != null) {
                onProgress(progress);
              }
            }
            reportedLogLines = lines.length;
          }
        }

        vmUri = readVmUri();
        if (vmUri != null && vmUri.isNotEmpty) break;
      }

      if (vmUri == null) {
        final tailLogLines = <String>[];
        if (File(logFile).existsSync()) {
          final lines = File(logFile).readAsLinesSync();
          tailLogLines.addAll(
            lines.length > 10 ? lines.sublist(lines.length - 10) : lines,
          );
        }
        return AttachTimeout(tailLogLines: tailLogLines);
      }

      return AttachSuccess(
        vmServiceUri: vmUri,
        pid: readLaunchPid(),
        logFilePath: logFile,
      );
    } finally {
      await sigintSub.cancel();
      await sigtermSub?.cancel();
    }
  } catch (e) {
    return AttachError(e.toString());
  }
}

List<String> buildAttachControllerArgs(
  List<String> controllerEntrypointArgs, {
  required String sessionDir,
  required String project,
  required String device,
  required String flutter,
  String? target,
  String? appId,
  String? debugUrl,
  required bool verbose,
}) =>
    [
      ...controllerEntrypointArgs,
      '--mode',
      'attach',
      '--session-dir',
      sessionDir,
      '--project',
      project,
      '--device',
      device,
      '--flutter',
      flutter,
      if (target != null) ...['--target', target],
      if (appId != null) ...['--app-id', appId],
      if (debugUrl != null) ...['--debug-url', debugUrl],
      if (verbose) '--verbose',
    ];

String normalizeAttachDebugUrl(String debugUrl) {
  var normalized = debugUrl.trim();
  if (normalized.startsWith('ws://')) {
    normalized = 'http://${normalized.substring(5)}';
  } else if (normalized.startsWith('wss://')) {
    normalized = 'https://${normalized.substring(6)}';
  }

  if (normalized.endsWith('/ws/')) {
    return normalized.substring(0, normalized.length - 3);
  }
  if (normalized.endsWith('/ws')) {
    return normalized.substring(0, normalized.length - 2);
  }
  return normalized;
}

void _stopPreviousSessionProcesses() {
  for (final pid in [readControllerPid(), readLogCollectorPid()].whereType<int>()) {
    if (isProcessAlive(pid)) {
      _killPid(pid);
    }
  }
}

void _killPid(int pid) {
  try {
    Process.killPid(pid, ProcessSignal.sigterm);
  } catch (_) {}
}

String? _progressFromLogLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('Waiting for a connection from Flutter')) {
    return 'flutter: $trimmed';
  }
  if (trimmed.startsWith('The Dart VM service is listening on')) {
    return 'flutter: $trimmed';
  }
  if (trimmed.startsWith('Error connecting to')) {
    return 'flutter: $trimmed';
  }

  return null;
}
