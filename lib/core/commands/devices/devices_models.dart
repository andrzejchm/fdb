import 'package:fdb/core/models/command_result.dart';

/// A single connected device entry returned by `flutter devices --machine`.
typedef DeviceInfo = ({
  String id,
  String name,
  String platform,
  bool emulator,
});

/// Input parameters for [listDevices]. Empty record because `fdb devices`
/// takes no arguments today.
typedef DevicesInput = ();

/// Result of a [listDevices] invocation.
///
/// The CLI adapter translates these into stdout/stderr tokens; other
/// adapters (MCP, REST) may translate them differently.
sealed class DevicesResult extends CommandResult {
  const DevicesResult();
}

/// At least one device was found; [skippedRaw] holds any entries that were
/// missing required fields (id / name / targetPlatform).
class DevicesListed extends DevicesResult {
  const DevicesListed({required this.devices, this.skippedRaw = const []});

  final List<DeviceInfo> devices;

  /// Raw map entries skipped because required fields were absent.
  final List<Map<String, dynamic>> skippedRaw;
}

/// `flutter devices --machine` exited with a non-zero code.
class DevicesFlutterFailed extends DevicesResult {
  const DevicesFlutterFailed(this.stderrText);

  final String stderrText;
}

/// No JSON array was found in the output, or the device list was empty.
class DevicesNotFound extends DevicesResult {
  const DevicesNotFound();
}

/// The JSON array could not be decoded.
class DevicesParseFailed extends DevicesResult {
  const DevicesParseFailed(this.error);

  final String error;
}
