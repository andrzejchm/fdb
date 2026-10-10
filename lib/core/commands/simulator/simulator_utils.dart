import 'dart:io';

import 'package:fdb/core/xcrun.dart';

// Target resolution is shared with non-simulator commands (deeplink,
// screenshot, grant-permission); re-exported so `fdb simulator` code keeps a
// single import.
export 'package:fdb/core/simulator_device.dart';

/// Runs `xcrun simctl` with the given [args] and returns the result.
///
/// Returns null on success (exit code 0), or an error message string on
/// failure. The caller is responsible for mapping the error into a sealed
/// result variant.
Future<String?> runSimctl(List<String> args) async {
  try {
    final result = await Process.run(xcrunExecutable, ['simctl', ...args]);
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      return err.isNotEmpty ? err : 'simctl exited with code ${result.exitCode}';
    }
    return null;
  } catch (e) {
    return 'Failed to run xcrun simctl: $e';
  }
}

/// Runs `xcrun simctl` and returns `(stdout, error)`.
///
/// On success, `error` is null and `stdout` contains the process output.
/// On failure, `stdout` is null and `error` contains the error message.
Future<({String? stdout, String? error})> runSimctlWithOutput(List<String> args) async {
  try {
    final result = await Process.run(xcrunExecutable, ['simctl', ...args]);
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      return (stdout: null, error: err.isNotEmpty ? err : 'simctl exited with code ${result.exitCode}');
    }
    return (stdout: (result.stdout as String), error: null);
  } catch (e) {
    return (stdout: null, error: 'Failed to run xcrun simctl: $e');
  }
}
