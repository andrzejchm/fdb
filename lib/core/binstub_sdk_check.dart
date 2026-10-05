/// Detects (and repairs) pub-generated `fdb` / `fdb-controller` launchers that
/// point at a snapshot compiled by a different Dart SDK than the `dart` on PATH.
///
/// Background: `dart pub global activate` writes a POSIX binstub into
/// `PUB_CACHE/bin/` that hardcodes
/// `dart "PUB_CACHE/global_packages/fdb/bin/fdb.dart-X.Y.Z.snapshot"`, where
/// `X.Y.Z` is the SDK that ran the activation. `dart` itself is resolved from
/// PATH at run time. When those differ (FVM, asdf, Homebrew upgrades, ...), the
/// VM prints `Can't load Kernel binary: Invalid kernel binary format version`,
/// exits 253, and the binstub falls back to `dart pub global run fdb:fdb`,
/// which compiles/runs `fdb.dart-<running>.snapshot`. Every call pays the
/// error line and the extra startup.
///
/// The error line is printed by the VM before any fdb code runs, so the
/// current call cannot hide it. What fdb can do is repoint the binstub to the
/// snapshot that the fallback just used, so future calls go straight to it.
///
/// Detection signal: in both the direct and the fallback path,
/// `Platform.script` is `PUB_CACHE/global_packages/fdb/bin/<script>.dart-<running>.snapshot`
/// (verified with a git-activated probe package whose binstub was pointed at
/// an incompatible snapshot). A path activation (`--source path`) runs from
/// `<repo>/.dart_tool/pub/bin/...` and its binstub has no snapshot reference,
/// so it is correctly ignored.
library;

import 'dart:io';

/// Binstub file names (in `PUB_CACHE/bin/`) owned by the fdb package.
const binstubNames = ['fdb', 'fdb-controller'];

/// Env var that disables the automatic rewrite (detection still runs).
const binstubRepairOptOutEnv = 'FDB_NO_BINSTUB_REPAIR';

typedef BinstubSdkCheckInput = ({
  /// `PUB_CACHE` root. Null means it could not be determined → no-op.
  String? pubCacheDir,

  /// Version string of the running VM, e.g. `3.12.2` (first token of
  /// `Platform.version`). Snapshot file names use this exact string.
  String runningDartVersion,

  /// File path of the running script (`Platform.script.toFilePath()`).
  String scriptPath,

  /// False when [binstubRepairOptOutEnv] is set — detect only.
  bool repairEnabled,

  /// Binstubs on Windows are `.bat` files with a different format → no-op.
  bool isWindows,
});

sealed class BinstubSdkCheckResult {
  const BinstubSdkCheckResult();
}

/// Nothing to do: not a global activation, Windows, or no mismatch found.
class BinstubSdkCheckNoOp extends BinstubSdkCheckResult {
  const BinstubSdkCheckNoOp();
}

/// At least one binstub was rewritten. [unrepaired] lists any other fdb
/// binstubs that are mismatched but could not be fixed (usually empty).
class BinstubSdkCheckRepaired extends BinstubSdkCheckResult {
  const BinstubSdkCheckRepaired(this.repairs, {this.unrepaired = const []});

  final List<BinstubRepair> repairs;
  final List<BinstubMismatch> unrepaired;
}

/// Mismatched binstubs were found but none could be rewritten.
class BinstubSdkCheckUnrepaired extends BinstubSdkCheckResult {
  const BinstubSdkCheckUnrepaired(this.mismatches);

  final List<BinstubMismatch> mismatches;
}

typedef BinstubRepair = ({String binstub, String from, String to});

enum BinstubUnrepairedReason {
  /// No snapshot compiled by the running SDK exists for this script yet.
  snapshotMissing,

  /// [binstubRepairOptOutEnv] is set.
  optedOut,

  /// Reading/writing the binstub failed (e.g. permissions).
  writeFailed,
}

typedef BinstubMismatch = ({
  String binstub,
  String from,
  String to,
  BinstubUnrepairedReason reason,
  String? detail,
});

/// Builds a [BinstubSdkCheckInput] from the real process environment.
BinstubSdkCheckInput binstubSdkCheckInputFromPlatform() {
  final env = Platform.environment;
  String? pubCache = env['PUB_CACHE'];
  if (pubCache == null || pubCache.isEmpty) {
    final home = env['HOME'];
    pubCache = (home == null || home.isEmpty) ? null : '$home/.pub-cache';
  }
  String scriptPath;
  try {
    scriptPath = Platform.script.toFilePath();
  } catch (_) {
    // Non-file script URI (e.g. data: URI) — cannot be a global activation.
    scriptPath = '';
  }
  return (
    pubCacheDir: pubCache,
    runningDartVersion: Platform.version.split(' ').first,
    scriptPath: scriptPath,
    repairEnabled: env[binstubRepairOptOutEnv] != '1',
    isWindows: Platform.isWindows,
  );
}

/// Matches `global_packages/fdb/bin/<script>.dart-<version>.snapshot` inside a
/// binstub. Group 1 = script name, group 2 = SDK version.
final _snapshotRef = RegExp(r'global_packages/fdb/bin/([A-Za-z0-9_]+)\.dart-([^"\s/]+)\.snapshot');

