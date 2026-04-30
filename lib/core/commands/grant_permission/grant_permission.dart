import 'dart:io';

import 'package:fdb/core/commands/grant_permission/grant_permission_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/grant_permission/grant_permission_models.dart';

// ---------------------------------------------------------------------------
// Permission token → platform-specific name maps
// ---------------------------------------------------------------------------

/// Maps canonical fdb permission tokens to xcrun simctl privacy service names.
const _iosSimctlServices = {
  'camera': 'camera',
  'microphone': 'microphone',
  'location': 'location',
  'location-always': 'location-always',
  'contacts': 'contacts',
  'contacts-read': 'contacts-limited',
  'photos': 'photos',
  'photos-add': 'photos-add',
  'calendar': 'calendar',
  'reminders': 'reminders',
  'motion': 'motion',
  'media-library': 'media-library',
  'siri': 'siri',
};

/// Maps canonical fdb permission tokens to android.permission.* identifiers.
/// Some tokens expand to multiple permissions (granted/revoked together).
const _androidPermissions = {
  'camera': ['android.permission.CAMERA'],
  'microphone': ['android.permission.RECORD_AUDIO'],
  'location': ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION'],
  'location-always': ['android.permission.ACCESS_BACKGROUND_LOCATION'],
  'contacts': ['android.permission.READ_CONTACTS', 'android.permission.WRITE_CONTACTS'],
  'contacts-read': ['android.permission.READ_CONTACTS'],
  'photos': [
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_EXTERNAL_STORAGE',
  ],
  'photos-add': ['android.permission.READ_MEDIA_IMAGES', 'android.permission.READ_EXTERNAL_STORAGE'],
  'calendar': ['android.permission.READ_CALENDAR', 'android.permission.WRITE_CALENDAR'],
  'reminders': ['android.permission.READ_CALENDAR', 'android.permission.WRITE_CALENDAR'],
  'motion': ['android.permission.ACTIVITY_RECOGNITION'],
  'notifications': ['android.permission.POST_NOTIFICATIONS'],
  'media-library': ['android.permission.READ_MEDIA_AUDIO', 'android.permission.READ_EXTERNAL_STORAGE'],
};

