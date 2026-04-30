import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/crash_report/crash_report.dart';

/// CLI adapter for `fdb crash-report`.
///
/// Output contract:
///
///   CRASH_REPORT_FOUND ENTRIES=N            (success — header line)
///   ---                                     (separator before each entry)
///   LABEL=[iOS sim]                         (per-entry label)
///   FILE=/path/to/crash.ips                 (per-entry file, if available)
///   (raw log text)                          (per-entry raw content)
///   CRASH_REPORT_NONE                       (no records found)
///   ERROR: --app-id is required ...         (missing app id)
///   ERROR: tool not found. hint             (missing tool)
///   ERROR: message                          (generic)
Future<int> runCrashReportCli(List<String> args) => runCliAdapter(
      ArgParser()
        ..addOption(
          'app-id',
          help: 'App bundle id (iOS/macOS) or package name (Android). '
              'Auto-detected from .fdb/app_id.txt if omitted.',
        )
        ..addOption(
          'last',
          defaultsTo: '1h',
          help: 'Time window to search (e.g. 30s, 5m, 1h). Default: 1h',
        )
        ..addFlag(
          'all',
          negatable: false,
          help: 'Return all crash records in the window, not just the latest.',
        ),
      args,
      _execute,
    );

Future<int> _execute(ArgResults results) async {
  final last = results['last'] as String;
  if (!_isValidDuration(last)) {
    stderr.writeln(
      'ERROR: Invalid --last value: $last. '
      'Use a number followed by s, m, or h (e.g. 30s, 5m, 1h)',
    );
    return 1;
  }

  final input = (
    appId: results['app-id'] as String?,
    last: last,
    all: results['all'] as bool,
  );

  final result = await fetchCrashReport(input);
  return _format(result);
}

int _format(CrashReportResult result) {
  switch (result) {
    case CrashReportFound(:final entries):
      stdout.writeln('CRASH_REPORT_FOUND ENTRIES=${entries.length}');
      for (final entry in entries) {
        stdout.writeln('---');
        stdout.writeln('LABEL=${entry.label}');
        if (entry.filePath != null) {
          stdout.writeln('FILE=${entry.filePath}');
        }
        stdout.writeln(entry.text);
      }
      return 0;

    case CrashReportNone():
      stdout.writeln('CRASH_REPORT_NONE');
      return 0;

    case CrashReportMissingAppId():
      stderr.writeln(
        'ERROR: --app-id is required for this platform. '
        'Pass --app-id <bundle-id-or-package> or run fdb launch first '
        '(it persists the app id to .fdb/app_id.txt).',
      );
      return 1;

    case CrashReportToolMissing(:final tool, :final hint):
      stderr.writeln('ERROR: $tool not found. $hint');
      return 1;

    case CrashReportUnsupportedPlatform(:final platform):
      stderr.writeln('ERROR: crash-report is not supported on platform: $platform');
      return 1;

    case CrashReportNoSession():
      stderr.writeln('ERROR: No platform info found. Is the app running? Run fdb launch first.');
      return 1;

    case CrashReportError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

/// Returns true if [s] is a valid duration string (`<positive-int>[smh]`).
bool _isValidDuration(String s) {
  if (s.isEmpty) return false;
  final suffix = s[s.length - 1];
  if (!const {'s', 'm', 'h'}.contains(suffix)) return false;
  final n = int.tryParse(s.substring(0, s.length - 1));
  return n != null && n > 0;
}
