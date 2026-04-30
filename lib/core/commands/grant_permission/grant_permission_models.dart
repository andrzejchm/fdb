import 'package:fdb/core/models/command_result.dart';

/// The action to perform on a permission.
enum GrantPermissionAction { grant, revoke, reset }

/// Input parameters for [grantPermission].
typedef GrantPermissionInput = ({
  /// Canonical permission token (e.g. 'camera', 'microphone').
  /// Null only when [action] is [GrantPermissionAction.reset] with [resetAll] true.
  String? permission,

  /// The action to perform.
  GrantPermissionAction action,

  /// Reset ALL permissions for the app (iOS sim + macOS) or system-wide (Android).
  bool resetAll,

  /// Override bundle ID / package name (default: read from .fdb/fdb.app_id).
  String? bundleOverride,
});

/// Result of a [grantPermission] invocation.
sealed class GrantPermissionResult extends CommandResult {
  const GrantPermissionResult();
}

/// iOS simulator: grant/revoke/reset succeeded.
class GrantPermissionIosSimulatorSuccess extends GrantPermissionResult {
  const GrantPermissionIosSimulatorSuccess({
    required this.action,
    required this.permission,
    this.appMayHaveTerminated = false,
  });

  final GrantPermissionAction action;
  final String permission;

  /// xcrun simctl warns that some permission changes terminate the app.
  final bool appMayHaveTerminated;
}

/// Android: grant/revoke succeeded.
class GrantPermissionAndroidSuccess extends GrantPermissionResult {
  const GrantPermissionAndroidSuccess({required this.action, required this.permission});

  final GrantPermissionAction action;
  final String permission;
}

/// macOS: reset succeeded (grant/revoke are unsupported on macOS).
class GrantPermissionMacosResetSuccess extends GrantPermissionResult {
  const GrantPermissionMacosResetSuccess({required this.permission});

  final String permission;
}

/// macOS: grant or revoke was requested — only reset is supported.
class GrantPermissionMacosGrantUnsupported extends GrantPermissionResult {
  const GrantPermissionMacosGrantUnsupported({required this.action});

  final GrantPermissionAction action;
}

/// Physical iOS: not supported.
class GrantPermissionPhysicalIosUnsupported extends GrantPermissionResult {
  const GrantPermissionPhysicalIosUnsupported();
}

/// Windows or Linux: not supported.
class GrantPermissionPlatformUnsupported extends GrantPermissionResult {
  const GrantPermissionPlatformUnsupported(this.platform);

  final String platform;
}

/// The permission token is not recognised for the current platform.
class GrantPermissionUnknownToken extends GrantPermissionResult {
  const GrantPermissionUnknownToken({required this.token, required this.supportedTokens});

  final String token;
  final List<String> supportedTokens;
}

/// No app ID in the session and none provided via --bundle.
class GrantPermissionNoAppId extends GrantPermissionResult {
  const GrantPermissionNoAppId();
}

/// No active fdb session found.
class GrantPermissionNoSession extends GrantPermissionResult {
  const GrantPermissionNoSession();
}

/// xcrun simctl exited with a non-zero code.
class GrantPermissionSimctlFailed extends GrantPermissionResult {
  const GrantPermissionSimctlFailed(this.details);

  final String details;
}

/// xcrun could not be launched.
class GrantPermissionSimctlExecutionFailed extends GrantPermissionResult {
  const GrantPermissionSimctlExecutionFailed(this.error);

  final String error;
}

/// adb exited with a non-zero code.
class GrantPermissionAdbFailed extends GrantPermissionResult {
  const GrantPermissionAdbFailed(this.details);

  final String details;
}

/// adb could not be launched.
class GrantPermissionAdbExecutionFailed extends GrantPermissionResult {
  const GrantPermissionAdbExecutionFailed(this.error);

  final String error;
}

/// tccutil exited with a non-zero code.
class GrantPermissionTccutilFailed extends GrantPermissionResult {
  const GrantPermissionTccutilFailed(this.details);

  final String details;
}

/// Generic unexpected error.
class GrantPermissionError extends GrantPermissionResult {
  const GrantPermissionError(this.message);

  final String message;
}
