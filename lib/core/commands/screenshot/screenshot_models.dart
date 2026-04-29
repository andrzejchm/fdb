import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [captureScreenshot].
typedef ScreenshotInput = ({String output, bool fullResolution});

/// Result of a [captureScreenshot] invocation.
///
/// Warnings are accumulated during capture (e.g. fallback notices) and
/// returned alongside the outcome so CLI / MCP adapters can emit them in the
/// appropriate format and ordering.
sealed class ScreenshotResult extends CommandResult {
  const ScreenshotResult();
}

/// Screenshot was captured, optionally downscaled, and saved to [path].
class ScreenshotSaved extends ScreenshotResult {
  final String path;
  final int sizeBytes;

  /// Accumulated WARNING lines (already prefixed with "WARNING: …").
  final List<String> warnings;

  const ScreenshotSaved({
    required this.path,
    required this.sizeBytes,
    this.warnings = const [],
  });
}

/// Screenshot capture or post-processing failed.
class ScreenshotFailed extends ScreenshotResult {
  /// Error description WITHOUT the leading "ERROR: " prefix.
  final String message;

  /// Accumulated WARNING lines emitted before the failure (already prefixed).
  final List<String> warnings;

  const ScreenshotFailed({required this.message, this.warnings = const []});
}
