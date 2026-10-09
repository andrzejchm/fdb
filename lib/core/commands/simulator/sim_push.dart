import 'dart:io';

import 'package:fdb/core/commands/simulator/simulator_models.dart';
import 'package:fdb/core/commands/simulator/simulator_utils.dart';

export 'package:fdb/core/commands/simulator/simulator_models.dart';

/// Sends a simulated push notification to the iOS simulator.
///
/// The [input.payload] is the path to an `.apns` JSON file or `"-"` for stdin.
/// The [input.bundleId] is the target app's bundle ID; if null, it is read from
/// the fdb session (`.fdb/app_id.txt`) or must be embedded in the payload as
/// the `"Simulator Target Bundle"` key.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimPushResult> sendSimPush(SimPushInput input) async {
  // Validate payload file exists (unless reading from stdin) before touching
  // simctl, so a bad path reports the same error however many simulators are booted.
  if (input.payload != '-') {
    final file = File(input.payload);
    if (!file.existsSync()) {
      return SimPushFailed('Payload file not found: ${input.payload}');
    }
  }

  final resolved = await resolveSimulatorDevice(deviceOverride: input.deviceOverride);
  if (resolved.error != null) {
    return SimPushFailed(resolved.error!);
  }
  final device = resolved.udid!;

  final bundleId = input.bundleId;

  final args = <String>[
    'push',
    device,
    if (bundleId != null) bundleId,
    input.payload,
  ];

  final error = await runSimctl(args);
  if (error != null) {
    return SimPushFailed(error);
  }

  return SimPushSent(bundleId: bundleId ?? 'payload');
}
