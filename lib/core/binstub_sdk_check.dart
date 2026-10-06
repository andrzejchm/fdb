/// Replaces pub's `fdb` / `fdb-controller` launchers, once, with launchers
/// that pick the snapshot for the Dart SDK on PATH at run time.
///
/// Background: `dart pub global activate` writes a POSIX launcher into
/// `PUB_CACHE/bin/` that hardcodes
/// `dart "PUB_CACHE/global_packages/fdb/bin/fdb.dart-X.Y.Z.snapshot"`, where
/// `X.Y.Z` is the SDK that ran the activation. `dart` itself is resolved from
/// PATH at run time. When those differ (FVM, asdf, Homebrew upgrades, ...), the
/// VM prints `Can't load Kernel binary: Invalid kernel binary format version`,
/// exits 253, and the launcher falls back to `dart pub global run fdb:fdb`,
/// which builds/runs `fdb.dart-<running>.snapshot`.
///
/// Repointing the launcher at the running SDK's snapshot does not work when
/// two SDKs are in use (e.g. a project pinned via FVM and a different global
/// `dart`): every switch would rewrite it again and the error line would come
/// back each time. Instead, the first time a mismatch is seen, fdb writes
/// [runtimeLauncher]: it reads the running SDK's version from its `version`
/// file (no extra process), runs that snapshot if it exists, and otherwise
/// uses `dart pub global run`. That launcher works for every SDK, so fdb never
/// writes it again (it carries [launcherMarker]). Pub overwrites it on the
/// next `dart pub global activate`, which is fine.
///
/// Detection signal: in both the direct and the fallback path,
/// `Platform.script` is `PUB_CACHE/global_packages/fdb/bin/<script>.dart-<running>.snapshot`.
/// A path activation (`--source path`) runs from `<repo>/.dart_tool/pub/bin/...`
/// and its launcher has no snapshot reference, so it is ignored.
library;

import 'dart:io';

/// Launcher file names (in `PUB_CACHE/bin/`) owned by the fdb package.
const binstubNames = ['fdb', 'fdb-controller'];

/// Env var that disables replacing the launchers.
const binstubRepairOptOutEnv = 'FDB_NO_BINSTUB_REPAIR';

/// Line that identifies a launcher written by fdb. fdb never rewrites a
/// launcher that contains it.
const launcherMarker = '# fdb-launcher: picks the snapshot for the Dart SDK on PATH at run time.';

typedef BinstubSdkCheckInput = ({
  /// `PUB_CACHE` root. Null means it could not be determined → no-op.
  String? pubCacheDir,

  /// Version string of the running VM, e.g. `3.12.2` (first token of
  /// `Platform.version`). Snapshot file names use this exact string.
  String runningDartVersion,

  /// File path of the running script (`Platform.script.toFilePath()`).
  String scriptPath,

  /// False when [binstubRepairOptOutEnv] is set → no-op.
  bool repairEnabled,

  /// Launchers on Windows are `.bat` files with a different format → no-op.
  bool isWindows,
});

sealed class BinstubSdkCheckResult {
  const BinstubSdkCheckResult();
}

/// Nothing to do: not a global activation, Windows, opted out, no mismatch,
/// or the launchers are already fdb's runtime-resolving ones.
class BinstubSdkCheckNoOp extends BinstubSdkCheckResult {
  const BinstubSdkCheckNoOp();
}

/// At least one launcher was replaced. [failed] lists any that could not be
/// written (usually empty).
class BinstubSdkCheckRepaired extends BinstubSdkCheckResult {
  const BinstubSdkCheckRepaired(this.repairs, {this.failed = const []});

  final List<BinstubRepair> repairs;
  final List<BinstubWriteFailure> failed;
}

/// Mismatched launchers were found but none could be written.
class BinstubSdkCheckUnrepaired extends BinstubSdkCheckResult {
  const BinstubSdkCheckUnrepaired(this.failed);

  final List<BinstubWriteFailure> failed;
}

/// [from] is the SDK version pub's launcher hardcoded, [to] the running one.
typedef BinstubRepair = ({String binstub, String from, String to});

typedef BinstubWriteFailure = ({String binstub, String from, String to, String detail});

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

/// Matches the quoted snapshot path in pub's `dart "..."` line. Group 1 = the
/// `.../global_packages/fdb/bin` directory pub wrote, group 2 = script name,
/// group 3 = SDK version.
final _snapshotRef = RegExp(r'"([^"]*global_packages/fdb/bin)/([A-Za-z0-9_]+)\.dart-([^"/]+)\.snapshot"');

