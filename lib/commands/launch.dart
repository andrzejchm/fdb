import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/log_collector_source.dart';
import 'package:fdb/process_utils.dart';

Future<int> runLaunch(List<String> args) async {
  String? device;
  String? project;
  String? flavor;
  String? target;
  String? flutterSdk;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        device = args[++i];
      case '--project':
        project = args[++i];
      case '--flavor':
        flavor = args[++i];
      case '--target':
        target = args[++i];
      case '--flutter-sdk':
        flutterSdk = args[++i];
    }
  }

  // Default project to CWD — agents run from the project directory.
  project ??= Directory.current.path;

  if (device == null) {
    stderr.writeln('ERROR: --device is required');
    return 1;
  }

  // Point all session files at <project>/.fdb/
  initSessionDir(project);

  // Kill any previous log collector.
  final oldCollectorPid = readLogCollectorPid();
  if (oldCollectorPid != null && isProcessAlive(oldCollectorPid)) {
    try {
      Process.killPid(oldCollectorPid, ProcessSignal.sigterm);
    } catch (_) {}
  }

  // Clean up previous state
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
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  // Create .fdb/ session directory and persist device ID.
  ensureSessionDir();
  _ensureGitignored(project);
  File(deviceFile).writeAsStringSync(device);

  // Resolve the flutter binary: explicit --flutter-sdk, FVM auto-detect, or PATH.
  final flutter = _resolveFlutter(project, flutterSdk);

  // Resolve and persist the target platform + emulator flag for this device.
  // Used by `fdb screenshot` to dispatch to the correct capture backend.
  // Non-fatal: screenshot falls back to the old heuristic if this fails.
  await _writePlatformInfo(device, flutter);

  // Build the flutter run command string
  final flutterArgs = [
    flutter,
    'run',
    '-d',
    device,
    '--debug',
    '--pid-file',
    pidFile,
    if (flavor != null) ...['--flavor', flavor],
    if (target != null) ...['--target', target],
  ];
  final flutterCmd = flutterArgs.map(_shellEscape).join(' ');

  // Write a launcher script that runs flutter in the foreground (nohup keeps
  // it alive after the parent exits, and & backgrounds it from our perspective)
  final script = '''
#!/bin/bash
cd ${_shellEscape(project)}
exec $flutterCmd > $logFile 2>&1
''';
  File(launcherScript).writeAsStringSync(script);
  Process.runSync('chmod', ['+x', launcherScript]);

  // Launch via nohup + & so the process is fully detached from this parent
  final result = await Process.run('bash', [
    '-c',
    'nohup bash $launcherScript &\necho \$!',
  ]);

  if (result.exitCode != 0) {
    stderr.writeln('ERROR: Failed to start launcher: ${result.stderr}');
    return 1;
  }

  final launcherPid = int.tryParse((result.stdout as String).trim());
  if (launcherPid == null) {
    stderr.writeln('ERROR: Could not read launcher PID');
    return 1;
  }

  // Poll log file for VM service URI
  final stopwatch = Stopwatch()..start();
  var lastHeartbeat = 0;
  String? vmUri;

  while (stopwatch.elapsed.inSeconds < launchTimeoutSeconds) {
    await Future<void>.delayed(const Duration(milliseconds: pollIntervalMs));

    // Heartbeat so the caller knows we're not stuck
    final elapsedSeconds = stopwatch.elapsed.inSeconds;
    if (elapsedSeconds ~/ heartbeatIntervalSeconds > lastHeartbeat) {
      lastHeartbeat = elapsedSeconds ~/ heartbeatIntervalSeconds;
      stdout.writeln('WAITING...');
    }

    // Check if the launcher process died unexpectedly
    if (!_isAlive(launcherPid)) {
      final logExists = File(logFile).existsSync();
      if (logExists) {
        final lines = File(logFile).readAsLinesSync();
        final tail = lines.length > 10 ? lines.sublist(lines.length - 10) : lines;
        stderr.writeln('ERROR: flutter process exited unexpectedly');
        for (final line in tail) {
          stderr.writeln(line);
        }
      } else {
        stderr.writeln(
          'ERROR: flutter process exited and no log file was created',
        );
      }
      return 1;
    }

    final logExists = File(logFile).existsSync();
    if (!logExists) continue;

    final logContent = File(logFile).readAsStringSync();
    vmUri = _extractVmUri(logContent);
    if (vmUri != null) break;
  }

  if (vmUri == null) {
    stdout.writeln('LAUNCH_TIMEOUT');
    if (File(logFile).existsSync()) {
      final lines = File(logFile).readAsLinesSync();
      final tail = lines.length > 10 ? lines.sublist(lines.length - 10) : lines;
      for (final line in tail) {
        stdout.writeln(line);
      }
    }
    return 1;
  }

  // Save VM service URI
  File(vmUriFile).writeAsStringSync(vmUri);

  // Read PID — flutter writes it via --pid-file, fall back to launcher PID
  final pid = File(pidFile).existsSync() ? File(pidFile).readAsStringSync().trim() : launcherPid.toString();

  // Start the log collector — a background process that subscribes to the
  // VM service Logging/Stdout/Stderr streams and appends to the log file.
  // flutter run only forwards print() to stdout; developer.log() events are
  // only available via the VM service, so this fills that gap.
  await _startLogCollector(vmUri);

  stdout.writeln('APP_STARTED');
  stdout.writeln('VM_SERVICE_URI=$vmUri');
  stdout.writeln('PID=$pid');
  stdout.writeln('LOG_FILE=$logFile');

  return 0;
}

