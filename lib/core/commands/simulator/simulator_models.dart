import 'package:fdb/core/models/command_result.dart';

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

typedef SimAppearanceInput = ({String mode});

sealed class SimAppearanceResult extends CommandResult {
  const SimAppearanceResult();
}

class SimAppearanceSet extends SimAppearanceResult {
  const SimAppearanceSet({required this.mode});
  final String mode;
}

class SimAppearanceQueried extends SimAppearanceResult {
  const SimAppearanceQueried({required this.mode});
  final String mode;
}

class SimAppearanceFailed extends SimAppearanceResult {
  const SimAppearanceFailed(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Push notification
// ---------------------------------------------------------------------------

typedef SimPushInput = ({String? bundleId, String payload});

sealed class SimPushResult extends CommandResult {
  const SimPushResult();
}

class SimPushSent extends SimPushResult {
  const SimPushSent({required this.bundleId});
  final String bundleId;
}

class SimPushFailed extends SimPushResult {
  const SimPushFailed(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

typedef SimLocationSetInput = ({String latitude, String longitude});
typedef SimLocationRouteInput = ({String scenario});
typedef SimLocationClearInput = ();

sealed class SimLocationResult extends CommandResult {
  const SimLocationResult();
}

class SimLocationSet extends SimLocationResult {
  const SimLocationSet({required this.latitude, required this.longitude});
  final String latitude;
  final String longitude;
}

class SimLocationRouteStarted extends SimLocationResult {
  const SimLocationRouteStarted({required this.scenario});
  final String scenario;
}

class SimLocationCleared extends SimLocationResult {
  const SimLocationCleared();
}

class SimLocationFailed extends SimLocationResult {
  const SimLocationFailed(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Text size (Dynamic Type / content_size)
// ---------------------------------------------------------------------------

typedef SimTextSizeInput = ({String size});

sealed class SimTextSizeResult extends CommandResult {
  const SimTextSizeResult();
}

class SimTextSizeSet extends SimTextSizeResult {
  const SimTextSizeSet({required this.size});
  final String size;
}

class SimTextSizeQueried extends SimTextSizeResult {
  const SimTextSizeQueried({required this.size});
  final String size;
}

class SimTextSizeFailed extends SimTextSizeResult {
  const SimTextSizeFailed(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

typedef SimStatusBarOverrideInput = ({
  String? time,
  String? dataNetwork,
  String? wifiMode,
  int? wifiBars,
  String? cellularMode,
  int? cellularBars,
  String? operatorName,
  String? batteryState,
  int? batteryLevel,
});

sealed class SimStatusBarResult extends CommandResult {
  const SimStatusBarResult();
}

class SimStatusBarOverridden extends SimStatusBarResult {
  const SimStatusBarOverridden();
}

class SimStatusBarCleared extends SimStatusBarResult {
  const SimStatusBarCleared();
}

class SimStatusBarFailed extends SimStatusBarResult {
  const SimStatusBarFailed(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Defaults (NSUserDefaults via `simctl spawn ... defaults`)
// ---------------------------------------------------------------------------

typedef SimDefaultsReadInput = ({String bundleId, String? key});
typedef SimDefaultsWriteInput = ({String bundleId, String key, String value, String type});
typedef SimDefaultsDeleteInput = ({String bundleId, String key});

sealed class SimDefaultsResult extends CommandResult {
  const SimDefaultsResult();
}

class SimDefaultsReadSuccess extends SimDefaultsResult {
  const SimDefaultsReadSuccess({required this.output});
  final String output;
}

class SimDefaultsWritten extends SimDefaultsResult {
  const SimDefaultsWritten({required this.key, required this.value});
  final String key;
  final String value;
}

class SimDefaultsDeleted extends SimDefaultsResult {
  const SimDefaultsDeleted({required this.key});
  final String key;
}

class SimDefaultsFailed extends SimDefaultsResult {
  const SimDefaultsFailed(this.message);
  final String message;
}
