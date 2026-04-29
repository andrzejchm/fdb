import 'package:fdb/core/models/command_result.dart';

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

/// Schema version written to every profile JSON file.
const _schemaVersion = 1;

/// One isolate's heap snapshot returned by `getMemoryUsage`.
class IsolateHeapInfo {
  const IsolateHeapInfo({
    required this.id,
    required this.name,
    required this.heapUsage,
    required this.externalUsage,
    required this.heapCapacity,
  });

  /// VM isolate ID (e.g. `isolates/123`). Use this as the `--isolate` value.
  final String id;
  final String name;
  final int heapUsage;
  final int externalUsage;
  final int heapCapacity;
}

/// Per-class allocation record inside a profile snapshot.
class ClassAlloc {
  const ClassAlloc({
    required this.className,
    required this.libraryUri,
    required this.instancesCurrent,
    required this.bytesCurrent,
  });

  final String className;
  final String libraryUri;
  final int instancesCurrent;
  final int bytesCurrent;
}

/// A full allocation profile captured by `getAllocationProfile`.
class MemProfile {
  const MemProfile({
    required this.isolateId,
    required this.isolateName,
    required this.capturedAt,
    required this.classes,
  });

  final String isolateId;
  final String isolateName;
  final DateTime capturedAt;
  final List<ClassAlloc> classes;

  Map<String, dynamic> toJson() => {
        'schema': _schemaVersion,
        'isolateId': isolateId,
        'isolateName': isolateName,
        'capturedAt': capturedAt.toIso8601String(),
        'classes': classes
            .map(
              (c) => {
                'className': c.className,
                'libraryUri': c.libraryUri,
                'instancesCurrent': c.instancesCurrent,
                'bytesCurrent': c.bytesCurrent,
              },
            )
            .toList(),
      };