Future<void> _startLogCollector(String vmUri) async {
  // Write a self-contained Dart script that subscribes to the VM service
  // Logging/Stdout/Stderr streams and appends events to the log file.
  // This runs as a detached process so it outlives the fdb launch command.
  File(logCollectorScript).writeAsStringSync(logCollectorSource);

  // Launch via nohup so the collector survives after fdb exits.
  // Same pattern used for the flutter run launcher script.
  await Process.run('bash', [
    '-c',
    'nohup dart run ${_shellEscape(logCollectorScript)}'
        ' ${_shellEscape(vmUri)}'
        ' ${_shellEscape(logFile)}'
        ' ${_shellEscape(logCollectorPidFile)}'
        ' > /dev/null 2>&1 &',
  ]);
}

/// Extract VM service websocket URI from flutter run log output.
String? _extractVmUri(String logContent) {
  // Match http(s) URIs with auth token path (e.g. http://127.0.0.1:9100/AbCdEf=/)
  // or ws:// URIs directly
  final match = RegExp(
    r'(https?://[^\s]+/[a-zA-Z0-9_\-]+=/)|(ws://[^\s]+)',
  ).firstMatch(logContent);

  if (match == null) {
    // Fall back: check for DevTools/Observatory text, then try again
    if (!logContent.contains('Flutter DevTools') && !logContent.contains('An Observatory debugger')) {
      return null;
    }
    final fallback = RegExp(
      r'(https?://127\.0\.0\.1:\d+/[a-zA-Z0-9_\-]+=/)|(ws://[^\s]+)',
    ).firstMatch(logContent);
    if (fallback == null) return null;
    return _httpToWs(fallback.group(0)!);
  }

  return _httpToWs(match.group(0)!);
}

String _httpToWs(String uri) {
  if (!uri.startsWith('http')) return uri;
  var wsUri = uri.replaceFirst('http', 'ws');
  if (!wsUri.endsWith('ws')) wsUri = '${wsUri}ws';
  return wsUri;
}

/// Shell-escape a string for safe embedding in a bash command.
String _shellEscape(String value) {
  if (RegExp(r'^[a-zA-Z0-9._/=-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}

/// Resolve the flutter binary path.
///
/// Priority:
/// 1. Explicit `--flutter-sdk <path>` → `<path>/bin/flutter`
/// 2. FVM auto-detect: `<project>/.fvm/flutter_sdk/bin/flutter`
/// 3. `flutter` from PATH
String _resolveFlutter(String projectPath, String? explicitSdk) {
  if (explicitSdk != null) {
    final bin = '$explicitSdk/bin/flutter';
    if (File(bin).existsSync()) return bin;
    stderr.writeln('WARNING: --flutter-sdk path not found ($bin), falling back to PATH');
  }

  // FVM stores a symlink at .fvm/flutter_sdk → <sdk-version>
  final fvmBin = '$projectPath/.fvm/flutter_sdk/bin/flutter';
  if (File(fvmBin).existsSync() || Link(fvmBin).existsSync()) {
    return fvmBin;
  }

  return 'flutter';
}

/// Append `.fdb/` to the project's `.gitignore` if not already present.
void _ensureGitignored(String projectPath) {
  final gitignore = File('$projectPath/.gitignore');
  if (gitignore.existsSync()) {
    final content = gitignore.readAsStringSync();
    if (content.contains('.fdb/') || content.contains('.fdb')) return;
    gitignore.writeAsStringSync('\n# fdb session state\n.fdb/\n', mode: FileMode.append);
  } else {
    gitignore.writeAsStringSync('# fdb session state\n.fdb/\n');
  }
}

bool _isAlive(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Queries `flutter devices --machine` to find the targetPlatform and emulator
/// flag for [device], then writes them to [platformFile] via [writePlatformInfo].
///
/// Silently no-ops on any failure — screenshot falls back gracefully if the
/// platform file is absent.
Future<void> _writePlatformInfo(String device, String flutter) async {
  try {
    final result = await Process.run(flutter, ['devices', '--machine']);
    if (result.exitCode != 0) return;

    final json = extractDevicesJson(result.stdout as String);
    if (json == null) return;

    final List<dynamic> devices;
    try {
      devices = (jsonDecode(json) as List<dynamic>);
    } catch (_) {
      return;
    }

    for (final d in devices) {
      final map = d as Map<String, dynamic>;
      if (map['id'] == device) {
        final platform = map['targetPlatform'] as String?;
        final emulator = map['emulator'] as bool? ?? false;
        if (platform != null) writePlatformInfo(platform, emulator);
        return;
      }
    }
  } on TimeoutException {
    rethrow;
  } catch (_) {
    // Non-fatal: screenshot will work without platform info.
  }
}