/// Maps canonical fdb permission tokens to tccutil service names (macOS).
const _macosServices = {
  'camera': 'Camera',
  'microphone': 'Microphone',
  'location': 'Location',
  'location-always': 'Location',
  'contacts': 'AddressBook',
  'contacts-read': 'ContactsLimited',
  'photos': 'Photos',
  'photos-add': 'PhotosAdd',
  'calendar': 'Calendar',
  'reminders': 'Reminders',
  'media-library': 'MediaLibrary',
  'screen-capture': 'ScreenCapture',
};

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Grants, revokes, or resets a runtime permission for the currently
/// running Flutter app.
///
/// Supported platforms:
///   - iOS simulator  → xcrun simctl privacy
///   - Android        → adb shell pm grant/revoke/reset-permissions
///   - macOS desktop  → tccutil reset (grant/revoke are not supported)
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<GrantPermissionResult> grantPermission(GrantPermissionInput input) async {
  try {
    final platformInfo = readPlatformInfo();
    if (platformInfo == null) return const GrantPermissionNoSession();

    final platform = platformInfo.platform;
    final isEmulator = platformInfo.emulator;

    if (platform.startsWith('android')) {
      return _handleAndroid(input);
    }

    if (platform.startsWith('ios') && isEmulator) {
      return _handleIosSimulator(input);
    }

    if (platform.startsWith('ios') && !isEmulator) {
      return const GrantPermissionPhysicalIosUnsupported();
    }

    if (platform.startsWith('darwin') || platform == 'macos') {
      return _handleMacos(input);
    }

    return GrantPermissionPlatformUnsupported(platform);
  } catch (e) {
    return GrantPermissionError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// iOS simulator — xcrun simctl privacy
// ---------------------------------------------------------------------------

Future<GrantPermissionResult> _handleIosSimulator(GrantPermissionInput input) async {
  final bundleId = input.bundleOverride ?? readAppId();
  if (bundleId == null) return const GrantPermissionNoAppId();

  final action = input.action;

  // --reset-all: reset all services for this bundle (no service arg needed)
  if (input.resetAll) {
    return _runSimctl(['privacy', 'booted', 'reset', 'all', bundleId], permission: 'all', action: action);
  }

  final token = input.permission!;
  final service = _iosSimctlServices[token];
  if (service == null) {
    return GrantPermissionUnknownToken(
      token: token,
      platform: 'ios-simulator',
      supportedTokens: _iosSimctlServices.keys.toList()..sort(),
    );
  }

  final actionStr = _simctlAction(action);
  return _runSimctl(['privacy', 'booted', actionStr, service, bundleId], permission: token, action: action);
}

Future<GrantPermissionResult> _runSimctl(
  List<String> args, {
  required String permission,
  required GrantPermissionAction action,
}) async {
  try {
    final result = await Process.run('xcrun', ['simctl', ...args]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      return GrantPermissionSimctlFailed(details);
    }
    return GrantPermissionIosSimulatorSuccess(
      action: action,
      permission: permission,
      appMayHaveTerminated: action == GrantPermissionAction.grant,
    );
  } catch (e) {
    return GrantPermissionSimctlExecutionFailed(e.toString());
  }
}

String _simctlAction(GrantPermissionAction action) {
  switch (action) {
    case GrantPermissionAction.grant:
      return 'grant';
    case GrantPermissionAction.revoke:
      return 'revoke';
    case GrantPermissionAction.reset:
      return 'reset';
  }
}

// ---------------------------------------------------------------------------
// Android — adb shell pm
// ---------------------------------------------------------------------------

Future<GrantPermissionResult> _handleAndroid(GrantPermissionInput input) async {
  final packageName = input.bundleOverride ?? readAppId();
  if (packageName == null) return const GrantPermissionNoAppId();

  final deviceId = readDevice();
  final deviceArgs = deviceId != null ? ['-s', deviceId] : <String>[];

  // --reset-all maps to pm reset-permissions (system-wide on Android)
  if (input.resetAll) {
    return _runAdbResetPermissions(deviceArgs, packageName);
  }

  final token = input.permission!;
  final androidPerms = _androidPermissions[token];
  if (androidPerms == null) {
    return GrantPermissionUnknownToken(
      token: token,
      platform: 'android',
      supportedTokens: _androidPermissions.keys.toList()..sort(),
    );
  }

  final action = input.action;
  if (action == GrantPermissionAction.reset) {
    // Android has no per-permission reset; revoke all mapped permissions instead.
    return _runAdbPmBatch(deviceArgs, packageName, 'revoke', androidPerms, token, GrantPermissionAction.reset);
  }

  final verb = action == GrantPermissionAction.grant ? 'grant' : 'revoke';
  return _runAdbPmBatch(deviceArgs, packageName, verb, androidPerms, token, action);
}

Future<GrantPermissionResult> _runAdbPmBatch(
  List<String> deviceArgs,
  String packageName,
  String verb,
  List<String> permissions,
  String token,
  GrantPermissionAction action,
) async {
  // Grant/revoke each mapped permission; stop on first failure.
  for (final perm in permissions) {
    final result = await _runAdbPm(deviceArgs, verb, packageName, perm);
    if (result != null) return result;
  }
  return GrantPermissionAndroidSuccess(action: action, permission: token);
}

/// Returns a failure result on error, or null on success.
Future<GrantPermissionResult?> _runAdbPm(
  List<String> deviceArgs,
  String verb,
  String packageName,
  String permission,
) async {
  try {
    final result = await Process.run('adb', [...deviceArgs, 'shell', 'pm', verb, packageName, permission]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      // Some permissions are not declared in the manifest — treat as soft skip,
      // not a hard failure, to allow the batch to continue.
      if (details.contains('has not requested permission')) return null;
      return GrantPermissionAdbFailed(details);
    }
    return null;
  } catch (e) {
    return GrantPermissionAdbExecutionFailed(e.toString());
  }
}

Future<GrantPermissionResult> _runAdbResetPermissions(List<String> deviceArgs, String packageName) async {
  try {
    final result = await Process.run('adb', [...deviceArgs, 'shell', 'pm', 'reset-permissions', packageName]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      return GrantPermissionAdbFailed(details);
    }
    return GrantPermissionAndroidSuccess(action: GrantPermissionAction.reset, permission: 'all');
  } catch (e) {
    return GrantPermissionAdbExecutionFailed(e.toString());
  }
}

// ---------------------------------------------------------------------------
// macOS — tccutil (reset only)
// ---------------------------------------------------------------------------

Future<GrantPermissionResult> _handleMacos(GrantPermissionInput input) async {
  final action = input.action;

  // grant and revoke are not scriptable on macOS with SIP enabled.
  if (action == GrantPermissionAction.grant || action == GrantPermissionAction.revoke) {
    return GrantPermissionMacosGrantUnsupported(action: action);
  }

  final bundleId = input.bundleOverride ?? readAppId();
  if (bundleId == null) return const GrantPermissionNoAppId();

  if (input.resetAll) {
    return _runTccutil('All', 'all', bundleId);
  }

  final token = input.permission!;
  final service = _macosServices[token];
  if (service == null) {
    return GrantPermissionUnknownToken(
      token: token,
      platform: 'macos',
      supportedTokens: _macosServices.keys.toList()..sort(),
    );
  }

  return _runTccutil(service, token, bundleId);
}

Future<GrantPermissionResult> _runTccutil(String service, String canonicalToken, String bundleId) async {
  try {
    final result = await Process.run('tccutil', ['reset', service, bundleId]);
    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      return GrantPermissionTccutilFailed(details);
    }
    return GrantPermissionMacosResetSuccess(permission: canonicalToken);
  } catch (e) {
    return GrantPermissionError(e.toString());
  }
}
