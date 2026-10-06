import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart' as constants;
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

/// First fdb_helper release that reports its version. A helper that stays
/// silent is older than this.
const helperVersionReportingSince = '1.13.0';

/// Upper bound for [queryRunningHelperVersion] so a hung VM never stalls doctor.
const helperVersionQueryTimeout = Duration(seconds: 2);

/// JSON-RPC "method not found": the extension is not registered.
const _methodNotFound = -32601;

/// What the running app reported about its fdb_helper version.
sealed class RunningHelperVersion {
  const RunningHelperVersion();

  /// Reads the version from an `ext.fdb.describe` / `ext.fdb.lifecycle`
  /// payload. A payload without the field comes from a pre-1.13 helper.
  factory RunningHelperVersion.fromPayload(Map<String, dynamic> payload) {
    final version = payload['fdbHelperVersion'];
    return version is String && version.isNotEmpty ? HelperVersionReported(version) : const HelperVersionNotReported();
  }
}

/// The helper reported [version].
class HelperVersionReported extends RunningHelperVersion {
  const HelperVersionReported(this.version);
  final String version;
}

/// The helper answered but does not report a version (older than
/// [helperVersionReportingSince]).
class HelperVersionNotReported extends RunningHelperVersion {
  const HelperVersionNotReported();
}

/// The version could not be queried (no session, no helper, VM unreachable).
class HelperVersionUnavailable extends RunningHelperVersion {
  const HelperVersionUnavailable();
}

/// Returns the `WARNING: ...` lines for [running] compared to the version the
/// project resolves ([resolved], null when unknown) and the fdb CLI version
/// ([cliVersion]). Empty when everything lines up or nothing is known.
List<String> helperVersionWarnings({
  required RunningHelperVersion running,
  required String? resolved,
  String cliVersion = constants.version,
}) {
  const rebuild = 'Hot reload/restart does not reload it; stop and rebuild the app (fdb kill, then fdb launch).';
  const unreported = 'an fdb_helper that does not report its version (older than 1.13)';
  final warnings = <String>[];

  switch (running) {
    case HelperVersionUnavailable():
      break;
    case HelperVersionReported(:final version):
      if (resolved != null && resolved != version) {
        warnings.add('WARNING: The app runs fdb_helper $version but the project resolves $resolved. $rebuild');
      }
      if (_isOlderMajorMinor(version, cliVersion)) {
        warnings
            .add('WARNING: fdb $cliVersion with fdb_helper $version; update fdb_helper to ^$cliVersion and rebuild.');
      }
    case HelperVersionNotReported():
      // Only conclusive once the resolved helper (or fdb itself) is new enough
      // to report a version; before that a silent helper is expected.
      if (resolved != null && !_isOlderMajorMinor(resolved, helperVersionReportingSince)) {
        warnings.add('WARNING: The app runs $unreported but the project resolves $resolved. $rebuild');
      }
      if (!_isOlderMajorMinor(cliVersion, helperVersionReportingSince)) {
        warnings.add('WARNING: fdb $cliVersion with $unreported; update fdb_helper to ^$cliVersion and rebuild.');
      }
  }
  return warnings;
}

/// True when [a]'s major.minor is lower than [b]'s. False when either does
/// not parse.
bool _isOlderMajorMinor(String a, String b) {
  final pa = _majorMinor(a);
  final pb = _majorMinor(b);
  if (pa == null || pb == null) return false;
  return pa.$1 != pb.$1 ? pa.$1 < pb.$1 : pa.$2 < pb.$2;
}

(int, int)? _majorMinor(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version.trim());
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// Returns the fdb_helper version the Flutter project at [projectPath]
/// resolves, from `.dart_tool/package_config.json`, or null when it cannot be
/// determined (no `pub get` yet, no fdb_helper dependency, unreadable files).
///
/// Path and git dependencies are read from the package's `pubspec.yaml`;
/// hosted ones fall back to the `fdb_helper-X.Y.Z` cache directory name.
String? readResolvedHelperVersion(String projectPath) {
  try {
    final configFile = File('$projectPath/.dart_tool/package_config.json');
    if (!configFile.existsSync()) return null;
    final config = jsonDecode(configFile.readAsStringSync());
    if (config is! Map || config['packages'] is! List) return null;

    for (final entry in config['packages'] as List) {
      if (entry is! Map || entry['name'] != 'fdb_helper') continue;
      final rootUri = entry['rootUri'];
      if (rootUri is! String) return null;

      // rootUri is relative to the package_config.json file itself.
      final root = configFile.absolute.uri.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
      final rootPath = root.toFilePath();
      final pubspec = File('${rootPath}pubspec.yaml');
      if (pubspec.existsSync()) {
        final match = RegExp(r'^version:\s*([^\s#]+)', multiLine: true).firstMatch(pubspec.readAsStringSync());
        if (match != null) return match.group(1)!.replaceAll(RegExp('''['"]'''), '');
      }
      final segments = root.pathSegments.where((s) => s.isNotEmpty);
      final dirMatch = RegExp(r'^fdb_helper-(\d+\.\d+\.\d+\S*)$').firstMatch(segments.isEmpty ? '' : segments.last);
      return dirMatch?.group(1);
    }
    return null;
  } catch (_) {
    // Advisory only — never fail the calling command.
    return null;
  }
}

/// [readResolvedHelperVersion] for the active session's project.
String? readSessionResolvedHelperVersion() {
  try {
    return readResolvedHelperVersion(readProjectPath());
  } catch (_) {
    return null;
  }
}

/// Best-effort query of the running helper's version via `ext.fdb.lifecycle`.
/// Never throws.
Future<RunningHelperVersion> queryRunningHelperVersion({Duration timeout = helperVersionQueryTimeout}) async {
  try {
    return await _queryRunningHelperVersion().timeout(timeout);
  } catch (_) {
    return const HelperVersionUnavailable();
  }
}

Future<RunningHelperVersion> _queryRunningHelperVersion() async {
  final isolateId = await findFlutterIsolateId();
  if (isolateId == null) return const HelperVersionUnavailable();

  final response = await extCall('ext.fdb.lifecycle', params: {'isolateId': isolateId});
  // A helper too old for ext.fdb.lifecycle (MethodNotFound) also predates
  // version reporting.
  if (response.errorCode == _methodNotFound) return const HelperVersionNotReported();
  if (response.errorCode != null) return const HelperVersionUnavailable();

  final payload = response.extensionResult;
  final inner = payload?['result'];
  final map = inner is Map ? inner : payload;
  if (map == null) return const HelperVersionUnavailable();
  return RunningHelperVersion.fromPayload(Map<String, dynamic>.from(map));
}
