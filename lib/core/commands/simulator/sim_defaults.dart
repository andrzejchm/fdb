import 'package:fdb/core/commands/simulator/simulator_models.dart';
import 'package:fdb/core/commands/simulator/simulator_utils.dart';

export 'package:fdb/core/commands/simulator/simulator_models.dart';

/// Reads NSUserDefaults for a given bundle ID on the iOS simulator.
///
/// When [input.key] is null, reads all defaults for the bundle.
/// When [input.key] is provided, reads that specific key.
///
/// Uses `xcrun simctl spawn <device> defaults read <bundleId> [key]`.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimDefaultsResult> readSimDefaults(SimDefaultsReadInput input) async {
  final device = await resolveSimulatorDevice();
  final bundleId = input.bundleId;

  final args = <String>[
    'spawn',
    device,
    'defaults',
    'read',
    bundleId,
    if (input.key != null) input.key!,
  ];

  final result = await runSimctlWithOutput(args);
  if (result.error != null) {
    return SimDefaultsFailed(result.error!);
  }
  return SimDefaultsReadSuccess(output: result.stdout!.trim());
}

/// Writes an NSUserDefaults value for a given bundle ID on the iOS simulator.
///
/// Uses `xcrun simctl spawn <device> defaults write <bundleId> <key> -<type> <value>`.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimDefaultsResult> writeSimDefaults(SimDefaultsWriteInput input) async {
  final device = await resolveSimulatorDevice();
  final bundleId = input.bundleId;

  final args = <String>[
    'spawn',
    device,
    'defaults',
    'write',
    bundleId,
    input.key,
    '-${input.type}',
    input.value,
  ];

  final error = await runSimctl(args);
  if (error != null) {
    return SimDefaultsFailed(error);
  }
  return SimDefaultsWritten(key: input.key, value: input.value);
}

/// Deletes an NSUserDefaults key for a given bundle ID on the iOS simulator.
///
/// Uses `xcrun simctl spawn <device> defaults delete <bundleId> <key>`.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimDefaultsResult> deleteSimDefaults(SimDefaultsDeleteInput input) async {
  final device = await resolveSimulatorDevice();
  final bundleId = input.bundleId;

  final args = <String>[
    'spawn',
    device,
    'defaults',
    'delete',
    bundleId,
    input.key,
  ];

  final error = await runSimctl(args);
  if (error != null) {
    return SimDefaultsFailed(error);
  }
  return SimDefaultsDeleted(key: input.key);
}
