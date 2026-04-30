import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/grant_permission/grant_permission.dart';

/// CLI adapter for `fdb grant-permission`.
///
/// Output contract:
///
///   PERMISSION_GRANTED=token          (grant succeeded)
///   PERMISSION_REVOKED=token          (revoke succeeded)
///   PERMISSION_RESET=token            (reset succeeded)
///   PERMISSION_RESET_ALL=true         (reset-all succeeded)
///   WARNING: message                  (macOS unsupported; iOS may have terminated)
///   ERROR: message                    (failure; exit 1)
Future<int> runGrantPermissionCli(List<String> args) {
  final parser = ArgParser()
    ..addFlag('revoke', help: 'Revoke the permission instead of granting it', negatable: false)
    ..addFlag('reset', help: 'Reset the permission to undecided (re-prompts on next access)', negatable: false)
    ..addFlag('reset-all', help: 'Reset all permissions for the app', negatable: false)
    ..addOption('bundle', help: 'Override bundle ID / package name (default: read from .fdb/fdb.app_id)');
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  final revoke = results['revoke'] as bool;
  final reset = results['reset'] as bool;
  final resetAll = results['reset-all'] as bool;
  final bundleOverride = results['bundle'] as String?;
  final rest = results.rest;

  // Validate flag combinations.
  final actionFlagCount = [revoke, reset, resetAll].where((f) => f).length;
  if (actionFlagCount > 1) {
    stderr.writeln('ERROR: --revoke, --reset, and --reset-all are mutually exclusive');
    return 1;
  }

  // Permission token is required unless --reset-all.
  if (!resetAll && rest.isEmpty) {
    stderr.writeln('ERROR: Provide a permission token (e.g. camera, microphone, location)');
    return 1;
  }

  if (!resetAll && rest.length > 1) {
    stderr.writeln('ERROR: Only one permission token may be specified at a time');
    return 1;
  }

  final permission = resetAll ? null : rest.first;

  final action = resetAll || reset
      ? GrantPermissionAction.reset
      : revoke
          ? GrantPermissionAction.revoke
          : GrantPermissionAction.grant;

  final result = await grantPermission((
    permission: permission,
    action: action,
    resetAll: resetAll,
    bundleOverride: bundleOverride,
  ));

  return _format(result);
}

int _format(GrantPermissionResult result) {
  switch (result) {
    case GrantPermissionIosSimulatorSuccess(:final action, :final permission, :final appMayHaveTerminated):
      _printSuccess(action, permission);
      if (appMayHaveTerminated) {
        stderr.writeln(
          'WARNING: Permission change may have terminated the app. '
          'Run `fdb reload` or `fdb launch` to restart.',
        );
      }
      return 0;

    case GrantPermissionAndroidSuccess(:final action, :final permission):
      _printSuccess(action, permission);
      return 0;

    case GrantPermissionMacosResetSuccess(:final permission):
      stdout.writeln('PERMISSION_RESET=$permission');
      return 0;

    case GrantPermissionMacosGrantUnsupported(:final action):
      final verb = action == GrantPermissionAction.grant ? 'grant' : 'revoke';
      stderr.writeln(
        'WARNING: Cannot $verb permissions on macOS via CLI — Apple requires user approval. '
        'Use --reset to clear the decision and trigger a re-prompt on next access.',
      );
      return 1;

    case GrantPermissionPhysicalIosUnsupported():
      stderr.writeln(
        'ERROR: grant-permission is not supported on physical iOS devices. '
        'Use an iOS simulator (xcrun simctl privacy), or manually grant permissions in Settings.',
      );
      return 1;

    case GrantPermissionPlatformUnsupported(:final platform):
      stderr.writeln('ERROR: grant-permission is not supported on platform: $platform');
      return 1;

    case GrantPermissionUnknownToken(:final token, :final platform, :final supportedTokens):
      stderr.writeln("ERROR: Unsupported permission '$token' on $platform. Supported: ${supportedTokens.join(', ')}");
      return 1;

    case GrantPermissionNoAppId():
      stderr.writeln(
        'ERROR: No app ID found. Run fdb launch first or pass --bundle <id>',
      );
      return 1;

    case GrantPermissionNoSession():
      stderr.writeln('ERROR: No active fdb session. Run `fdb launch` first.');
      return 1;

    case GrantPermissionSimctlFailed(:final details):
      stderr.writeln('ERROR: xcrun simctl exited with code 1: $details');
      return 1;

    case GrantPermissionSimctlExecutionFailed(:final error):
      stderr.writeln('ERROR: Could not run xcrun simctl: $error');
      return 1;

    case GrantPermissionAdbFailed(:final details):
      stderr.writeln('ERROR: adb exited with code 1: $details');
      return 1;

    case GrantPermissionAdbExecutionFailed(:final error):
      stderr.writeln('ERROR: Could not run adb: $error');
      return 1;

    case GrantPermissionTccutilFailed(:final details):
      stderr.writeln('ERROR: tccutil failed: $details');
      return 1;

    case GrantPermissionError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

void _printSuccess(GrantPermissionAction action, String permission) {
  switch (action) {
    case GrantPermissionAction.grant:
      stdout.writeln('PERMISSION_GRANTED=$permission');
    case GrantPermissionAction.revoke:
      stdout.writeln('PERMISSION_REVOKED=$permission');
    case GrantPermissionAction.reset:
      if (permission == 'all') {
        stdout.writeln('PERMISSION_RESET_ALL=true');
      } else {
        stdout.writeln('PERMISSION_RESET=$permission');
      }
  }
}
