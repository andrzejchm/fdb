import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/launch/launch_models.dart';
import 'package:fdb/core/flutter_binary.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/launch/launch_models.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

void _noop(String _) {}

/// Launches a Flutter app as a detached background process and waits for the
/// VM service URI to appear in the log.
///
/// Progress messages are emitted via [onProgress]. Warnings are prefixed with
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
    final dartDefines = input.dartDefines;
    final dartDefineFromFiles = input.dartDefineFromFiles;
    String? deviceLabel;

    if (device == null) return const LaunchMissingDevice();
    onProgress('launch: preparing session');

    initLaunchSession(project: project, sessionDir: input.sessionDir);

    // Kill any previous controller.
    final oldControllerPid = readControllerPid();
    if (oldControllerPid != null && isProcessAlive(oldControllerPid)) {
      try {
        Process.killPid(oldControllerPid, ProcessSignal.sigterm);
      } catch (_) {}
    }

    // Kill any previous log collector.
    final oldCollectorPid = readLogCollectorPid();
    if (oldCollectorPid != null && isProcessAlive(oldCollectorPid)) {
      try {
        Process.killPid(oldCollectorPid, ProcessSignal.sigterm);
      } catch (_) {}
    }

    // Clean up previous state.
    cleanupLaunchSessionFiles();

    // Create .fdb/ session directory and persist device ID.
    ensureSessionDir();
    _ensureGitignored(project);
    File(deviceFile).writeAsStringSync(device);

    // Resolve the flutter binary: explicit --flutter-sdk, FVM auto-detect, or PATH.
    final flutter = resolveFlutterBinary(
      project,
      explicitSdk: flutterSdk,
      onWarning: onProgress,
    );

    // Resolve and persist the target platform + emulator flag for this device.
    // Used by `fdb screenshot` to dispatch to the correct capture backend.
    // Non-fatal: screenshot falls back to the old heuristic if this fails.
    deviceLabel = await writePlatformInfoForLaunch(device, flutter);

    // Persist the app bundle id / package name for later use by crash-report.
    // Non-fatal: crash-report will ask the user for --app-id if this fails.
    writeAppIdFromProjectForLaunch(project);

    final controllerLaunch = _resolveControllerLaunch();

    final controllerArgs = buildLaunchControllerArgs(
      controllerLaunch.arguments,
      sessionDir: ensureSessionDir(),
      project: project,
      device: device,
      flutter: flutter,
      flavor: flavor,
      target: target,
      dartDefines: dartDefines,
      dartDefineFromFiles: dartDefineFromFiles,
      verbose: verbose,
    );

    late final Process controllerProcess;
    try {
      onProgress('launch: starting controller');
      controllerProcess = await Process.start(
        controllerLaunch.executable,
        controllerArgs,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      return LaunchLauncherFailed(e.toString());
    }
    File(controllerPidFile).writeAsStringSync(controllerProcess.pid.toString());

    // Guard against Ctrl-C / SIGTERM during the poll loop: kill the controller
    // so it does not linger as an orphan after the fdb process exits.
    final sigintSub = ProcessSignal.sigint.watch().listen((_) {
      try {
        Process.killPid(controllerProcess.pid, ProcessSignal.sigterm);
      } catch (_) {}
      exit(1);
    });
    final sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
      try {
        Process.killPid(controllerProcess.pid, ProcessSignal.sigterm);
      } catch (_) {}
      exit(1);
    });

    // Poll log file for VM service URI.
    final stopwatch = Stopwatch()..start();
    var lastHeartbeat = 0;
    var reportedLogLines = 0;
    String? vmUri;
    onProgress('launch: starting Flutter on ${deviceLabel ?? 'device $device'}');

    try {
      while (stopwatch.elapsed.inSeconds < launchTimeoutSeconds) {
        await Future<void>.delayed(const Duration(milliseconds: pollIntervalMs));

        // Heartbeat so the caller knows we're not stuck.
        final elapsedSeconds = stopwatch.elapsed.inSeconds;
        if (elapsedSeconds ~/ heartbeatIntervalSeconds > lastHeartbeat) {
          lastHeartbeat = elapsedSeconds ~/ heartbeatIntervalSeconds;
          onProgress(
            'launch: still waiting for VM service (${elapsedSeconds}s elapsed)',
          );
        }

        // Check if the controller process died unexpectedly.
        if (!_isAlive(controllerProcess.pid)) {
          final logExists = File(logFile).existsSync();
          if (logExists) {
            final logContent = File(logFile).readAsStringSync();
            return LaunchProcessDied(fullLog: logContent);
          } else {
            return const LaunchProcessDied(noLogFile: true);
          }
        }

        if (!File(logFile).existsSync()) continue;

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
        return LaunchTimeout(tailLogLines: tailLogLines);
      }

      final pid = readLaunchPid();

      return LaunchSuccess(
        vmServiceUri: vmUri,
        pid: pid,
        logFilePath: logFile,
      );
    } finally {
      await sigintSub.cancel();
      await sigtermSub.cancel();
    }
  } catch (e) {
    return LaunchError(e.toString());
  }
}

