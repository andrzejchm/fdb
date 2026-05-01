import 'package:fdb/core/commands/simulator/simulator_models.dart';
import 'package:fdb/core/commands/simulator/simulator_utils.dart';

export 'package:fdb/core/commands/simulator/simulator_models.dart';

/// Sets a static GPS location on the iOS simulator.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimLocationResult> setSimLocation(SimLocationSetInput input) async {
  final device = await resolveSimulatorDevice();
  final error = await runSimctl([
    'location',
    device,
    'set',
    '${input.latitude},${input.longitude}',
  ]);
  if (error != null) {
    return SimLocationFailed(error);
  }
  return SimLocationSet(latitude: input.latitude, longitude: input.longitude);
}

/// Starts a built-in location scenario (e.g. "City Run", "Freeway Drive").
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimLocationResult> runSimLocationRoute(SimLocationRouteInput input) async {
  final device = await resolveSimulatorDevice();
  final error = await runSimctl(['location', device, 'run', input.scenario]);
  if (error != null) {
    return SimLocationFailed(error);
  }
  return SimLocationRouteStarted(scenario: input.scenario);
}

/// Stops location simulation on the iOS simulator.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimLocationResult> clearSimLocation(SimLocationClearInput _) async {
  final device = await resolveSimulatorDevice();
  final error = await runSimctl(['location', device, 'clear']);
  if (error != null) {
    return SimLocationFailed(error);
  }
  return const SimLocationCleared();
}
