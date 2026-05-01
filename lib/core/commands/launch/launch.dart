import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/launch/launch_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/launch/launch_models.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

void _noop(String _) {}

/// Launches a Flutter app as a detached background process and waits for the
/// VM service URI to appear in the log.
///
/// Progress messages (heartbeats and warnings) are emitted via [onProgress].
/// Heartbeats are plain tokens (e.g. "WAITING..."); warnings are prefixed with
/// "WARNING: " so adapters can route them to the appropriate output channel.
///
/// Never throws. All error conditions are represented as sealed result cases.
Future<LaunchResult> launchApp(
  LaunchInput input, {
  void Function(String) onProgress = _noop,
}) async {
  try {
    final device = input.device;
    final project = input.project ?? Directory.current.path;
    final flavor = input.flavor;
    final target = input.target;
    final flutterSdk = input.flutterSdk;
    final verbose = input.verbose;

    if (device == null) return const LaunchMissingDevice();

    // Point all session files at <project>/.fdb/
    initSessionDir(project);

    // Kill any previous log collector.
    final oldCollectorPid = readLogCollectorPid();
    if (oldCollectorPid != null && isProcessAlive(oldCollectorPid)) {
      try {
        Process.killPid(oldCollectorPid, ProcessSignal.sigterm);
      } catch (_) {}
    }

    // Clean up previous state.
    for (final path in [
      pidFile,
      appPidFile,
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
    final flutter = _resolveFlutter(project, flutterSdk, onProgress);

    // Resolve and persist the target platform + emulator flag for this device.
    // Used by `fdb screenshot` to dispatch to the correct capture backend.
    // Non-fatal: screenshot falls back to the old heuristic if this fails.
    await _writePlatformInfo(device, flutter);

    // Persist the app bundle id / package name for later use by crash-report.
    // Non-fatal: crash-report will ask the user for --app-id if this fails.
    _writeAppIdFromProject(project, device);

    // Build the flutter run command string.
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
      if (verbose) '--verbose',
    ];
    final flutterCmd = flutterArgs.map(_shellEscape).join(' ');

    // Write a launcher script that runs flutter in the foreground (nohup keeps
    // it alive after the parent exits, and & backgrounds it from our perspective).
    final script = '''
#!/bin/bash
cd ${_shellEscape(project)}
exec $flutterCmd > $logFile 2>&1
''';
    File(launcherScript).writeAsStringSync(script);
    Process.runSync('chmod', ['+x', launcherScript]);

    // Launch via nohup + & so the process is fully detached from this parent.
    final result = await Process.run('bash', [
      '-c',
      'nohup bash $launcherScript &\necho \$!',
    ]);

    if (result.exitCode != 0) {
      return LaunchLauncherFailed(result.stderr as String);
    }

    final launcherPid = int.tryParse((result.stdout as String).trim());
    if (launcherPid == null) return const LaunchInvalidLauncherPid();

    // Poll log file for VM service URI.
    final stopwatch = Stopwatch()..start();
    var lastHeartbeat = 0;
    String? vmUri;

    while (stopwatch.elapsed.inSeconds < launchTimeoutSeconds) {
      await Future<void>.delayed(const Duration(milliseconds: pollIntervalMs));

      // Heartbeat so the caller knows we're not stuck.
      final elapsedSeconds = stopwatch.elapsed.inSeconds;
      if (elapsedSeconds ~/ heartbeatIntervalSeconds > lastHeartbeat) {
        lastHeartbeat = elapsedSeconds ~/ heartbeatIntervalSeconds;
        onProgress('WAITING...');
      }

      // Check if the launcher process died unexpectedly.
      if (!_isAlive(launcherPid)) {
        final logExists = File(logFile).existsSync();
        if (logExists) {
          final logContent = File(logFile).readAsStringSync();
          return LaunchProcessDied(fullLog: logContent);
        } else {
          return const LaunchProcessDied(noLogFile: true);
        }
      }

      if (!File(logFile).existsSync()) continue;

      final logContent = File(logFile).readAsStringSync();
      vmUri = _extractVmUri(logContent);
      if (vmUri != null) break;
    }

    if (vmUri == null) {
      final tailLogLines = <String>[];
      if (File(logFile).existsSync()) {
        final lines = File(logFile).readAsLinesSync();
        tailLogLines.addAll(
          lines.length > 10 ? lines.sublist(lines.length - 10) : lines,
        );
      }
      return LaunchTimeout(tailLogLines: tailLogLines);
    }

    // Save VM service URI.
    File(vmUriFile).writeAsStringSync(vmUri);

    // Read PID — flutter writes it via --pid-file, fall back to launcher PID.
    final pid = File(pidFile).existsSync() ? File(pidFile).readAsStringSync().trim() : launcherPid.toString();

    // Start the log collector — a background process that subscribes to the
    // VM service Logging/Stdout/Stderr streams and appends to the log file.
    // flutter run only forwards print() to stdout; developer.log() events are
    // only available via the VM service, so this fills that gap.
    await _startLogCollector(vmUri, onProgress);

    // Retrieve the app VM PID via getVM and persist it to fdb.app_pid.
    // This is the Dart VM process PID (different from the flutter-tools PID in
    // fdb.pid). Used by vmServiceCall for liveness detection on macOS desktop.
    // Non-fatal: if getVM fails for any reason, fdb.app_pid is simply not written
    // and vmServiceCall falls back to the flutter-tools PID heuristic.
    await _writeAppPid();

    return LaunchSuccess(
      vmServiceUri: vmUri,
      pid: pid,
      logFilePath: logFile,
    );
  } catch (e) {
    return LaunchError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// Log collector
// ---------------------------------------------------------------------------

Future<void> _startLogCollector(
  String vmUri,
  void Function(String) onProgress,
) async {
  final collectorEntrypoint = await _resolveLogCollectorEntrypoint();
  if (collectorEntrypoint == null) {
    onProgress(
      'WARNING: Log collector entrypoint not found; developer.log() events may be missing',
    );
    return;
  }

  // Launch via nohup so the collector survives after fdb exits.
  // Same pattern used for the flutter run launcher script.
  await Process.run('bash', [
    '-c',
    'nohup dart ${_shellEscape(collectorEntrypoint)}'
        ' ${_shellEscape(vmUri)}'
        ' ${_shellEscape(logFile)}'
        ' ${_shellEscape(logCollectorPidFile)}'
        ' > /dev/null 2>&1 &',
  ]);
}

Future<String?> _resolveLogCollectorEntrypoint() async {
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

// ---------------------------------------------------------------------------
// Flutter binary resolution
// ---------------------------------------------------------------------------

/// Resolve the flutter binary path.
///
/// Priority:
/// 1. Explicit --flutter-sdk path → path/bin/flutter
/// 2. FVM auto-detect: project/.fvm/flutter_sdk/bin/flutter
/// 3. flutter from PATH
String _resolveFlutter(
  String projectPath,
  String? explicitSdk,
  void Function(String) onProgress,
) {
  if (explicitSdk != null) {
    final bin = '$explicitSdk/bin/flutter';
    if (File(bin).existsSync()) return bin;
    onProgress(
      'WARNING: --flutter-sdk path not found ($bin), falling back to PATH',
    );
  }

  // FVM stores a symlink at .fvm/flutter_sdk → sdk-version
  final fvmBin = '$projectPath/.fvm/flutter_sdk/bin/flutter';
  if (File(fvmBin).existsSync() || Link(fvmBin).existsSync()) {
    return fvmBin;
  }

  return 'flutter';
}

// ---------------------------------------------------------------------------
// Platform info
// ---------------------------------------------------------------------------

/// Queries flutter devices --machine to find the targetPlatform and emulator
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
      devices = jsonDecode(json) as List<dynamic>;
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

// ---------------------------------------------------------------------------
// App id
// ---------------------------------------------------------------------------

/// Reads the app bundle id (iOS/macOS) or application id (Android) from the
/// project's native config files and persists it to [appIdFile].
///
/// Silently no-ops on any failure — crash-report falls back to --app-id flag.
void _writeAppIdFromProject(String projectPath, String device) {
  try {
    // Determine target platform from the session info written by _writePlatformInfo
    // (called immediately before this function). This ensures we consult the
    // correct native config file first, avoiding e.g. an Android package name
    // being written for an iOS simulator launch.
    final platformInfo = readPlatformInfo();
    final platform = platformInfo?.platform ?? '';
    final isIos = platform.startsWith('ios');
    final isMacos = platform == 'macos' || platform.startsWith('darwin');

    // Build a prioritised list of extractors for this target platform.
    // Each entry is a closure that returns the app id or null.
    final extractors = <String? Function()>[
      if (isIos) ...[
        () {
          final f = File('$projectPath/ios/Runner/Info.plist');
          if (!f.existsSync()) return null;
          final id = _extractPlistBundleId(f.readAsStringSync());
          if (id != null) return id;
          // Info.plist uses a variable reference — resolve from project.pbxproj.
          return _resolvePbxprojBundleId('$projectPath/ios/Runner.xcodeproj/project.pbxproj');
        },
      ],
      if (isMacos) ...[
        () {
          final f = File('$projectPath/macos/Runner/Info.plist');
          if (!f.existsSync()) return null;
          final id = _extractPlistBundleId(f.readAsStringSync());
          if (id != null) return id;
          // Info.plist uses a variable reference — try xcconfig first, then pbxproj.
          return _resolveXcconfigBundleId('$projectPath/macos/Runner/Configs/AppInfo.xcconfig') ??
              _resolvePbxprojBundleId('$projectPath/macos/Runner.xcodeproj/project.pbxproj');
        },
      ],
      if (!isIos && !isMacos) ...[
        () {
          final f = File('$projectPath/android/app/build.gradle.kts');
          return f.existsSync() ? _extractApplicationId(f.readAsStringSync()) : null;
        },
        () {
          final f = File('$projectPath/android/app/build.gradle');
          return f.existsSync() ? _extractApplicationId(f.readAsStringSync()) : null;
        },
      ],
      // Fallbacks: try remaining platforms so Android-only projects without
      // Info.plist still work when platform is unknown, and iOS projects with a
      // missing plist can fall back to other files.
      if (!isIos) ...[
        () {
          final f = File('$projectPath/ios/Runner/Info.plist');
          if (!f.existsSync()) return null;
          final id = _extractPlistBundleId(f.readAsStringSync());
          if (id != null) return id;
          return _resolvePbxprojBundleId('$projectPath/ios/Runner.xcodeproj/project.pbxproj');
        },
      ],
      if (!isMacos)
        () {
          final f = File('$projectPath/macos/Runner/Info.plist');
          if (!f.existsSync()) return null;
          final id = _extractPlistBundleId(f.readAsStringSync());
          if (id != null) return id;
          return _resolveXcconfigBundleId('$projectPath/macos/Runner/Configs/AppInfo.xcconfig') ??
              _resolvePbxprojBundleId('$projectPath/macos/Runner.xcodeproj/project.pbxproj');
        },
    ];

    for (final extractor in extractors) {
      final id = extractor();
      if (id != null) {
        writeAppId(id);
        return;
      }
    }
  } catch (_) {
    // Non-fatal: crash-report will prompt for --app-id.
  }
}

/// Extracts `applicationId` or `namespace` from a Gradle build file.
String? _extractApplicationId(String content) {
  // Kotlin DSL: applicationId = "com.example.app" or namespace = "com.example.app"
  // Groovy DSL: applicationId "com.example.app" or namespace "com.example.app"
  final patterns = [
    RegExp(r'applicationId\s*[=\s]\s*["\x27]([a-zA-Z0-9._]+)["\x27]'),
    RegExp(r'namespace\s*[=\s]\s*["\x27]([a-zA-Z0-9._]+)["\x27]'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(content);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Extracts `CFBundleIdentifier` from an Info.plist file.
///
/// Returns the literal bundle ID when present. Returns null when the value is
/// an Xcode variable substitution (e.g. `$(PRODUCT_BUNDLE_IDENTIFIER)`) —
/// callers should then resolve via `_resolvePbxprojBundleId` or
/// `_resolveXcconfigBundleId`.
String? _extractPlistBundleId(String content) {
  final match = RegExp(
    r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>',
  ).firstMatch(content);
  if (match == null) return null;
  final value = match.group(1)!;
  // Skip unresolved Xcode variable substitutions like $(VAR) or ${VAR}.
  if (value.contains(r'$(') || value.contains(r'${')) return null;
  return value;
}

/// Reads `PRODUCT_BUNDLE_IDENTIFIER` for the main Runner target from an Xcode
/// `project.pbxproj` file.
///
/// Scans every `PRODUCT_BUNDLE_IDENTIFIER = ...` assignment and returns the
/// shortest value found. In standard Flutter projects the main app target's
/// bundle ID is shorter than test targets (which append suffixes such as
/// `.RunnerTests`), so the shortest value is the main app bundle ID.
/// Returns null when the file does not exist or contains no matching entry.
String? _resolvePbxprojBundleId(String pbxprojPath) {
  final f = File(pbxprojPath);
  if (!f.existsSync()) return null;
  final content = f.readAsStringSync();
  final matches = RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([A-Za-z0-9._-]+)\s*;',
  ).allMatches(content);

  String? best;
  for (final m in matches) {
    final id = m.group(1)!;
    // Prefer the shortest ID; in standard Flutter projects the main app target's bundle ID is shorter than test targets (which append .RunnerTests or similar).
    if (best == null || id.length < best.length) {
      best = id;
    }
  }
  return best;
}

/// Reads `PRODUCT_BUNDLE_IDENTIFIER` from an Xcode `.xcconfig` file.
///
/// Used for macOS targets where the bundle ID is typically stored in
/// `macos/Runner/Configs/AppInfo.xcconfig` rather than in `project.pbxproj`.
/// Returns null when the file does not exist or contains no matching entry.
String? _resolveXcconfigBundleId(String xcconfigPath) {
  final f = File(xcconfigPath);
  if (!f.existsSync()) return null;
  final match = RegExp(
    r'^\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.+)$',
    multiLine: true,
  ).firstMatch(f.readAsStringSync());
  final raw = match?.group(1)?.trim();
  if (raw == null) return null;
  // Strip inline // comments (e.g. "com.example.app // comment" or "com.example.app//comment").
  final commentIndex = raw.indexOf('//');
  if (commentIndex == -1) return raw.isEmpty ? null : raw;
  final stripped = raw.substring(0, commentIndex).trim();
  return stripped.isEmpty ? null : stripped;
}

// ---------------------------------------------------------------------------
// Gitignore
// ---------------------------------------------------------------------------

/// Append .fdb/ to the project's .gitignore if not already present.
void _ensureGitignored(String projectPath) {
  final gitignore = File('$projectPath/.gitignore');
  if (gitignore.existsSync()) {
    final content = gitignore.readAsStringSync();
    if (content.contains('.fdb/') || content.contains('.fdb')) return;
    gitignore.writeAsStringSync(
      '\n# fdb session state\n.fdb/\n',
      mode: FileMode.append,
    );
  } else {
    gitignore.writeAsStringSync('# fdb session state\n.fdb/\n');
  }
}

// ---------------------------------------------------------------------------
// App PID
// ---------------------------------------------------------------------------

/// Calls getVM on the VM service to retrieve the app process PID and writes
/// it to [appPidFile]. Silently no-ops on any failure — callers fall back
/// to the flutter-tools PID heuristic when this file is absent.
Future<void> _writeAppPid() async {
  try {
    final response = await vmServiceCall('getVM');
    final result = response['result'] as Map<String, dynamic>?;
    if (result == null) return;
    final appPid = result['pid'];
    if (appPid == null) return;
    File(appPidFile).writeAsStringSync(appPid.toString());
  } catch (_) {
    // Non-fatal: fdb.app_pid simply won't be written.
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool _isAlive(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Extract VM service websocket URI from flutter run log output.
String? _extractVmUri(String logContent) {
  // Match http(s) URIs with auth token path (e.g. http://127.0.0.1:9100/AbCdEf=/)
  // or ws:// URIs directly.
  final match = RegExp(
    r'(https?://[^\s]+/[a-zA-Z0-9_\-]+=/)|(ws://[^\s]+)',
  ).firstMatch(logContent);

  if (match == null) {
    // Fall back: check for DevTools/Observatory text, then try again.
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
