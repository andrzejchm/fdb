import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/mem/mem_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

export 'package:fdb/core/commands/mem/mem_models.dart';

// ---------------------------------------------------------------------------
// fdb mem — per-isolate heap totals
// ---------------------------------------------------------------------------

/// Returns heap usage totals for every isolate in the running VM.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<MemResult> getHeapUsage(MemInput _) async {
  try {
    final isolateIds = await findAllIsolateIds();
    final infos = <IsolateHeapInfo>[];
    for (final id in isolateIds) {
      try {
        final mem = await getMemoryUsage(id);
        final heapUsage = mem.heapUsage;
        final externalUsage = mem.externalUsage;
        final heapCapacity = mem.heapCapacity;
        if (heapUsage == null || externalUsage == null || heapCapacity == null) {
          continue;
        }
        infos.add(IsolateHeapInfo(
          id: id,
          name: await _isolateName(id),
          heapUsage: heapUsage,
          externalUsage: externalUsage,
          heapCapacity: heapCapacity,
        ));
      } on AppDiedException {
        rethrow;
      } catch (_) {
        // Skip isolates that don't expose getMemoryUsage (e.g. system isolates).
      }
    }
    return MemSuccess(infos);
  } on AppDiedException catch (e) {
    return MemAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return MemError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// fdb mem profile — capture allocation profile
// ---------------------------------------------------------------------------

/// Captures a full allocation profile and writes it to [input.outputPath].
///
/// Single-isolate: returns [MemProfileSuccess] with the actual file path.
/// Multi-isolate (`allIsolates: true`): writes one file per isolate using the
/// pattern `<stem>_<isolateName>.json`; returns [MemProfileMultiSuccess].
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<MemProfileResult> captureMemProfile(MemProfileInput input) async {
  try {
    final List<String> targetIds;

    if (input.allIsolates) {
      targetIds = await findAllIsolateIds();
      if (targetIds.isEmpty) return const MemProfileError('No isolates found in running VM');
    } else if (input.isolateId != null) {
      final allIds = await findAllIsolateIds();
      if (!allIds.contains(input.isolateId)) return MemProfileIsolateNotFound(input.isolateId!);
      targetIds = [input.isolateId!];
    } else {
      final id = await findFlutterIsolateId() ?? (await findAllIsolateIds()).firstOrNull;
      if (id == null) return const MemProfileError('No isolates found in running VM');
      targetIds = [id];
    }

    if (targetIds.length == 1) return _captureIsolateProfile(targetIds.first, input.outputPath);

    // Multi-isolate: one file per isolate, name resolved once and reused for
    // both the filename and the MemProfileSuccess inside _captureIsolateProfile.
    var totalClasses = 0;
    final writtenPaths = <String>[];
    final writtenNames = <String>[];
    for (final id in targetIds) {
      final name = await _isolateName(id);
      final path = '${_stripExtension(input.outputPath)}_${_safeFileName(name)}.json';
      final r = await _captureIsolateProfile(id, path, resolvedName: name);
      if (r is MemProfileSuccess) {
        totalClasses += r.classCount;
        writtenPaths.add(r.outputPath);
        writtenNames.add(r.isolateName);
      } else {
        return r; // Propagate first error.
      }
    }
    return MemProfileMultiSuccess(outputPaths: writtenPaths, isolateNames: writtenNames, classCount: totalClasses);
  } on AppDiedException catch (e) {
    return MemProfileAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return MemProfileError(e.toString());
  }
}

Future<MemProfileResult> _captureIsolateProfile(
  String isolateId,
  String outputPath, {
  String? resolvedName,
}) async {
  final profileResult = await getAllocationProfile(isolateId);
  final members = profileResult.members;
  if (members == null) {
    return const MemProfileError('getAllocationProfile returned no result');
  }

  final isolateName = resolvedName ?? await _isolateName(isolateId);
  final classes = _parseAllocationMembers(members);

  final profile = MemProfile(
    isolateId: isolateId,
    isolateName: isolateName,
    capturedAt: DateTime.now().toUtc(),
    classes: classes,
  );

  final file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(profile.toJson()));

  return MemProfileSuccess(outputPath: outputPath, classCount: classes.length, isolateName: isolateName);
}

/// Converts the `members` array from `getAllocationProfile` into [ClassAlloc] objects.
List<ClassAlloc> _parseAllocationMembers(List<dynamic> members) {
  final classes = <ClassAlloc>[];
  for (final entry in members) {
    final m = entry as Map<String, dynamic>;
    final classRef = m['class'] as Map<String, dynamic>?;
    if (classRef == null) continue;
    final newSpace = m['new'] as Map<String, dynamic>?;
    final oldSpace = m['old'] as Map<String, dynamic>?;
    classes.add(ClassAlloc(
      className: (classRef['name'] as String?) ?? '<unknown>',
      libraryUri: (classRef['library'] as Map<String, dynamic>?)?['uri'] as String? ?? '',
      instancesCurrent: _sumSpaces(newSpace, oldSpace, 'count'),
      bytesCurrent: _sumSpaces(newSpace, oldSpace, 'size'),
    ));
  }
  return classes;
}

