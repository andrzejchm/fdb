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
        final mem =
            (await vmServiceCall('getMemoryUsage', params: {'isolateId': id}))['result'] as Map<String, dynamic>?;
        if (mem == null) continue;
        infos.add(IsolateHeapInfo(
          id: id,
          name: await _isolateName(id),
          heapUsage: (mem['heapUsage'] as num).toInt(),
          externalUsage: (mem['externalUsage'] as num).toInt(),
          heapCapacity: (mem['heapCapacity'] as num).toInt(),
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
  final profileResult = (await vmServiceCall('getAllocationProfile', params: {'isolateId': isolateId}))['result']
      as Map<String, dynamic>?;
  if (profileResult == null) return const MemProfileError('getAllocationProfile returned no result');

  final isolateName = resolvedName ?? await _isolateName(isolateId);
  final classes = _parseAllocationMembers(profileResult['members'] as List<dynamic>? ?? []);

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
  final result =
      (await vmServiceCall('getIsolate', params: {'isolateId': isolateId}))['result'] as Map<String, dynamic>?;
  return (result?['name'] as String?) ?? isolateId;
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
