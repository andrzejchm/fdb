/// Detects when pub's `fdb` launcher was written for a different Dart SDK
/// than the one running fdb.
///
/// `dart pub global activate` writes `PUB_CACHE/bin/fdb`, which runs
/// `PUB_CACHE/global_packages/fdb/bin/fdb.dart-X.Y.Z.snapshot` (X.Y.Z = the
/// activating SDK) with whatever `dart` is on PATH. When those differ, the VM
/// prints `Can't load Kernel binary`, and the launcher falls back to
/// `dart pub global run`, which is what ends up running fdb. fdb only reads
/// the launcher to explain that line; it never writes to the pub cache.
library;

import 'dart:io';

/// Line in the launcher that some earlier fdb builds wrote over pub's. That
/// launcher picks the right snapshot itself, so it gets no warning and is left
/// as is.
const launcherMarker = '# fdb-launcher: picks the snapshot for the Dart SDK on PATH at run time.';

typedef BinstubSdkCheckInput = ({
  /// `PUB_CACHE` root, or null when it could not be determined.
  String? pubCacheDir,

  /// First token of `Platform.version`, e.g. `3.12.2`.
  String runningDartVersion,

  /// `Platform.script.toFilePath()`, or empty for non-file scripts.
  String scriptPath,
  bool isWindows,
});

/// [activated] is the SDK the launcher hardcodes, [running] the current one.
typedef BinstubSdkMismatch = ({String activated, String running});

/// Builds a [BinstubSdkCheckInput] from the real process environment.
BinstubSdkCheckInput binstubSdkCheckInputFromPlatform() {
  final env = Platform.environment;
  var pubCache = env['PUB_CACHE'];
  if (pubCache == null || pubCache.isEmpty) {
    final home = env['HOME'];
    pubCache = (home == null || home.isEmpty) ? null : '$home/.pub-cache';
  }
  var scriptPath = '';
  try {
    scriptPath = Platform.script.toFilePath();
  } catch (_) {
    // Non-file script URI (e.g. data:) — cannot be a global activation.
  }
  return (
    pubCacheDir: pubCache,
    runningDartVersion: Platform.version.split(' ').first,
    scriptPath: scriptPath,
    isWindows: Platform.isWindows,
  );
}

final _snapshotRef = RegExp(r'global_packages/fdb/bin/fdb\.dart-([^"/\s]+)\.snapshot');

/// Returns the mismatch when fdb runs from a global activation and
/// `PUB_CACHE/bin/fdb` hardcodes another SDK's snapshot; otherwise null.
/// Reads files only; never throws.
BinstubSdkMismatch? checkBinstubSdk(BinstubSdkCheckInput input) {
  try {
    final pubCache = input.pubCacheDir;
    final running = input.runningDartVersion;
    if (input.isWindows || pubCache == null || running.isEmpty) return null;
    if (!_isUnder(input.scriptPath, '$pubCache/global_packages/fdb/')) return null;

    final lines = File('$pubCache/bin/fdb').readAsLinesSync();
    if (!lines.any((l) => l.trim() == '# Package: fdb')) return null;
    if (lines.any((l) => l.trim() == launcherMarker)) return null;
    final activated = lines.map(_snapshotRef.firstMatch).nonNulls.firstOrNull?.group(1);
    if (activated == null || activated == running) return null;
    return (activated: activated, running: running);
  } catch (_) {
    return null; // Missing/unreadable launcher — nothing to report.
  }
}

/// True when [path] is under [dir] (a path ending in `/`), comparing both
/// as given and with symlinks resolved.
bool _isUnder(String path, String dir) {
  if (path.isEmpty) return false;
  String? resolve(String p) {
    try {
      return File(p).resolveSymbolicLinksSync();
    } catch (_) {
      return null; // Missing path — compare as given.
    }
  }

  final resolvedDir = resolve(dir);
  final dirs = {dir, if (resolvedDir != null) '$resolvedDir/'};
  final resolvedPath = resolve(path);
  final paths = {path, if (resolvedPath != null) resolvedPath};
  return paths.any((p) => dirs.any(p.startsWith));
}
