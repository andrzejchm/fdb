import 'dart:io';

import 'package:fdb/core/commands/deeplink/deeplink_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/simulator_device.dart';
import 'package:fdb/core/xcrun.dart';

export 'package:fdb/core/commands/deeplink/deeplink_models.dart';

/// Opens a deep link URL on the target device (Android or iOS simulator).
///
/// The target is `--device` ([DeeplinkInput.deviceOverride]) when given, else
/// the session device. An iOS simulator target goes through
/// [pickSimulatorDevice], the same resolution `fdb simulator` uses, and the URL
/// is opened on that UDID, never on simctl's `booted` alias (which picks an
/// arbitrary simulator when several are booted). An Android target is
/// addressed with `adb -s <serial>`.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<DeeplinkResult> openDeeplink(DeeplinkInput input) async {
  final sessionDevice = readDevice();
  final target = input.deviceOverride ?? sessionDevice;
  if (target == null) return const DeeplinkNoSession();

  // A failed listing (no Xcode, Linux/Windows host) just means no simulators.
  final simulators = (await listSimulators()).simulators ?? const <SimulatorDevice>[];
  if (findSimulator(simulators, target) != null) {
    final resolved = pickSimulatorDevice(
      simulators,
      deviceOverride: input.deviceOverride,
      sessionDevice: sessionDevice,
    );
    final udid = resolved.udid;
    if (udid == null) return DeeplinkDeviceUnresolved(resolved.error!);
    return _openIos(udid, input.url);
  }

  if (await _isAndroidDeviceId(target)) {
    return _openAndroid(target, input.url);
  }

  if (input.deviceOverride != null) {
    return DeeplinkDeviceUnresolved(
      'No iOS simulator or Android device with ID $target. List devices with: fdb devices',
    );
  }
  return const DeeplinkUnsupportedPlatform();
}

Future<DeeplinkResult> _openAndroid(String serial, String url) async {
  final ProcessResult result;
  try {
    result = await Process.run(adbExecutable, [
      '-s',
      serial,
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
  } catch (e) {
    return DeeplinkFailed('Failed to run adb: $e');
  }

  final stdoutStr = result.stdout as String;
  final stderrStr = result.stderr as String;

  if (result.exitCode != 0 || stdoutStr.contains('Error:')) {
    final details = stderrStr.isNotEmpty ? stderrStr.trim() : stdoutStr.trim();
    return DeeplinkFailed(details);
  }

  return DeeplinkOpened(url: url);
}

Future<DeeplinkResult> _openIos(String udid, String url) async {
  String? warning;
  if (url.startsWith('http://') || url.startsWith('https://')) {
    warning = 'WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator';
  }

  final ProcessResult result;
  try {
    result = await Process.run(xcrunExecutable, ['simctl', 'openurl', udid, url]);
  } catch (e) {
    return DeeplinkFailed('Failed to run xcrun simctl: $e');
  }

  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    return DeeplinkFailed(details);
  }

  return DeeplinkOpened(url: url, warning: warning);
}

/// Returns true if [deviceId] is an Android device in the `device` state in
/// `adb devices` (exact serial match).
Future<bool> _isAndroidDeviceId(String deviceId) async {
  try {
    final result = await Process.run(adbExecutable, ['devices']);
    final output = result.stdout as String;
    return output.split('\n').any((line) {
      final columns = line.trim().split(RegExp(r'\s+'));
      return columns.length >= 2 && columns[0] == deviceId && columns[1] == 'device';
    });
  } catch (_) {
    return false;
  }
}