List<String> buildLaunchControllerArgs(
  List<String> controllerEntrypointArgs, {
  required String sessionDir,
  required String project,
  required String device,
  required String flutter,
  String? flavor,
  String? target,
  required List<String> dartDefines,
  required List<String> dartDefineFromFiles,
  required bool verbose,
}) => [
  ...controllerEntrypointArgs,
  '--session-dir',
  sessionDir,
  '--project',
  project,
  '--device',
  device,
  '--flutter',
  flutter,
  if (flavor != null) ...['--flavor', flavor],
  if (target != null) ...['--target', target],
  for (final define in dartDefines) ...['--dart-define', define],
  for (final file in dartDefineFromFiles) ...['--dart-define-from-file', file],
  if (verbose) '--verbose',
];

/// Reads the app or flutter-tools PID written during launch.
///
/// Returns an empty string until one of the expected PID files exists.
String readLaunchPid() {
  for (final path in [appPidFile, pidFile]) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }

    final pid = file.readAsStringSync().trim();
    if (pid.isNotEmpty) {
      return pid;
    }
  }

  return '';
}

/// Removes launch-owned session files before starting a new launch.
void cleanupLaunchSessionFiles() {
  for (final path in [
    pidFile,
    appPidFile,
    controllerPidFile,
    controllerPortFile,
    controllerTokenFile,
    logFile,
    logCollectorPidFile,
    logCollectorScript,
    vmUriFile,
    launcherScript,
    deviceFile,
    platformFile,
    appIdFile,
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

class _ControllerLaunchCommand {
  const _ControllerLaunchCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

_ControllerLaunchCommand _resolveControllerLaunch() {
  final localController = _findLocalControllerEntrypoint();
  if (localController != null) {
    return _ControllerLaunchCommand(
      Platform.resolvedExecutable,
      [localController],
    );
  }

  return const _ControllerLaunchCommand('fdb-controller', []);
}

void initLaunchSession({
  required String project,
  String? sessionDir,
}) {
  if (sessionDir != null) {
    initSessionDirFromPath(sessionDir);
  } else {
    initSessionDir(project);
  }
}

String? _progressFromLogLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  const prefixes = [
    'Resolving dependencies',
    'Downloading packages',
    'Got dependencies',
    'Launching ',
    'Running Gradle task',
    'Building Linux application',
    'Building macOS application',
    'Building Windows application',
    'Installing ',
    'Syncing files',
  ];

  for (final prefix in prefixes) {
    if (trimmed.startsWith(prefix)) {
      return 'flutter: $trimmed';
    }
  }

  if (trimmed.startsWith('✓ Built ')) {
    return 'flutter: $trimmed';
  }

  return null;
}

String? _findLocalControllerEntrypoint() {
  final scriptDir = Directory.fromUri(Platform.script).parent;
  final packageRoot = scriptDir.parent;
  final controller = File('${packageRoot.path}/bin/controller.dart');
  final pubspec = File('${packageRoot.path}/pubspec.yaml');

  if (!controller.existsSync() || !pubspec.existsSync()) {
    return null;
  }

  try {
    final content = pubspec.readAsStringSync();
    if (!content.contains('name: fdb')) {
      return null;
    }
    return controller.path;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Platform info
// ---------------------------------------------------------------------------

/// Queries flutter devices --machine to find the targetPlatform, emulator flag,
/// and friendly name for [device].
///
/// Silently no-ops on any failure — screenshot falls back gracefully if the
/// platform file is absent.
Future<String?> writePlatformInfoForLaunch(
  String device,
  String flutter, {
  ProcessRunner processRunner = Process.run,
}) async {
  try {
    final result = await processRunner(flutter, ['devices', '--machine']);
    if (result.exitCode != 0) return null;

    final json = extractDevicesJson(result.stdout as String);
    if (json == null) return null;

    final List<dynamic> devices;
    try {
      devices = jsonDecode(json) as List<dynamic>;
    } catch (_) {
      return null;
    }

    for (final d in devices) {
      final map = d as Map<String, dynamic>;
      if (map['id'] == device) {
        final platform = map['targetPlatform'] as String?;
        final emulator = map['emulator'] as bool? ?? false;
        if (platform != null) writePlatformInfo(platform, emulator);
        return map['name'] as String? ?? device;
      }
    }
    return null;
  } on TimeoutException {
    return null;
  } catch (_) {
    // Non-fatal: screenshot will work without platform info.
    return null;
  }
}

// ---------------------------------------------------------------------------
// App id
// ---------------------------------------------------------------------------

/// Reads the app bundle id (iOS/macOS) or application id (Android) from the
/// project's native config files and persists it to [appIdFile].
///
/// Silently no-ops on any failure — crash-report falls back to --app-id flag.
void writeAppIdFromProjectForLaunch(String projectPath) {
  try {
    final platformInfo = readPlatformInfo();
    final platform = platformInfo?.platform ?? '';
    final isIos = platform.startsWith('ios');
    final isMacos = platform == 'macos' || platform.startsWith('darwin');
    final hasPlatformHint = isIos || isMacos || platform.startsWith('android');

    if (!hasPlatformHint) {
      final candidates = {
        ...[
          _readIosAppId(projectPath),
          _readMacosAppId(projectPath),
          _readAndroidAppId(projectPath),
        ].whereType<String>(),
      };

      if (candidates.length == 1) {
        writeAppId(candidates.single);
      }
      return;
    }

    final extractors = <String? Function()>[
      if (isIos) () => _readIosAppId(projectPath),
      if (isMacos) () => _readMacosAppId(projectPath),
      if (!isIos && !isMacos) () => _readAndroidAppId(projectPath),
      if (!isIos) () => _readIosAppId(projectPath),
      if (!isMacos) () => _readMacosAppId(projectPath),
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

String? _readIosAppId(String projectPath) {
  final file = File('$projectPath/ios/Runner/Info.plist');
  if (!file.existsSync()) return null;

  final id = _extractPlistBundleId(file.readAsStringSync());
  if (id != null) return id;

  return _resolvePbxprojBundleId('$projectPath/ios/Runner.xcodeproj/project.pbxproj');
}

String? _readMacosAppId(String projectPath) {
  final file = File('$projectPath/macos/Runner/Info.plist');
  if (!file.existsSync()) return null;

  final id = _extractPlistBundleId(file.readAsStringSync());
  if (id != null) return id;

  return _resolveXcconfigBundleId('$projectPath/macos/Runner/Configs/AppInfo.xcconfig') ??
      _resolvePbxprojBundleId('$projectPath/macos/Runner.xcodeproj/project.pbxproj');
}

String? _readAndroidAppId(String projectPath) {
  for (final path in ['$projectPath/android/app/build.gradle.kts', '$projectPath/android/app/build.gradle']) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }

    final appId = _extractApplicationId(file.readAsStringSync());
    if (appId != null) {
      return appId;
    }
  }

  return null;
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
