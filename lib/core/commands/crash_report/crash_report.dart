import 'dart:io';

import 'package:fdb/core/commands/crash_report/crash_report_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/crash_report/crash_report_models.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Fetches the most recent OS-level crash record(s) for the app under debug.
///
/// Platform dispatch:
///   Android       — adb logcat -b crash + adb shell dumpsys dropbox + LMK events
///   iOS simulator — xcrun simctl log show (jetsam/crash predicate) + .ips files
///   iOS physical  — idevicecrashreport (requires libimobiledevice)
///   macOS         — log show + ~/Library/Logs/DiagnosticReports/
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<CrashReportResult> fetchCrashReport(CrashReportInput input) async {
  try {
    final platformInfo = readPlatformInfo();
    if (platformInfo == null) return const CrashReportNoSession();

    final appId = input.appId ?? readAppId();

    final platform = platformInfo.platform.toLowerCase();
    final emulator = platformInfo.emulator;
    final device = readDevice();

    if (platform.startsWith('android')) {
      return _runAndroid(device: device, appId: appId, input: input);
    } else if (platform == 'ios' || platform.startsWith('ios-')) {
      if (emulator) {
        return _runIosSimulator(device: device, appId: appId, input: input);
      } else {
        return _runIosPhysical(appId: appId, input: input);
      }
    } else if (platform == 'darwin' || platform == 'macos') {
      return _runMacos(appId: appId, input: input);
    } else {
      return CrashReportUnsupportedPlatform(platform);
    }
  } catch (e) {
    return CrashReportError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// Platform implementations
// ---------------------------------------------------------------------------

Future<CrashReportResult> _runAndroid({
  required String? device,
  required String? appId,
  required CrashReportInput input,
}) async {
  if (!_isToolOnPath('adb')) {
    return const CrashReportToolMissing(
      tool: 'adb',
      hint: 'Install Android SDK platform-tools and ensure adb is on PATH.',
    );
  }

  final adbPrefix = <String>[
    if (device != null) ...['-s', device]
  ];
  final entries = <CrashReportEntry>[];

  // --- logcat crash buffer ---
  final logcatArgs = [...adbPrefix, 'logcat', '-b', 'crash', '-d'];
  final logcatResult = Process.runSync('adb', logcatArgs);
  final logcatText = (logcatResult.stdout as String).trim();
  if (logcatText.isNotEmpty) {
    final filtered = appId != null ? _filterLines(logcatText, appId) : logcatText;
    if (filtered.isNotEmpty) {
      entries.add(CrashReportEntry(label: '[Android logcat crash]', text: filtered));
    }
  }

  // --- logcat LMK (low memory killer) events ---
  final lmkArgs = [...adbPrefix, 'logcat', '-b', 'system', '-d', '-s', 'lowmemorykiller'];
  final lmkResult = Process.runSync('adb', lmkArgs);
  final lmkText = (lmkResult.stdout as String).trim();
  if (lmkText.isNotEmpty) {
    final filtered = appId != null ? _filterLines(lmkText, appId) : lmkText;
    if (filtered.isNotEmpty) {
      entries.add(CrashReportEntry(label: '[Android LMK]', text: filtered));
    }
  }

  // --- dropbox ---
  final dropboxArgs = [...adbPrefix, 'shell', 'dumpsys', 'dropbox', '--print'];
  final dropboxResult = Process.runSync('adb', dropboxArgs);
  final dropboxText = (dropboxResult.stdout as String).trim();
  if (dropboxText.isNotEmpty && appId != null) {
    final filtered = _filterLines(dropboxText, appId);
    if (filtered.isNotEmpty) {
      entries.add(CrashReportEntry(label: '[Android dropbox]', text: filtered));
    }
  } else if (dropboxText.isNotEmpty && appId == null) {
    entries.add(CrashReportEntry(label: '[Android dropbox]', text: dropboxText));
  }

  if (entries.isEmpty) return const CrashReportNone();

  // Android logcat has no native --last filter. All available records from
  // logcat buffers are returned; the --last flag is ignored.
  // When --all is false, entries.first (logcat crash buffer) is returned as the
  // most likely source of the most recent crash.
  final returnedEntries = input.all ? entries : [entries.first];
  final warnings = [
    '--last is not supported on Android, '
        '${input.all ? 'returning all available records' : 'returning first available record'}',
  ];
  return CrashReportFound(returnedEntries, warnings: warnings);
}

Future<CrashReportResult> _runIosSimulator({
  required String? device,
  required String? appId,
  required CrashReportInput input,
}) async {
  if (!_isToolOnPath('xcrun')) {
    return const CrashReportToolMissing(
      tool: 'xcrun',
      hint: 'Install Xcode command-line tools: xcode-select --install',
    );
  }

  if (device == null) {
    return const CrashReportError('No device ID found. Is the app running?');
  }

  final entries = <CrashReportEntry>[];

  // --- system log: jetsam / crash events ---
  final predicateParts = <String>['eventMessage CONTAINS "jetsam"'];
  if (appId != null) {
    predicateParts.add('eventMessage CONTAINS "$appId"');
  }
  final predicate = predicateParts.join(' OR ');

  // When --all is true, omit --last so the query is not time-bounded.
  final logArgs = [
    'simctl',
    'spawn',
    device,
    'log',
    'show',
    if (!input.all) ...['--last', input.last],
    '--style',
    'compact',
    '--predicate',
    predicate,
  ];

  final logResult = Process.runSync('xcrun', logArgs);
  final logText = (logResult.stdout as String).trim();
  if (logText.isNotEmpty) {
    entries.add(CrashReportEntry(label: '[iOS sim log]', text: logText));
  }

  // --- .ips diagnostic report files ---
  final reportsDir = Directory('${Platform.environment['HOME']}/Library/Logs/DiagnosticReports');
  if (reportsDir.existsSync()) {
    final ipsFiles = reportsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ips') && (appId == null || f.path.contains(appId)))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    final filesToRead = input.all ? ipsFiles : (ipsFiles.isNotEmpty ? [ipsFiles.first] : <File>[]);
    for (final file in filesToRead) {
      final text = _safeReadFile(file);
      if (text != null) {
        entries.add(CrashReportEntry(label: '[iOS sim .ips]', filePath: file.path, text: text));
      }
    }
  }

  if (entries.isEmpty) return const CrashReportNone();
  return CrashReportFound(entries);
}

Future<CrashReportResult> _runIosPhysical({
  required String? appId,
  required CrashReportInput input,
}) async {
  if (!_isToolOnPath('idevicecrashreport')) {
    return const CrashReportToolMissing(
      tool: 'idevicecrashreport',
      hint: 'Install: brew install libimobiledevice',
    );
  }

  if (appId == null) {
    return const CrashReportMissingAppId();
  }

  // The temp dir is intentionally NOT deleted after the call. The caller
  // requested these files and their paths are surfaced via FILE= tokens.
  // Each invocation creates a fresh temp dir so they do not accumulate
  // unboundedly; the OS will eventually reclaim them.
  final tmpDir = Directory.systemTemp.createTempSync('fdb_crash_');
  final result = Process.runSync('idevicecrashreport', ['-e', '-k', appId, tmpDir.path]);
  if (result.exitCode != 0) {
    final err = (result.stderr as String).trim();
    return CrashReportError('idevicecrashreport failed: $err');
  }

  final duration = _parseDuration(input.last);
  final ipsFiles = tmpDir
      .listSync()
      .whereType<File>()
      .where((f) {
        if (!f.path.endsWith('.ips')) return false;
        if (duration == null) return true;
        final cutoff = DateTime.now().subtract(duration);
        return f.statSync().modified.isAfter(cutoff);
      })
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

  if (ipsFiles.isEmpty) return const CrashReportNone();

  final filesToRead = input.all ? ipsFiles : [ipsFiles.first];
  final entries = <CrashReportEntry>[];
  for (final file in filesToRead) {
    final text = _safeReadFile(file);
    if (text != null) {
      entries.add(CrashReportEntry(label: '[iOS physical .ips]', filePath: file.path, text: text));
    }
  }

  if (entries.isEmpty) return const CrashReportNone();
  return CrashReportFound(entries);
}

Future<CrashReportResult> _runMacos({
  required String? appId,
  required CrashReportInput input,
}) async {
  if (!_isToolOnPath('log')) {
    return const CrashReportToolMissing(
      tool: 'log',
      hint: 'This is unexpected on macOS — ensure /usr/bin is on PATH.',
    );
  }

  final entries = <CrashReportEntry>[];

  // --- system log ---
  final logArgs = ['show', '--last', input.last, '--style', 'compact'];
  if (appId != null) {
    logArgs.addAll(['--predicate', 'process == "$appId"']);
  }

  final logResult = Process.runSync('log', logArgs);
  final logText = (logResult.stdout as String).trim();
  if (logText.isNotEmpty) {
    entries.add(CrashReportEntry(label: '[macOS log]', text: logText));
  }

  // --- DiagnosticReports ---
  final reportsDir = Directory('${Platform.environment['HOME']}/Library/Logs/DiagnosticReports');
  if (reportsDir.existsSync()) {
    final ipsFiles = reportsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ips') && (appId == null || f.path.contains(appId)))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    final filesToRead = input.all ? ipsFiles : (ipsFiles.isNotEmpty ? [ipsFiles.first] : <File>[]);
    for (final file in filesToRead) {
      final text = _safeReadFile(file);
      if (text != null) {
        entries.add(CrashReportEntry(label: '[macOS .ips]', filePath: file.path, text: text));
      }
    }
  }

  if (entries.isEmpty) return const CrashReportNone();
  return CrashReportFound(entries);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns true if [tool] can be found via `which`.
bool _isToolOnPath(String tool) {
  try {
    final result = Process.runSync('which', [tool]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Returns only lines containing [substring].
String _filterLines(String text, String substring) =>
    text.split('\n').where((l) => l.contains(substring)).join('\n').trim();

/// Parses a duration string of the form `<n>s`, `<n>m`, or `<n>h`.
/// Returns null if the string cannot be parsed.
Duration? _parseDuration(String s) {
  if (s.isEmpty) return null;
  final suffix = s[s.length - 1];
  final n = int.tryParse(s.substring(0, s.length - 1));
  if (n == null) return null;
  return switch (suffix) {
    's' => Duration(seconds: n),
    'm' => Duration(minutes: n),
    'h' => Duration(hours: n),
    _ => null,
  };
}

/// Reads a file's content, returning null on any error.
String? _safeReadFile(File file) {
  try {
    return file.readAsStringSync();
  } catch (_) {
    return null;
  }
}


