import 'dart:io';

import 'package:fdb/core/binstub_sdk_check.dart';

/// Runs [checkBinstubSdk] against the real environment and writes `WARNING:`
/// lines to stderr when a launcher/SDK mismatch is found. Never throws and
/// never affects the exit code.
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

/// Maps a [BinstubSdkCheckResult] to stderr lines (deduplicated, in order).
List<String> formatBinstubSdkCheckResult(BinstubSdkCheckResult result) {
  final lines = switch (result) {
    BinstubSdkCheckNoOp() => const <String>[],
    BinstubSdkCheckRepaired(:final repairs, :final unrepaired) => [
        ...repairs.map(_repairedLine),
        ...unrepaired.map(_unrepairedLine),
      ],
    BinstubSdkCheckUnrepaired(:final mismatches) => mismatches.map(_unrepairedLine).toList(),
  };
  return lines.toSet().toList();
}

String _repairedLine(BinstubRepair r) =>
    "WARNING: fdb launcher ${r.binstub} referenced a Dart ${r.from} snapshot but 'dart' on PATH is ${r.to}. "
    'Repointed it to the ${r.to} snapshot; the "Can\'t load Kernel binary" line above will not repeat. '
    "To use another SDK, put it first on PATH and re-run your 'dart pub global activate' command.";

String _unrepairedLine(BinstubMismatch m) {
  final reason = switch (m.reason) {
    BinstubUnrepairedReason.optedOut => 'automatic repair disabled by $binstubRepairOptOutEnv=1',
    BinstubUnrepairedReason.writeFailed => 'could not rewrite ${m.binstub}: ${m.detail ?? 'unknown error'}',
  };
  return "WARNING: fdb was activated with Dart ${m.from} but 'dart' on PATH is ${m.to}, "
      'which causes the "Can\'t load Kernel binary" line. '
      "Fix: re-run your 'dart pub global activate fdb ...' command with this SDK, "
      'or put Dart ${m.from} first on PATH. ($reason)';
}
