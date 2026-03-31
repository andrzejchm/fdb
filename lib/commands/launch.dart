import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

Future<int> runLaunch(List<String> args) async {
  String? device;
  String? project;
  String? flavor;
  String? target;

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
    }
  }

  if (device == null || project == null) {
    stderr.writeln('ERROR: --device and --project are required');
    return 1;
  }

  // Ensure ~/.fdb/ directory structure exists
  ensureFdbHome();

  // Look up platform and emulator status from device cache
  var platform = lookupPlatform(device);
  var emulator = lookupEmulator(device);

  if (platform == null) {
    // Cache miss — refresh and try again
    await refreshDeviceCache();
    platform = lookupPlatform(device);
    emulator = lookupEmulator(device);
    if (platform == null) {
      stderr.writeln(
        'WARNING: Device $device not found in device cache. '
        'Platform will be unknown — screenshot may fail.',
      );
    }
  }

  // Determine CDP port for web targets.
  // NOTE: There is an inherent TOCTOU race here — we bind a socket to find a
  // free port, close it, then pass the port number to flutter run.  Another
  // process could claim the port in the window between close() and flutter
  // binding it.  This is a known limitation of the find-free-port pattern and
  // is acceptable for a debug-only tool.
  int? cdpPort;
  if (platform == 'web-javascript') {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    cdpPort = server.port;
    await server.close();
  }

  // Wipe any previous session for this device
  cleanupSession(device);

  // Write initial session state (pid and vmServiceUri filled in after launch)
  writeSession(device, {
    'deviceId': device,
    'platform': platform,
    'emulator': emulator,
    'launchedAt': DateTime.now().toUtc().toIso8601String(),
    'pid': null,
    'vmServiceUri': null,
    'cdpPort': cdpPort,
  });

  // Path for flutter's --pid-file inside the session directory
  final pidFilePath = '${sessionDir(device)}/flutter.pid';

  // Build the flutter run command string
  final flutterArgs = [
    'flutter',
    'run',
    '-d',
    device,
    '--debug',
    '--pid-file',
    pidFilePath,
    if (flavor != null) ...['--flavor', flavor],
    if (target != null) ...['--target', target],
    if (cdpPort != null) '--web-browser-debug-port=$cdpPort',
  ];
  final flutterCmd = flutterArgs.map(shellEscape).join(' ');

  // Write a launcher script that runs flutter in the foreground (nohup keeps
  // it alive after the parent exits, and & backgrounds it from our perspective)
  final logFile = logPath(device);
  final launcherScript = launcherPath(device);
  final script = '''
#!/bin/bash
cd ${shellEscape(project)}
exec $flutterCmd > ${shellEscape(logFile)} 2>&1
''';
  File(launcherScript).writeAsStringSync(script);
  Process.runSync('chmod', ['+x', launcherScript]);

  // Launch via nohup + & so the process is fully detached from this parent
  final result = await Process.run('bash', [
    '-c',
    'nohup bash ${shellEscape(launcherScript)} &\necho \$!',
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
    if (!isProcessAlive(launcherPid)) {
      final logExists = File(logFile).existsSync();
      if (logExists) {
        final lines = File(logFile).readAsLinesSync();
        final tail =
            lines.length > 10 ? lines.sublist(lines.length - 10) : lines;
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
    stderr.writeln(
      'ERROR: Launch timed out after $launchTimeoutSeconds seconds',
    );
    if (File(logFile).existsSync()) {
      final lines = File(logFile).readAsLinesSync();
      final tail = lines.length > 10 ? lines.sublist(lines.length - 10) : lines;
      for (final line in tail) {
        stderr.writeln(line);
      }
    }
    return 1;
  }

  // Read PID — flutter writes it via --pid-file, fall back to launcher PID
  final pid = File(pidFilePath).existsSync()
      ? File(pidFilePath).readAsStringSync().trim()
      : launcherPid.toString();

  // Persist PID and VM service URI into session.json
  updateSession(device, {
    'pid': int.tryParse(pid) ?? pid,
    'vmServiceUri': vmUri,
  });

  stdout.writeln('APP_STARTED');
  stdout.writeln('VM_SERVICE_URI=$vmUri');
  stdout.writeln('PID=$pid');
  stdout.writeln('LOG_FILE=$logFile');

  return 0;
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
    if (!logContent.contains('Flutter DevTools') &&
        !logContent.contains('An Observatory debugger')) {
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
