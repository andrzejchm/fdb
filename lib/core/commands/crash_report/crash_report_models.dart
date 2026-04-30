import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [fetchCrashReport].
typedef CrashReportInput = ({
  String? appId,
  String last,
  bool all,
});

// ---------------------------------------------------------------------------
// Result hierarchy
// ---------------------------------------------------------------------------

sealed class CrashReportResult extends CommandResult {
  const CrashReportResult();
}

/// At least one crash record was found and its content is in [entries].
///
/// Each [CrashReportEntry] carries a platform label, a path to the crash file
/// on disk (if any), and the raw log text to display.
///
/// [warnings] carries non-fatal advisory messages (e.g. unsupported flags on
/// a given platform) that the CLI adapter should print to stderr.
class CrashReportFound extends CrashReportResult {
  const CrashReportFound(this.entries, {this.warnings = const []});

  final List<CrashReportEntry> entries;
  final List<String> warnings;
}

/// No crash records were found in the requested time window.
class CrashReportNone extends CrashReportResult {
  const CrashReportNone();
}

/// The app bundle id / package name is required but was not found.
class CrashReportMissingAppId extends CrashReportResult {
  const CrashReportMissingAppId();
}

/// A required platform tool (e.g. `xcrun`, `adb`) was not on PATH.
class CrashReportToolMissing extends CrashReportResult {
  const CrashReportToolMissing({required this.tool, required this.hint});

  final String tool;
  final String hint;
}

/// The platform stored in .fdb/platform.txt is not supported.
class CrashReportUnsupportedPlatform extends CrashReportResult {
  const CrashReportUnsupportedPlatform(this.platform);

  final String platform;
}

/// No platform info was found — app is probably not running.
class CrashReportNoSession extends CrashReportResult {
  const CrashReportNoSession();
}

/// Generic / unrecognised error.
class CrashReportError extends CrashReportResult {
  const CrashReportError(this.message);

  final String message;
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class CrashReportEntry {
  const CrashReportEntry({required this.label, this.filePath, required this.text});

  /// Short human-readable label, e.g. `[iOS sim]` or `[Android]`.
  final String label;

  /// Path to the full crash file on disk, if available.
  final String? filePath;

  /// Raw text of the crash record (log lines or .ips content).
  final String text;
}
