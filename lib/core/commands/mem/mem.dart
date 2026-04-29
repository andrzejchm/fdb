import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/mem/mem_models.dart';
import 'package:fdb/core/vm_service.dart';

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
        final response = await vmServiceCall('getMemoryUsage', params: {'isolateId': id});
        final result = response['result'] as Map<String, dynamic>?;
        if (result == null) continue;

        // Resolve human-readable name from getIsolate.
        final nameResponse = await vmServiceCall('getIsolate', params: {'isolateId': id});
        final isolateResult = nameResponse['result'] as Map<String, dynamic>?;
        final name = (isolateResult?['name'] as String?) ?? id;

        infos.add(
          IsolateHeapInfo(
            id: id,
            name: name,
            heapUsage: (result['heapUsage'] as num).toInt(),
            externalUsage: (result['externalUsage'] as num).toInt(),
            heapCapacity: (result['heapCapacity'] as num).toInt(),
          ),
        );
      } on AppDiedException {
        rethrow;
      } catch (_) {
        // Best-effort: skip isolates that fail (e.g. system isolates that
        // do not expose getMemoryUsage).
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
/// Single-isolate: returns [MemProfileSuccess] with the actual file path written.
///
/// Multi-isolate (`allIsolates: true`): one file per isolate is written using
/// the pattern `<stem>_<isolateName>.json`; returns [MemProfileMultiSuccess]
/// with the list of actual file paths and corresponding isolate names.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<MemProfileResult> captureMemProfile(MemProfileInput input) async {
  try {
    final List<String> targetIds;

    if (input.allIsolates) {
      targetIds = await findAllIsolateIds();
      if (targetIds.isEmpty) {
        return const MemProfileError('No isolates found in running VM');
      }
    } else if (input.isolateId != null) {
      final allIds = await findAllIsolateIds();
      if (!allIds.contains(input.isolateId)) {
        return MemProfileIsolateNotFound(input.isolateId!);
      }
      targetIds = [input.isolateId!];
    } else {
      // Default: use the Flutter UI isolate, fall back to first available.
      final flutterId = await findFlutterIsolateId();
      final fallback = flutterId ?? (await findAllIsolateIds()).firstOrNull;
      if (fallback == null) {
        return const MemProfileError('No isolates found in running VM');
      }
      targetIds = [fallback];
    }

    if (targetIds.length == 1) {
      return _captureIsolateProfile(targetIds.first, input.outputPath);
    }

    // Multi-isolate: write one file per isolate, suffixed with the isolate name.
    var totalClasses = 0;
    final writtenPaths = <String>[];
    final writtenIsolateNames = <String>[];
    for (final id in targetIds) {
      final nameResponse = await vmServiceCall('getIsolate', params: {'isolateId': id});
      final isolateResult = nameResponse['result'] as Map<String, dynamic>?;
      final isolateName = (isolateResult?['name'] as String?) ?? id;
      final path = '${_stripExtension(input.outputPath)}_${_safeFileName(isolateName)}.json';

      final r = await _captureIsolateProfile(id, path);
      if (r is MemProfileSuccess) {
        totalClasses += r.classCount;
        writtenPaths.add(r.outputPath);
        writtenIsolateNames.add(r.isolateName);
      } else {
        return r; // Propagate first error.
      }
    }

    return MemProfileMultiSuccess(
      outputPaths: writtenPaths,
      isolateNames: writtenIsolateNames,
      classCount: totalClasses,
    );
  } on AppDiedException catch (e) {
    return MemProfileAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return MemProfileError(e.toString());
  }
}

