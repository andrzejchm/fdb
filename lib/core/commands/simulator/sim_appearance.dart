import 'package:fdb/core/commands/simulator/simulator_models.dart';
import 'package:fdb/core/commands/simulator/simulator_utils.dart';

export 'package:fdb/core/commands/simulator/simulator_models.dart';

/// Sets or queries the iOS simulator appearance (dark/light mode).
///
/// When [input.mode] is `"get"`, queries the current appearance.
/// Otherwise sets the appearance to the given mode.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimAppearanceResult> setSimAppearance(SimAppearanceInput input) async {
  final device = await resolveSimulatorDevice();
  final mode = input.mode;

  if (mode == 'get') {
    final result = await runSimctlWithOutput(['ui', device, 'appearance']);
    if (result.error != null) {
      return SimAppearanceFailed(result.error!);
    }
    return SimAppearanceQueried(mode: result.stdout!.trim());
  }

  final error = await runSimctl(['ui', device, 'appearance', mode]);
  if (error != null) {
    return SimAppearanceFailed(error);
  }
  return SimAppearanceSet(mode: mode);
}
