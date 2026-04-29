import 'dart:async';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/process_utils.dart';

/// Thrown when the target Flutter app process has died while fdb is trying to
/// communicate with it via the VM service.
///
/// Carries the last [logLines] from `.fdb/logs.txt` and an optional structured
/// [reason] string (e.g. `jetsam_highwater`, `lmk`, `crash_NullPointerException`)
/// obtained from OS-level log queries.
///
/// Formatted by the top-level error handler in `bin/fdb.dart`.
class AppDiedException implements Exception {
  AppDiedException({required this.logLines, this.reason});

  /// Last N lines from `.fdb/logs.txt`.
  final List<String> logLines;

  /// Optional OS-level reason (jetsam/LMK/native crash). Null if unavailable.
  final String? reason;

  @override
  String toString() => 'AppDiedException(reason: $reason)';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

const _logTailLines = 20;
const _reasonTimeoutSeconds = 3;

/// Reads the last [_logTailLines] lines from `.fdb/logs.txt`.
List<String> readLastLogLines() {
  try {
    final file = File(logFile);
    if (!file.existsSync()) return [];
    final lines = file.readAsLinesSync();
    if (lines.length <= _logTailLines) return lines;
    return lines.sublist(lines.length - _logTailLines);
  } catch (_) {
    return [];
  }
}

/// Builds an [AppDiedException] by reading the log tail and, when possible,
/// performing a best-effort OS-level reason lookup.
///
/// [pid] is used on some platforms; may be null if the PID file was absent.
///
/// This is a shared helper reused by #58 (`fdb crash-report`).
Future<AppDiedException> buildAppDiedException({int? pid}) async {
  final logLines = readLastLogLines();
  final reason = await _lookupCrashReason(pid: pid);
  return AppDiedException(logLines: logLines, reason: reason);
}

/// Tries to determine why the app died from OS-level log sources.
///
/// Returns a compact reason string on success, null on any failure (including
/// the [_reasonTimeoutSeconds] time limit).
///
/// Per-platform strategy:
/// - **iOS simulator**: `xcrun simctl spawn <udid> log show` for jetsam entries.
/// - **Android**: `adb -s <device> logcat -b crash -d -t 50` for LMK / FATAL.
/// - **macOS**: `log show` for crash entries matching the app process.
/// - Others: returns null immediately.
Future<String?> _lookupCrashReason({int? pid}) async {
  try {
    return await _doCrashReasonLookup(pid: pid).timeout(
      const Duration(seconds: _reasonTimeoutSeconds),
    );
  } catch (_) {
    // Intentional: any failure (timeout, OS error, parse error) → null.
    // REASON is a bonus, not a requirement.
    return null;
  }
}

Future<String?> _doCrashReasonLookup({int? pid}) async {
  final info = readPlatformInfo();
  if (info == null) return null;

  final platform = info.platform.toLowerCase();

  if (platform.startsWith('ios') && info.emulator) {
    return _lookupIosSimulatorReason();
  }
  if (platform.startsWith('android')) {
    return _lookupAndroidReason();
  }
  if (platform == 'darwin' || platform == 'macos') {
    return _lookupMacOsReason(pid: pid);
  }
  return null;
}

// ---------------------------------------------------------------------------
// iOS simulator — jetsam lookup
// ---------------------------------------------------------------------------

Future<String?> _lookupIosSimulatorReason() async {
  final device = readDevice();
  if (device == null) return null;

  final result = await Process.run('xcrun', [
    'simctl',
    'spawn',
    device,
    'log',
    'show',
    '--last',
    '30s',
    '--predicate',
    'eventMessage CONTAINS "jetsam"',
  ]);

  if (result.exitCode != 0) return null;

  final output = result.stdout as String;
  // Look for a reason field in jetsam entries, e.g. "jetsam_highwater"
  final match = RegExp(r'jetsam[_-](\w+)', caseSensitive: false).firstMatch(output);
  if (match != null) {
    return 'jetsam_${match.group(1)?.toLowerCase()}';
  }
  if (output.toLowerCase().contains('jetsam')) {
    return 'jetsam';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Android — LMK / FATAL EXCEPTION
// ---------------------------------------------------------------------------

Future<String?> _lookupAndroidReason() async {
  final device = readDevice();
  if (device == null) return null;

  final result = await Process.run('adb', [
    '-s',
    device,
    'logcat',
    '-b',
    'crash',
    '-d',
    '-t',
    '50',
  ]);

  if (result.exitCode != 0) return null;

  final output = result.stdout as String;

  // Low-memory killer
  if (RegExp(r'LowMemoryKiller|kill.*to free', caseSensitive: false).hasMatch(output)) {
    return 'lmk';
  }

  // Fatal exception — extract the exception class
  final fatalMatch = RegExp(
    r'FATAL EXCEPTION.*\n.*\n\s*(\S+Exception|\S+Error)',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(output);
  if (fatalMatch != null) {
    final exClass = fatalMatch.group(1) ?? 'unknown';
    // Trim package prefix
    final shortName = exClass.split('.').last;
    return 'crash_$shortName';
  }

  if (output.contains('FATAL EXCEPTION')) {
    return 'crash';
  }

  return null;
}

// ---------------------------------------------------------------------------
// macOS — log show
// ---------------------------------------------------------------------------

Future<String?> _lookupMacOsReason({int? pid}) async {
  if (pid == null) return null;

  final args = [
    'show',
    '--last',
    '30s',
    '--process',
    pid.toString(),
    '--predicate',
    'eventMessage CONTAINS "crash" OR eventMessage CONTAINS "killed"',
  ];

  final result = await Process.run('log', args);
  if (result.exitCode != 0) return null;

  final output = result.stdout as String;
  if (output.trim().isEmpty) return null;

  if (output.toLowerCase().contains('killed')) return 'killed';
  if (output.toLowerCase().contains('crash')) return 'crash';
  return null;
}