Future<MemProfileResult> _captureIsolateProfile(String isolateId, String outputPath) async {
  final profileResponse = await vmServiceCall(
    'getAllocationProfile',
    params: {'isolateId': isolateId},
  );
  final profileResult = profileResponse['result'] as Map<String, dynamic>?;
  if (profileResult == null) {
    return const MemProfileError('getAllocationProfile returned no result');
  }

  final nameResponse = await vmServiceCall('getIsolate', params: {'isolateId': isolateId});
  final isolateResult = nameResponse['result'] as Map<String, dynamic>?;
  final isolateName = (isolateResult?['name'] as String?) ?? isolateId;

  final rawMembers = profileResult['members'] as List<dynamic>? ?? [];
  final classes = <ClassAlloc>[];
  for (final entry in rawMembers) {
    final m = entry as Map<String, dynamic>;
    final classRef = m['class'] as Map<String, dynamic>?;
    if (classRef == null) continue;

    final className = (classRef['name'] as String?) ?? '<unknown>';
    final libraryUri = (classRef['library'] as Map<String, dynamic>?)?['uri'] as String? ?? '';
    final newSpace = m['new'] as Map<String, dynamic>?;
    final oldSpace = m['old'] as Map<String, dynamic>?;

    final instancesCurrent =
        ((newSpace?['count'] as num?)?.toInt() ?? 0) + ((oldSpace?['count'] as num?)?.toInt() ?? 0);
    final bytesCurrent = ((newSpace?['size'] as num?)?.toInt() ?? 0) + ((oldSpace?['size'] as num?)?.toInt() ?? 0);

    classes.add(
      ClassAlloc(
        className: className,
        libraryUri: libraryUri,
        instancesCurrent: instancesCurrent,
        bytesCurrent: bytesCurrent,
      ),
    );
  }

  final profile = MemProfile(
    isolateId: isolateId,
    isolateName: isolateName,
    capturedAt: DateTime.now().toUtc(),
    classes: classes,
  );

  final file = File(outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(profile.toJson()));

  return MemProfileSuccess(
    outputPath: outputPath,
    classCount: classes.length,
    isolateName: isolateName,
  );
}

// ---------------------------------------------------------------------------
// fdb mem diff — diff two allocation profiles
// ---------------------------------------------------------------------------

/// Computes the allocation diff between two profile files.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<MemDiffResult> diffMemProfiles(MemDiffInput input) async {
  try {
    final MemProfile before;
    final MemProfile after;

    try {
      before = MemProfile.fromJson(
        jsonDecode(await File(input.beforePath).readAsString()) as Map<String, dynamic>,
      );
    } on FileSystemException catch (e) {
      return MemDiffReadError('Cannot read before-profile "${input.beforePath}": ${e.message}');
    } on FormatException catch (e) {
      return MemDiffReadError('Cannot parse before-profile "${input.beforePath}": $e');
    }

    try {
      after = MemProfile.fromJson(
        jsonDecode(await File(input.afterPath).readAsString()) as Map<String, dynamic>,
      );
    } on FileSystemException catch (e) {
      return MemDiffReadError('Cannot read after-profile "${input.afterPath}": ${e.message}');
    } on FormatException catch (e) {
      return MemDiffReadError('Cannot parse after-profile "${input.afterPath}": $e');
    }

    // Allow different isolate IDs as long as names match — restarts change IDs.
    // Reject only when both ID and name differ (clearly different sessions).
    if (before.isolateId != after.isolateId && before.isolateName != after.isolateName) {
      return MemDiffIsolateMismatch(
        beforeIsolateName: before.isolateName,
        afterIsolateName: after.isolateName,
      );
    }

    // Build lookup maps: (className + '|' + libraryUri) → ClassAlloc.
    final beforeMap = {for (final c in before.classes) '${c.className}|${c.libraryUri}': c};
    final afterMap = {for (final c in after.classes) '${c.className}|${c.libraryUri}': c};

    final allKeys = {...beforeMap.keys, ...afterMap.keys};
    final diffs = <ClassDiff>[];

    for (final key in allKeys) {
      final b = beforeMap[key];
      final a = afterMap[key];

      final instancesBefore = b?.instancesCurrent ?? 0;
      final instancesAfter = a?.instancesCurrent ?? 0;
      final bytesBefore = b?.bytesCurrent ?? 0;
      final bytesAfter = a?.bytesCurrent ?? 0;

      if (instancesBefore == instancesAfter && bytesBefore == bytesAfter) continue;

      final ref = b ?? a!;
      diffs.add(
        ClassDiff(
          className: ref.className,
          libraryUri: ref.libraryUri,
          instancesBefore: instancesBefore,
          instancesAfter: instancesAfter,
          bytesBefore: bytesBefore,
          bytesAfter: bytesAfter,
        ),
      );
    }

    // Sort by selected key descending (largest absolute delta first).
    diffs.sort((a, b) {
      return input.sort == MemDiffSort.bytes
          ? b.bytesDelta.abs().compareTo(a.bytesDelta.abs())
          : b.instanceDelta.abs().compareTo(a.instanceDelta.abs());
    });

    final visible = input.topN != null ? diffs.take(input.topN!).toList() : diffs;

    return MemDiffSuccess(
      diffs: visible,
      beforeIsolateName: before.isolateName,
      afterIsolateName: after.isolateName,
      sort: input.sort,
    );
  } catch (e) {
    return MemDiffError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _safeFileName(String name) => name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

String _stripExtension(String path) {
  final lastDot = path.lastIndexOf('.');
  final lastSlash = path.lastIndexOf('/');
  if (lastDot > lastSlash) return path.substring(0, lastDot);
  return path;
}