  /// Parses a profile from JSON produced by [toJson].
  ///
  /// Throws [FormatException] for missing/wrong-type fields or wrong schema version.
  static MemProfile fromJson(Map<String, dynamic> json) {
    try {
      final schema = json['schema'];
      if (schema == null) {
        throw const FormatException('Missing required field: schema');
      }
      if (schema != _schemaVersion) {
        throw FormatException(
          'Incompatible profile schema: expected $_schemaVersion, got $schema',
        );
      }

      final isolateId = json['isolateId'];
      if (isolateId is! String) {
        throw const FormatException('Missing or invalid field: isolateId');
      }
      final isolateName = json['isolateName'];
      if (isolateName is! String) {
        throw const FormatException('Missing or invalid field: isolateName');
      }
      final capturedAtRaw = json['capturedAt'];
      if (capturedAtRaw is! String) {
        throw const FormatException('Missing or invalid field: capturedAt');
      }
      final capturedAt = DateTime.tryParse(capturedAtRaw);
      if (capturedAt == null) {
        throw FormatException('Invalid capturedAt value: $capturedAtRaw');
      }

      final rawClasses = json['classes'];
      if (rawClasses is! List) {
        throw const FormatException('Missing or invalid field: classes');
      }

      final classes = rawClasses.map((e) {
        if (e is! Map<String, dynamic>) {
          throw const FormatException('Invalid class entry in classes list');
        }
        final className = e['className'];
        if (className is! String) {
          throw const FormatException('Missing or invalid field: className');
        }
        final libraryUri = e['libraryUri'];
        if (libraryUri is! String) {
          throw const FormatException('Missing or invalid field: libraryUri');
        }
        final instancesCurrent = e['instancesCurrent'];
        if (instancesCurrent is! int) {
          throw const FormatException('Missing or invalid field: instancesCurrent');
        }
        final bytesCurrent = e['bytesCurrent'];
        if (bytesCurrent is! int) {
          throw const FormatException('Missing or invalid field: bytesCurrent');
        }
        return ClassAlloc(
          className: className,
          libraryUri: libraryUri,
          instancesCurrent: instancesCurrent,
          bytesCurrent: bytesCurrent,
        );
      }).toList();

      return MemProfile(
        isolateId: isolateId,
        isolateName: isolateName,
        capturedAt: capturedAt,
        classes: classes,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse profile: $e');
    }
  }
}

/// A single class diff entry (after − before).
class ClassDiff {
  const ClassDiff({
    required this.className,
    required this.libraryUri,
    required this.instancesBefore,
    required this.instancesAfter,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  final String className;
  final String libraryUri;
  final int instancesBefore;
  final int instancesAfter;
  final int bytesBefore;
  final int bytesAfter;

  int get instanceDelta => instancesAfter - instancesBefore;
  int get bytesDelta => bytesAfter - bytesBefore;
}

// ---------------------------------------------------------------------------
// fdb mem  (heap totals)
// ---------------------------------------------------------------------------

/// Input for [getHeapUsage]. No parameters; always targets all isolates.
typedef MemInput = ();

/// Result of [getHeapUsage].
sealed class MemResult extends CommandResult {
  const MemResult();
}

/// Successfully retrieved per-isolate heap info.
class MemSuccess extends MemResult {
  const MemSuccess(this.isolates);
  final List<IsolateHeapInfo> isolates;
}

/// App process died during the call.
class MemAppDied extends MemResult {
  const MemAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class MemError extends MemResult {
  const MemError(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// fdb mem profile  (capture allocation profile)
// ---------------------------------------------------------------------------

/// Input for [captureMemProfile].
typedef MemProfileInput = ({
  /// Specific isolate ID to target (null → use first Flutter isolate).
  String? isolateId,

  /// Where to write the JSON output file.
  String outputPath,

  /// Capture all isolates instead of just one (one file per isolate).
  bool allIsolates,
});

/// Result of [captureMemProfile].
sealed class MemProfileResult extends CommandResult {
  const MemProfileResult();
}

/// Profile captured and written to disk (single isolate).
class MemProfileSuccess extends MemProfileResult {
  const MemProfileSuccess({
    required this.outputPath,
    required this.classCount,
    required this.isolateName,
  });
  final String outputPath;
  final int classCount;
  final String isolateName;
}

/// Profiles captured and written to disk for multiple isolates.
class MemProfileMultiSuccess extends MemProfileResult {
  const MemProfileMultiSuccess({
    required this.outputPaths,
    required this.isolateNames,
    required this.classCount,
  });

  /// Actual file paths written, one per isolate (parallel to [isolateNames]).
  final List<String> outputPaths;

  /// Isolate name for each written file (parallel to [outputPaths]).
  final List<String> isolateNames;

  /// Total class count across all isolates.
  final int classCount;
}

/// Requested isolate ID was not found.
class MemProfileIsolateNotFound extends MemProfileResult {
  const MemProfileIsolateNotFound(this.requestedId);
  final String requestedId;
}

/// App process died during the call.
class MemProfileAppDied extends MemProfileResult {
  const MemProfileAppDied({required this.logLines, this.reason});
  final List<String> logLines;
  final String? reason;
}

/// Generic / unrecognised error.
class MemProfileError extends MemProfileResult {
  const MemProfileError(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// fdb mem diff  (diff two allocation profiles)
// ---------------------------------------------------------------------------

/// Sort key for diff output.
enum MemDiffSort { count, bytes }

/// Input for [diffMemProfiles].
typedef MemDiffInput = ({
  String beforePath,
  String afterPath,

  /// How many top entries to show (null → show all changed).
  int? topN,

  /// Sort key.
  MemDiffSort sort,
});

/// Result of [diffMemProfiles].
sealed class MemDiffResult extends CommandResult {
  const MemDiffResult();
}

/// Diff computed successfully.
class MemDiffSuccess extends MemDiffResult {
  const MemDiffSuccess({
    required this.diffs,
    required this.beforeIsolateName,
    required this.afterIsolateName,
    required this.sort,
  });
  final List<ClassDiff> diffs;
  final String beforeIsolateName;
  final String afterIsolateName;

  /// The sort key applied — callers use this to label the output correctly.
  final MemDiffSort sort;
}

/// One or both profile files could not be read or parsed.
class MemDiffReadError extends MemDiffResult {
  const MemDiffReadError(this.message);
  final String message;
}

/// Profiles come from different isolates and cannot be meaningfully diffed.
class MemDiffIsolateMismatch extends MemDiffResult {
  const MemDiffIsolateMismatch({
    required this.beforeIsolateName,
    required this.afterIsolateName,
  });
  final String beforeIsolateName;
  final String afterIsolateName;
}

/// Generic / unrecognised error.
class MemDiffError extends MemDiffResult {
  const MemDiffError(this.message);
  final String message;
}