/// Replaces pub's fdb launchers in `PUB_CACHE/bin/` with [runtimeLauncher]
/// when they hardcode a snapshot from a different SDK than
/// [BinstubSdkCheckInput.runningDartVersion]. Launchers that already carry
/// [launcherMarker] are never touched. File I/O only; never throws.
BinstubSdkCheckResult checkBinstubSdk(BinstubSdkCheckInput input) {
  try {
    final pubCache = input.pubCacheDir;
    if (input.isWindows || !input.repairEnabled || pubCache == null || input.runningDartVersion.isEmpty) {
      return const BinstubSdkCheckNoOp();
    }
    if (!isRunningFromGlobalActivation(pubCacheDir: pubCache, scriptPath: input.scriptPath)) {
      return const BinstubSdkCheckNoOp();
    }

    final repairs = <BinstubRepair>[];
    final failed = <BinstubWriteFailure>[];
    for (final name in binstubNames) {
      Object? outcome;
      try {
        outcome = _checkOne(binstubPath: '$pubCache/bin/$name', running: input.runningDartVersion);
      } catch (_) {
        outcome = null; // One bad launcher must not hide the other's result.
      }
      switch (outcome) {
        case final BinstubRepair r:
          repairs.add(r);
        case final BinstubWriteFailure f:
          failed.add(f);
      }
    }

    if (repairs.isNotEmpty) return BinstubSdkCheckRepaired(repairs, failed: failed);
    if (failed.isNotEmpty) return BinstubSdkCheckUnrepaired(failed);
    return const BinstubSdkCheckNoOp();
  } catch (_) {
    // Best-effort — never break the actual command.
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

/// Returns null when the launcher is absent, not ours, already fdb's
/// runtime-resolving launcher, or pub's launcher for the running SDK.
Object? _checkOne({required String binstubPath, required String running}) {
  // Resolve symlinks so the rename replaces the real file, not the link.
  final path = _tryResolve(binstubPath);
  if (path == null) return null;
  final file = File(path);

  final String content;
  try {
    content = file.readAsStringSync();
  } catch (_) {
    return null; // Unreadable — nothing we can say about it.
  }
  final lines = content.split('\n');
  if (!lines.any((l) => l.trim() == '# Package: fdb')) return null;
  if (lines.any((l) => l.trim() == launcherMarker)) return null;

  final ref = _snapshotRef.firstMatch(content);
  if (ref == null || ref.group(3) == running) return null;
  final from = ref.group(3)!;

  // Keep pub's header (shebang + `# Package:` etc.) so pub still recognises
  // the file as fdb's on `activate` / `deactivate`.
  final header = lines.takeWhile((l) => l.startsWith('#')).join('\n');
  final launcher = runtimeLauncher(header: header, snapshotDir: ref.group(1)!, script: ref.group(2)!);
  try {
    _atomicRewrite(file, launcher);
  } catch (e) {
    final detail = e is FileSystemException ? _fsMessage(e) : '$e';
    return (binstub: binstubPath, from: from, to: running, detail: detail);
  }
  return (binstub: binstubPath, from: from, to: running);
}

/// POSIX sh launcher that runs `snapshotDir/script.dart-VERSION.snapshot`,
/// where VERSION is read from the SDK of the `dart` on PATH:
/// `bin/cache/dart-sdk/version` next to a Flutter SDK's `bin/dart` wrapper,
/// or `version` one level above a Dart SDK's `bin/dart`. When the version
/// can't be found (e.g. a version-manager shim) or the snapshot doesn't exist
/// yet, it runs `dart pub global run`, which builds the snapshot for that SDK.
/// Exit code 253 means the VM rejected the snapshot; pub rebuilds it.
String runtimeLauncher({required String header, required String snapshotDir, required String script}) => '''
$header
$launcherMarker
# Written by fdb. `dart pub global activate` replaces it with pub's launcher.
sdk_version=
dart_bin=\$(command -v dart 2>/dev/null)
hops=0
while [ -L "\$dart_bin" ] && [ \$hops -lt 40 ]; do
  link=\$(readlink "\$dart_bin")
  case \$link in
    /*) dart_bin=\$link ;;
    *) dart_bin=\${dart_bin%/*}/\$link ;;
  esac
  hops=\$((hops + 1))
done
case \$dart_bin in
  /*)
    for version_file in "\${dart_bin%/*}/cache/dart-sdk/version" "\${dart_bin%/*}/../version"; do
      if [ -f "\$version_file" ]; then
        read -r sdk_version < "\$version_file"
        break
      fi
    done
    ;;
esac
snapshot="${_shDoubleQuoted(snapshotDir)}/$script.dart-\$sdk_version.snapshot"
if [ -n "\$sdk_version" ] && [ -f "\$snapshot" ]; then
  dart "\$snapshot" "\$@"
  exit_code=\$?
  if [ \$exit_code != 253 ]; then
    exit \$exit_code
  fi
fi
dart pub global run fdb:$script "\$@"
''';

/// Escapes [s] for use inside a double-quoted sh string.
String _shDoubleQuoted(String s) => s.replaceAllMapped(RegExp(r'[\\"$`]'), (m) => '\\${m[0]}');

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
