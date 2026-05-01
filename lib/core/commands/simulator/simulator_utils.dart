import 'dart:io';

import 'package:fdb/core/process_utils.dart';

/// Resolves the iOS simulator device target for `xcrun simctl` commands.
///
/// Reads the session device ID from `.fdb/device.txt` if available and verifies
/// it is a booted iOS simulator. Falls back to `"booted"` (simctl's keyword for
/// the last-booted simulator) when no session exists or the session device is
/// not a simulator.
Future<String> resolveSimulatorDevice() async {
  final sessionDevice = readDevice();
  if (sessionDevice != null && await _isBootedSimulator(sessionDevice)) {
    return sessionDevice;
  }
  return 'booted';
}

/// Returns true if [deviceId] appears in the booted iOS simulator list.
Future<bool> _isBootedSimulator(String deviceId) async {
  try {
    final result = await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted']);
    return (result.stdout as String).contains(deviceId);
  } catch (_) {
    return false;
  }
}

/// Runs `xcrun simctl` with the given [args] and returns the result.
///
/// Returns null on success (exit code 0), or an error message string on
/// failure. The caller is responsible for mapping the error into a sealed
/// result variant.
Future<String?> runSimctl(List<String> args) async {
  try {
    final result = await Process.run('xcrun', ['simctl', ...args]);
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
    final result = await Process.run('xcrun', ['simctl', ...args]);
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      return (stdout: null, error: err.isNotEmpty ? err : 'simctl exited with code ${result.exitCode}');
    }
    return (stdout: (result.stdout as String), error: null);
  } catch (e) {
    return (stdout: null, error: 'Failed to run xcrun simctl: $e');
  }
}