int _sumSpaces(Map<String, dynamic>? newSpace, Map<String, dynamic>? oldSpace, String key) =>
    ((newSpace?[key] as num?)?.toInt() ?? 0) + ((oldSpace?[key] as num?)?.toInt() ?? 0);

// ---------------------------------------------------------------------------
// fdb mem diff — diff two allocation profiles
// ---------------------------------------------------------------------------

/// Computes the allocation diff between two profile files.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<MemDiffResult> diffMemProfiles(MemDiffInput input) async {
  try {
    final (beforeErr, beforeProfile) = await _loadProfile(input.beforePath);
    if (beforeErr != null) return MemDiffReadError(beforeErr);
    final (afterErr, afterProfile) = await _loadProfile(input.afterPath);
    if (afterErr != null) return MemDiffReadError(afterErr);

    final b = beforeProfile!;
    final a = afterProfile!;

    if (b.isolateId != a.isolateId && b.isolateName != a.isolateName) {
      return MemDiffIsolateMismatch(beforeIsolateName: b.isolateName, afterIsolateName: a.isolateName);
    }

    final beforeMap = {for (final c in b.classes) '${c.className}|${c.libraryUri}': c};
    final afterMap = {for (final c in a.classes) '${c.className}|${c.libraryUri}': c};

    final diffs = <ClassDiff>[];
    for (final key in {...beforeMap.keys, ...afterMap.keys}) {
      final bc = beforeMap[key];
      final ac = afterMap[key];
      final instancesBefore = bc?.instancesCurrent ?? 0;
      final instancesAfter = ac?.instancesCurrent ?? 0;
      final bytesBefore = bc?.bytesCurrent ?? 0;
      final bytesAfter = ac?.bytesCurrent ?? 0;
      if (instancesBefore == instancesAfter && bytesBefore == bytesAfter) continue;
      final ref = bc ?? ac!;
      diffs.add(ClassDiff(
        className: ref.className,
        libraryUri: ref.libraryUri,
        instancesBefore: instancesBefore,
        instancesAfter: instancesAfter,
        bytesBefore: bytesBefore,
        bytesAfter: bytesAfter,
      ));
    }

    diffs.sort((x, y) => input.sort == MemDiffSort.bytes
        ? y.bytesDelta.abs().compareTo(x.bytesDelta.abs())
        : y.instanceDelta.abs().compareTo(x.instanceDelta.abs()));

    return MemDiffSuccess(
      diffs: input.topN != null ? diffs.take(input.topN!).toList() : diffs,
      beforeIsolateName: b.isolateName,
      afterIsolateName: a.isolateName,
      sort: input.sort,
    );
  } catch (e) {
    return MemDiffError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Resolves the human-readable name for an isolate ID from the VM service.
Future<String> _isolateName(String isolateId) async {
  final result = await getIsolate(isolateId);
  return result.name ?? isolateId;
}

/// Returns `(errorMessage, profile)`. Exactly one of the two is non-null.
Future<(String?, MemProfile?)> _loadProfile(String path) async {
  try {
    final profile = MemProfile.fromJson(jsonDecode(await File(path).readAsString()) as Map<String, dynamic>);
    return (null, profile);
  } on FileSystemException catch (e) {
    return ('Cannot read profile "$path": ${e.message}', null);
  } on FormatException catch (e) {
    return ('Cannot parse profile "$path": $e', null);
  }
}

String _safeFileName(String name) => name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

String _stripExtension(String path) {
  final lastDot = path.lastIndexOf('.');
  final lastSlash = path.lastIndexOf('/');
  if (lastDot > lastSlash) return path.substring(0, lastDot);
  return path;
}

// ---------------------------------------------------------------------------
// fdb mem native — platform-native memory snapshot
// ---------------------------------------------------------------------------

/// Shells out to a platform-native memory tool and returns its raw output.
///
/// Platform dispatch:
///   Android       — adb shell dumpsys meminfo `<appId>`
///   iOS simulator — vmmap `<pid>`
///   iOS physical  — unsupported in v1; returns [MemNativeUnsupportedPlatform]
///   macOS         — footprint `<pid>` (default) or vmmap `<pid>` (--tool vmmap)
///
/// The exact command is reported via [onCommand] before execution so callers
/// can echo it to stderr.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<MemNativeResult> runMemNative(
  MemNativeInput input, {
  void Function(String command)? onCommand,
}) async {
  try {
    final platformInfo = readPlatformInfo();
    if (platformInfo == null) {
      return const MemNativeError('No platform info found. Is the app running?');
    }

    final platform = platformInfo.platform.toLowerCase();
    final emulator = platformInfo.emulator;
    final device = readDevice();

    if (platform.startsWith('android')) {
      return _runAndroid(input: input, device: device, onCommand: onCommand);
    } else if (platform == 'ios' || platform.startsWith('ios-')) {
      if (emulator) {
        return _runIosSimulator(input: input, onCommand: onCommand);
      } else {
        return const MemNativeUnsupportedPlatform(
          platform: 'ios-physical',
          message: 'fdb mem native is not supported on physical iOS devices in v1. '
              'Use Xcode Instruments (Product > Profile > Allocations) for native iOS memory profiling.',
        );
      }
    } else if (platform == 'darwin' || platform == 'macos') {
      return _runMacos(input: input, onCommand: onCommand);
    } else {
      return MemNativeUnsupportedPlatform(
        platform: platform,
        message: 'fdb mem native is not supported on platform: $platform',
      );
    }
  } catch (e) {
    return MemNativeError(e.toString());
  }
}

