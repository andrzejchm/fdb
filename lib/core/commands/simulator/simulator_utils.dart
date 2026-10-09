import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/xcrun.dart';

/// Outcome of [resolveSimulatorDevice]: exactly one of [udid] or [error] is set.
typedef SimulatorDeviceResolution = ({String? udid, String? error});

typedef _Simulator = ({String udid, String name, String state, String runtime});

/// Runtime key fragment shared by every iOS (and iPadOS) simulator runtime,
/// e.g. `com.apple.CoreSimulator.SimRuntime.iOS-18-0`.
const _iosRuntimeMarker = '.SimRuntime.iOS-';

/// Resolves the iOS simulator UDID that `xcrun simctl` commands should target.
///
/// Order of precedence:
/// 1. [deviceOverride] (`--device <udid>`) — must be an existing, booted simulator.
/// 2. The session device in `.fdb/device.txt`, when it is an iOS simulator.
///    A session simulator that is not booted is an error: silently targeting
///    another simulator would hit the wrong device. A session device that is
///    not a simulator (Android, macOS, physical iOS) is ignored.
/// 3. The only booted simulator.
///
/// Never falls back to simctl's `booted` keyword, which picks an arbitrary
/// device when more than one simulator is booted. With zero or several booted
/// simulators and nothing to disambiguate, returns an error.
Future<SimulatorDeviceResolution> resolveSimulatorDevice({String? deviceOverride}) async {
  final listing = await _listSimulators();
  if (listing.error != null) {
    return (udid: null, error: listing.error);
  }
  final simulators = listing.simulators!;

  _Simulator? find(String udid) {
    for (final sim in simulators) {
      if (sim.udid.toLowerCase() == udid.toLowerCase()) return sim;
    }
    return null;
  }

  if (deviceOverride != null) {
    final sim = find(deviceOverride);
    if (sim == null) {
      return (
        udid: null,
        error: 'No iOS simulator with UDID $deviceOverride. List them with: xcrun simctl list devices',
      );
    }
    if (sim.state != 'Booted') {
      return (udid: null, error: 'Simulator ${_describe(sim)} is not booted (state: ${sim.state}).');
    }
    return (udid: sim.udid, error: null);
  }

  final sessionDevice = readDevice();
  final sessionSim = sessionDevice == null ? null : find(sessionDevice);
  if (sessionSim != null) {
    if (sessionSim.state != 'Booted') {
      return (
        udid: null,
        error: 'The session simulator ${_describe(sessionSim)} is not booted (state: ${sessionSim.state}). '
            'Boot it, or target another booted simulator with --device <udid>.',
      );
    }
    return (udid: sessionSim.udid, error: null);
  }

  // Only iOS-runtime simulators are auto-pick candidates: a booted watchOS,
  // tvOS or visionOS simulator (e.g. the pair of an iPhone) is not a target.
  final booted = simulators.where((sim) => sim.state == 'Booted' && sim.runtime.contains(_iosRuntimeMarker)).toList();
  if (booted.isEmpty) {
    return (
      udid: null,
      error: 'No booted iOS simulator. Boot one with: xcrun simctl boot <udid>',
    );
  }
  if (booted.length > 1) {
    return (
      udid: null,
      error: 'Multiple booted iOS simulators and no fdb session simulator to choose from. '
          'Pass --device <udid> with one of:\n${booted.map((sim) => '  ${_describe(sim)}').join('\n')}',
    );
  }
  return (udid: booted.single.udid, error: null);
}

String _describe(_Simulator sim) => '${sim.udid} (${sim.name})';

/// Lists every simulator known to `simctl` via `simctl list devices -j`.
Future<({List<_Simulator>? simulators, String? error})> _listSimulators() async {
  final result = await runSimctlWithOutput(['list', 'devices', '-j']);
  if (result.error != null) {
    return (simulators: null, error: result.error);
  }
  try {
    final decoded = jsonDecode(result.stdout!) as Map<String, dynamic>;
    final byRuntime = decoded['devices'] as Map<String, dynamic>;
    final simulators = <_Simulator>[
      for (final entry in byRuntime.entries)
        for (final device in (entry.value as List<dynamic>).cast<Map<String, dynamic>>())
          (
            udid: device['udid'] as String,
            name: device['name'] as String? ?? 'unknown',
            state: device['state'] as String? ?? 'unknown',
            runtime: entry.key,
          ),
    ];
    return (simulators: simulators, error: null);
  } catch (e) {
    return (simulators: null, error: 'Could not parse `xcrun simctl list devices -j` output: $e');
  }
}

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
