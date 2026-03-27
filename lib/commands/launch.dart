import 'dart:io';

import 'package:fdb/constants.dart';

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

  // Clean up previous state
  for (final path in [
    pidFile,
    logFile,
    vmUriFile,
    launcherScript,
    deviceFile
  ]) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  // Persist device ID for other commands to use
  File(deviceFile).writeAsStringSync(device);

  // Build the flutter run command string
  final flutterArgs = [
    'flutter',
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
  final pid = File(pidFile).existsSync()
      ? File(pidFile).readAsStringSync().trim()
      : launcherPid.toString();

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

/// Shell-escape a string for safe embedding in a bash command.
String _shellEscape(String value) {
  if (RegExp(r'^[a-zA-Z0-9._/=-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}

bool _isAlive(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