/// Checks the fdb binstubs in `PUB_CACHE/bin/` and repoints any that reference
/// a snapshot from a different SDK than [BinstubSdkCheckInput.runningDartVersion],
/// provided the running SDK's snapshot already exists. File I/O only; never
/// throws.
BinstubSdkCheckResult checkBinstubSdk(BinstubSdkCheckInput input) {
  try {
    final pubCache = input.pubCacheDir;
    if (input.isWindows || pubCache == null || input.runningDartVersion.isEmpty) {
      return const BinstubSdkCheckNoOp();
    }
    if (!isRunningFromGlobalActivation(pubCacheDir: pubCache, scriptPath: input.scriptPath)) {
      return const BinstubSdkCheckNoOp();
    }

    final repairs = <BinstubRepair>[];
    final mismatches = <BinstubMismatch>[];
    for (final name in binstubNames) {
      final outcome = _checkOne(
        binstubPath: '$pubCache/bin/$name',
        pubCache: pubCache,
        running: input.runningDartVersion,
        repairEnabled: input.repairEnabled,
      );
      switch (outcome) {
        case null:
          break;
        case final BinstubRepair r:
          repairs.add(r);
        case final BinstubMismatch m:
          mismatches.add(m);
      }
    }

    if (repairs.isNotEmpty) return BinstubSdkCheckRepaired(repairs, unrepaired: mismatches);
    if (mismatches.isNotEmpty) return BinstubSdkCheckUnrepaired(mismatches);
    return const BinstubSdkCheckNoOp();
  } catch (_) {
    // Best-effort diagnostic — never break the actual command.
    return const BinstubSdkCheckNoOp();
  }
}

/// True when [scriptPath] lives under `PUB_CACHE/global_packages/fdb/`.
bool isRunningFromGlobalActivation({required String pubCacheDir, required String scriptPath}) {
  if (scriptPath.isEmpty) return false;
  final prefixes = <String>{_withSlash('$pubCacheDir/global_packages/fdb')};
  final resolved = _tryResolve(pubCacheDir);
  if (resolved != null) prefixes.add(_withSlash('$resolved/global_packages/fdb'));
  final scripts = <String>{scriptPath};
  final resolvedScript = _tryResolve(scriptPath);
  if (resolvedScript != null) scripts.add(resolvedScript);
  return scripts.any((s) => prefixes.any(s.startsWith));
}

String _withSlash(String p) => p.endsWith('/') ? p : '$p/';

String? _tryResolve(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } catch (_) {
    return null; // Missing path — compare unresolved only.
  }
}

/// Returns null when the binstub is absent, not ours, or already matching.
Object? _checkOne({
  required String binstubPath,
  required String pubCache,
  required String running,
  required bool repairEnabled,
}) {
  final file = File(binstubPath);
  if (!file.existsSync()) return null;

  final String content;
  try {
    content = file.readAsStringSync();
  } catch (_) {
    return null; // Unreadable — nothing we can say about it.
  }
  if (!content.split('\n').any((l) => l.trim() == '# Package: fdb')) return null;

  final stale = _snapshotRef.allMatches(content).where((m) => m.group(2) != running).toList();
  if (stale.isEmpty) return null;

  final from = stale.first.group(2)!;
  BinstubMismatch mismatch(BinstubUnrepairedReason reason, [String? detail]) =>
      (binstub: binstubPath, from: from, to: running, reason: reason, detail: detail);

  final scripts = stale.map((m) => m.group(1)!).toSet();
  for (final script in scripts) {
    final target = File('$pubCache/global_packages/fdb/bin/$script.dart-$running.snapshot');
    if (!target.existsSync() || target.lengthSync() == 0) {
      return mismatch(BinstubUnrepairedReason.snapshotMissing, target.path);
    }
  }

  if (!repairEnabled) return mismatch(BinstubUnrepairedReason.optedOut);

  final updated = content.replaceAllMapped(
    _snapshotRef,
    (m) => 'global_packages/fdb/bin/${m.group(1)}.dart-$running.snapshot',
  );
  try {
    _atomicRewrite(file, updated);
  } catch (e) {
    return mismatch(BinstubUnrepairedReason.writeFailed, e is FileSystemException ? _fsMessage(e) : '$e');
  }
  return (binstub: binstubPath, from: from, to: running);
}

String _fsMessage(FileSystemException e) {
  final os = e.osError?.message;
  return os == null || os.isEmpty ? e.message : '${e.message}: $os';
}

/// Replaces [file]'s contents atomically while keeping its permission bits.
///
/// `File.copySync` preserves the source mode on macOS and Linux, so the temp
/// file is created as a copy of the original (inheriting the executable bit),
/// truncated, filled with [content], then renamed over the original. No
/// process is spawned (no `chmod`).
void _atomicRewrite(File file, String content) {
  final tmp = File('${file.path}.fdb-tmp-$pid');
  try {
    file.copySync(tmp.path);
    tmp.writeAsStringSync(content, flush: true);
    if (tmp.statSync().mode != file.statSync().mode) {
      throw const FileSystemException('could not preserve file mode');
    }
    tmp.renameSync(file.path);
  } catch (_) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {
      // Leftover temp file is harmless; the original error is what matters.
    }
    rethrow;
  }
}
