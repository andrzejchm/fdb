import 'dart:io';

import 'package:fdb/core/commands/deeplink/deeplink_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/deeplink/deeplink_models.dart';

/// Opens a deep link URL on the connected device (Android or iOS simulator).
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<DeeplinkResult> openDeeplink(DeeplinkInput input) async {
  final deviceId = readDevice();
  if (deviceId == null) return const DeeplinkNoSession();

  final isSimulator = await _isIosSimulatorId(deviceId);
  if (isSimulator) {
    return _openIos(input.url);
  }

  final isAndroid = await _isAndroidDeviceId(deviceId);
  if (isAndroid) {
    return _openAndroid(input.url);
  }

  return const DeeplinkUnsupportedPlatform();
}

Future<DeeplinkResult> _openAndroid(String url) async {
  final result = await Process.run('adb', [
    'shell',
    'am',
    'start',
    '-W',
    '-a',
    'android.intent.action.VIEW',
    '-c',
    'android.intent.category.BROWSABLE',
    '-d',
    url,
  ]);

  final stdoutStr = result.stdout as String;
  final stderrStr = result.stderr as String;

  if (result.exitCode != 0 || stdoutStr.contains('Error:')) {
    final details = stderrStr.isNotEmpty ? stderrStr.trim() : stdoutStr.trim();
    return DeeplinkFailed(details);
  }

  return DeeplinkOpened(url: url);
}

Future<DeeplinkResult> _openIos(String url) async {
  String? warning;
  if (url.startsWith('http://') || url.startsWith('https://')) {
    warning = 'WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator';
  }

  final result = await Process.run('xcrun', ['simctl', 'openurl', 'booted', url]);

  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    return DeeplinkFailed(details);
  }

  return DeeplinkOpened(url: url, warning: warning);
}

/// Returns true if [deviceId] is a booted iOS simulator UUID.
Future<bool> _isIosSimulatorId(String deviceId) async {
  try {
    final result = await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted']);
    return (result.stdout as String).contains(deviceId);
  } catch (_) {
    return false;
  }
}

/// Returns true if [deviceId] is an Android device connected via adb.
Future<bool> _isAndroidDeviceId(String deviceId) async {
  try {
    final result = await Process.run('adb', ['devices']);
    final output = result.stdout as String;
    return output.split('\n').any(
          (l) => l.startsWith(deviceId) && l.contains('\tdevice'),
        );
  } catch (_) {
    return false;
  }
}