Future<MemNativeResult> _runAndroid({
  required MemNativeInput input,
  required String? device,
  required void Function(String command)? onCommand,
}) async {
  if (input.tool != null && input.tool != 'dumpsys') {
    return MemNativeError(
      'Unknown tool "${input.tool}". Supported tools on Android: dumpsys',
    );
  }

  if (!isToolOnPath('adb')) {
    return const MemNativeToolMissing(
      tool: 'adb',
      hint: 'Install Android SDK platform-tools and ensure adb is on PATH.',
    );
  }

  final appId = input.appId ?? readAppId();
  if (appId == null || appId.isEmpty) {
    return const MemNativeMissingInfo(
      'Could not resolve package name. '
      'Pass --app-id <package> or run from a project that was launched with fdb.',
    );
  }

  final adbArgs = <String>[
    if (device != null) ...['-s', device],
    'shell',
    'dumpsys',
    'meminfo',
    appId,
  ];

  final cmd = 'adb ${adbArgs.join(' ')}';
  onCommand?.call(cmd);

  return _captureOutput(executable: 'adb', args: adbArgs);
}

Future<MemNativeResult> _runIosSimulator({
  required MemNativeInput input,
  required void Function(String command)? onCommand,
}) async {
  if (input.tool != null && input.tool != 'vmmap') {
    return MemNativeError(
      'Unknown tool "${input.tool}". Supported tools on iOS simulator: vmmap',
    );
  }

  if (!isToolOnPath('vmmap')) {
    return const MemNativeToolMissing(
      tool: 'vmmap',
      hint: 'vmmap is bundled with Xcode command-line tools: xcode-select --install',
    );
  }

  final pid = input.pid ?? readAppPid();
  if (pid == null) {
    return const MemNativeMissingInfo(
      'Could not resolve process PID. '
      'Pass --pid <pid> or run from a project that was launched with fdb.',
    );
  }

  final vmmapArgs = [pid.toString()];
  final cmd = 'vmmap ${vmmapArgs.join(' ')}';
  onCommand?.call(cmd);

  return _captureOutput(executable: 'vmmap', args: vmmapArgs);
}

Future<MemNativeResult> _runMacos({
  required MemNativeInput input,
  required void Function(String command)? onCommand,
}) async {
  final toolName = input.tool ?? 'footprint';

  if (toolName != 'footprint' && toolName != 'vmmap') {
    return MemNativeError('Unknown tool "$toolName". Supported tools on macOS: footprint, vmmap');
  }

  if (!isToolOnPath(toolName)) {
    return MemNativeToolMissing(
      tool: toolName,
      hint: toolName == 'footprint'
          ? 'footprint is bundled with Xcode command-line tools: xcode-select --install'
          : 'vmmap is bundled with Xcode command-line tools: xcode-select --install',
    );
  }

  final pid = input.pid ?? readAppPid();
  if (pid == null) {
    return const MemNativeMissingInfo(
      'Could not resolve process PID. '
      'Pass --pid <pid> or run from a project that was launched with fdb.',
    );
  }

  final toolArgs = [pid.toString()];
  final cmd = '$toolName ${toolArgs.join(' ')}';
  onCommand?.call(cmd);

  return _captureOutput(executable: toolName, args: toolArgs);
}

/// Runs [executable] with [args], collects all stdout, and returns [MemNativeSuccess].
///
/// Stderr from the child process is piped to the host stderr directly.
Future<MemNativeResult> _captureOutput({
  required String executable,
  required List<String> args,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, args);
  } catch (e) {
    return MemNativeError('Failed to start $executable: $e');
  }

  // Pipe stderr through so the user can see tool errors/warnings.
  process.stderr.transform(const SystemEncoding().decoder).listen(stderr.write);

  final buffer = StringBuffer();
  await for (final chunk in process.stdout.transform(const SystemEncoding().decoder)) {
    buffer.write(chunk);
  }

  await process.exitCode; // wait for process to finish

  return MemNativeSuccess(buffer.toString());
}
