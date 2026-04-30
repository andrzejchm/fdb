import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/devices/devices_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/devices/devices_models.dart';

/// Runs `flutter devices --machine` and returns a structured result.
///
/// When `input.connectedOnly` is `true`, iOS physical devices that are not
/// reachable on the local network are excluded. Reachability is determined via
/// `xcrun devicectl` (macOS + Xcode only): a device whose `tunnelState` is
/// `unavailable` is considered unreachable. Devices on other platforms
/// (Android, macOS, simulators) are always treated as reachable because
/// `flutter devices` only surfaces them when they are available.
///
/// Never throws; never writes to stdio. All error conditions are represented
/// as distinct [DevicesResult] subtypes.
Future<DevicesResult> listDevices(DevicesInput input) async {
  final ProcessResult result;
  result = await Process.run('flutter', ['devices', '--machine']);

  if (result.exitCode != 0) {
    return DevicesFlutterFailed(result.stderr as String);
  }

  final json = extractDevicesJson(result.stdout as String);
  if (json == null) return const DevicesNotFound();

  final List<dynamic> raw;
  try {
    raw = jsonDecode(json) as List<dynamic>;
  } catch (e) {
    return DevicesParseFailed(e.toString());
  }

  if (raw.isEmpty) return const DevicesNotFound();

  final devices = <DeviceInfo>[];
  final skipped = <Map<String, dynamic>>[];

  // Fetch reachability info once for all iOS physical devices.
  final reachableIosUdids = await _fetchReachableIosUdids();

  for (final entry in raw) {
    final d = entry as Map<String, dynamic>;
    final id = d['id'] as String?;
    final name = d['name'] as String?;
    final platform = d['targetPlatform'] as String?;

    if (id == null || name == null || platform == null) {
      skipped.add(d);
      continue;
    }

    final emulator = d['emulator'] as bool? ?? false;
    final connected = _isConnected(
      id: id,
      platform: platform,
      emulator: emulator,
      reachableIosUdids: reachableIosUdids,
    );

    if (input.connectedOnly && !connected) continue;

    devices.add((id: id, name: name, platform: platform, emulator: emulator, connected: connected));
  }

  return DevicesListed(devices: devices, skippedRaw: skipped);
}

/// Returns the set of iOS physical device UDIDs that are currently reachable,
/// according to `xcrun devicectl`.
///
/// A device is considered reachable when its `connectionProperties.tunnelState`
/// is anything other than `"unavailable"`. This matches the `available` state
/// shown in `xcrun devicectl list devices` human-readable output.
///
/// Returns an empty set when `xcrun` is unavailable (non-macOS, no Xcode) or
/// when `devicectl` fails for any reason — callers treat all iOS devices as
/// connected in that case.
Future<Set<String>> _fetchReachableIosUdids() async {
  try {
    final tmpFile = await _createTempFile();
    try {
      final result = await Process.run('xcrun', [
        'devicectl',
        'list',
        'devices',
        '--json-output',
        tmpFile.path,
      ]);

      if (result.exitCode != 0) return {};

      final content = await tmpFile.readAsString();
      if (content.isEmpty) return {};

      final Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }

      final resultMap = parsed['result'] as Map<String, dynamic>?;
      if (resultMap == null) return {};

      final devicesList = resultMap['devices'] as List<dynamic>?;
      if (devicesList == null) return {};

      final reachable = <String>{};
      for (final entry in devicesList) {
        final deviceMap = entry as Map<String, dynamic>;
        final conn = deviceMap['connectionProperties'] as Map<String, dynamic>?;
        final hw = deviceMap['hardwareProperties'] as Map<String, dynamic>?;
        if (conn == null || hw == null) continue;

        final tunnelState = conn['tunnelState'] as String?;
        final udid = hw['udid'] as String?;
        if (udid == null) continue;

        // Any tunnelState other than 'unavailable' means the device can be
        // reached (e.g. 'disconnected' when visible on the network but not
        // yet tunnelled, 'connected' when fully active).
        if (tunnelState != 'unavailable') {
          reachable.add(udid);
        }
      }
      return reachable;
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  } catch (_) {
    // xcrun not available or any other unexpected error — degrade gracefully.
    return {};
  }
}

/// Creates a temporary file for `devicectl --json-output`.
///
/// Uses a name that is safe on both macOS and Linux.
Future<File> _createTempFile() async {
  final dir = Directory.systemTemp;
  final name = 'fdb_devicectl_${DateTime.now().microsecondsSinceEpoch}.json';
  return File('${dir.path}/$name');
}

/// Returns whether [id] is considered connected given the current
/// [reachableIosUdids] set.
///
/// - Simulators (`emulator == true`) are always connected — Flutter only
///   lists booted simulators.
/// - Non-iOS platforms (Android, macOS, web) are always connected — Flutter
///   only surfaces them when available.
/// - iOS physical devices: connected iff [id] appears in [reachableIosUdids].
///   When [reachableIosUdids] is empty (xcrun unavailable), falls back to
///   `true` so existing behaviour is preserved.
bool _isConnected({
  required String id,
  required String platform,
  required bool emulator,
  required Set<String> reachableIosUdids,
}) {
  if (emulator) return true;
  if (platform != 'ios') return true;
  if (reachableIosUdids.isEmpty) return true;
  return reachableIosUdids.contains(id);
}
