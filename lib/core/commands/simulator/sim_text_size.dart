import 'package:fdb/core/commands/simulator/simulator_models.dart';
import 'package:fdb/core/commands/simulator/simulator_utils.dart';

export 'package:fdb/core/commands/simulator/simulator_models.dart';

/// Valid content size values accepted by `xcrun simctl ui <device> content_size`.
const validContentSizes = <String>{
  'extra-small',
  'small',
  'medium',
  'large',
  'extra-large',
  'extra-extra-large',
  'extra-extra-extra-large',
  'accessibility-medium',
  'accessibility-large',
  'accessibility-extra-large',
  'accessibility-extra-extra-large',
  'accessibility-extra-extra-extra-large',
};

/// Sets or queries the Dynamic Type content size on the iOS simulator.
///
/// When [input.size] is `"get"`, queries the current content size.
/// Otherwise sets the content size to the given value.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SimTextSizeResult> setSimTextSize(SimTextSizeInput input) async {
  final device = await resolveSimulatorDevice();
  final size = input.size;

  if (size == 'get') {
    final result = await runSimctlWithOutput(['ui', device, 'content_size']);
    if (result.error != null) {
      return SimTextSizeFailed(result.error!);
    }
    return SimTextSizeQueried(size: result.stdout!.trim());
  }

  final error = await runSimctl(['ui', device, 'content_size', size]);
  if (error != null) {
    return SimTextSizeFailed(error);
  }
  return SimTextSizeSet(size: size);
}
