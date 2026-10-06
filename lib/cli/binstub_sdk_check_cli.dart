import 'dart:io';

import 'package:fdb/core/binstub_sdk_check.dart';

/// Runs [checkBinstubSdk] against the real environment and writes `WARNING:`
/// lines to stderr when fdb's launchers were replaced or could not be. Never
/// throws and never affects the exit code.
void runBinstubSdkCheckCli() {
  try {
    final lines = formatBinstubSdkCheckResult(checkBinstubSdk(binstubSdkCheckInputFromPlatform()));
    for (final line in lines) {
      stderr.writeln(line);
    }
  } catch (_) {
    // Diagnostic only — must never break the actual command.
  }
}

/// Maps a [BinstubSdkCheckResult] to stderr lines.
List<String> formatBinstubSdkCheckResult(BinstubSdkCheckResult result) => switch (result) {
      BinstubSdkCheckNoOp() => const <String>[],
      BinstubSdkCheckRepaired(:final binstubs, :final failed) => [
          'WARNING: fdb runs with more than one Dart SDK. Replaced ${binstubs.join(' and ')} with launchers that '
              "run the snapshot for whichever Dart is on PATH, so the \"Can't load Kernel binary\" line won't come "
              "back when you switch SDKs. 'dart pub global activate' restores pub's launchers.",
          ...failed.map(_failedLine),
        ],
      BinstubSdkCheckUnrepaired(:final failed) => failed.map(_failedLine).toList(),
    };

String _failedLine(BinstubWriteFailure f) =>
    "WARNING: fdb was activated with Dart ${f.from} but 'dart' on PATH is ${f.to}, "
    'which causes the "Can\'t load Kernel binary" line. Could not replace ${f.binstub}: ${f.detail}. '
    "Fix: re-run your 'dart pub global activate fdb ...' command with the SDK you use, "
    'or set $binstubRepairOptOutEnv=1 to hide this warning.';
