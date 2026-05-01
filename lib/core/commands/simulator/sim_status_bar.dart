import 'package:fdb/core/commands/simulator/simulator_models.dart';
import 'package:fdb/core/commands/simulator/simulator_utils.dart';

export 'package:fdb/core/commands/simulator/simulator_models.dart';

/// Overrides the iOS simulator status bar with the given values.
///
/// All fields are optional; only the provided fields are overridden.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimStatusBarResult> overrideSimStatusBar(SimStatusBarOverrideInput input) async {
  final device = await resolveSimulatorDevice();
  final args = <String>[
    'status_bar',
    device,
    'override',
    if (input.time != null) ...['--time', input.time!],
    if (input.dataNetwork != null) ...['--dataNetwork', input.dataNetwork!],
    if (input.wifiMode != null) ...['--wifiMode', input.wifiMode!],
    if (input.wifiBars != null) ...['--wifiBars', '${input.wifiBars}'],
    if (input.cellularMode != null) ...['--cellularMode', input.cellularMode!],
    if (input.cellularBars != null) ...['--cellularBars', '${input.cellularBars}'],
    if (input.operatorName != null) ...['--operatorName', input.operatorName!],
    if (input.batteryState != null) ...['--batteryState', input.batteryState!],
    if (input.batteryLevel != null) ...['--batteryLevel', '${input.batteryLevel}'],
  ];

  final error = await runSimctl(args);
  if (error != null) {
    return SimStatusBarFailed(error);
  }
  return const SimStatusBarOverridden();
}

/// Clears all status bar overrides on the iOS simulator.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimStatusBarResult> clearSimStatusBar(SimStatusBarClearInput _) async {
  final device = await resolveSimulatorDevice();
  final error = await runSimctl(['status_bar', device, 'clear']);
  if (error != null) {
    return SimStatusBarFailed(error);
  }
  return const SimStatusBarCleared();
}
