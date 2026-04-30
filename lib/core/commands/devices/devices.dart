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
  final result = await Process.run('flutter', ['devices', '--machine']);

  if (result.exitCode != 0) {
    return DevicesFlutterFailed(result.stderr.toString());
  }

  final json = extractDevicesJson(result.stdout.toString());
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

  // Only invoke xcrun when at least one iOS physical device is present.
  // null  → xcrun unavailable/failed or not needed (fall back: treat all as connected).
  // non-null → xcrun ran OK; set contains UDIDs explicitly listed with
  //            tunnelState == 'unavailable'.
  final hasIosPhysical = raw.any((entry) {
    if (entry is! Map<String, dynamic>) return false;
    final platform = entry['targetPlatform'] as String?;
    final emulator = entry['emulator'] is bool ? entry['emulator'] as bool : false;
    return platform == 'ios' && !emulator;
  });
  final xcrunResult =
      hasIosPhysical ? await _fetchUnavailableIosUdids() : null;

  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final d = entry;
    final id = d['id'] as String?;
    final name = d['name'] as String?;
    final platform = d['targetPlatform'] as String?;

    if (id == null || name == null || platform == null) {
      skipped.add(d);
      continue;
    }

    final emulator = d['emulator'] is bool ? d['emulator'] as bool : false;
    final connected = _isConnected(
      id: id,
      platform: platform,
      emulator: emulator,
      unavailableIosUdids: xcrunResult,
    );

    if (input.connectedOnly && !connected) continue;

    devices.add((id: id, name: name, platform: platform, emulator: emulator, connected: connected));
  }

  return DevicesListed(devices: devices, skippedRaw: skipped);
}

/// Returns the set of iOS physical device UDIDs explicitly listed by
/// `xcrun devicectl` with `tunnelState == 'unavailable'`.
///
/// Returns `null` when `xcrun` is unavailable (non-macOS, no Xcode) or when
/// `devicectl` fails for any reason — callers treat all iOS devices as
/// connected in that case (graceful degradation).
///
/// Returns an empty set when xcrun ran successfully but found no devices with
/// `tunnelState == 'unavailable'`. Devices absent from xcrun output entirely
/// default to connected — xcrun only lists network-tunnel-visible devices, so
/// a USB-connected device may not appear at all even though it is reachable.
Future<Set<String>?> _fetchUnavailableIosUdids() async {
  try {
    final tmpFile = _createTempFile();
    try {
      final result = await Process.run('xcrun', [
        'devicectl',
        'list',
        'devices',
        '--json-output',
        tmpFile.path,
      ]);

      if (result.exitCode != 0) return null;

      final content = await tmpFile.readAsString();
      if (content.isEmpty) return null;

      final Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }

      final resultMap = parsed['result'] as Map<String, dynamic>?;
      if (resultMap == null) return null;

      final devicesList = resultMap['devices'] as List<dynamic>?;
      if (devicesList == null) return null;

      final unavailable = <String>{};
      for (final entry in devicesList) {
        final deviceMap = entry as Map<String, dynamic>;
        final conn = deviceMap['connectionProperties'] as Map<String, dynamic>?;
        final hw = deviceMap['hardwareProperties'] as Map<String, dynamic>?;
        if (conn == null || hw == null) continue;

        final tunnelState = conn['tunnelState'] as String?;
        final udid = hw['udid'] as String?;
        if (udid == null) continue;

        if (tunnelState == 'unavailable') {
          unavailable.add(udid);
        }
      }
      return unavailable;
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  } catch (_) {
    // xcrun not available or any other unexpected error — degrade gracefully.
    return null;
  }
}

/// Creates a temporary file for `devicectl --json-output`.
///
/// Uses a name that is safe on both macOS and Linux.
File _createTempFile() {
  final dir = Directory.systemTemp;
  final name = 'fdb_devicectl_${DateTime.now().microsecondsSinceEpoch}.json';
  return File('${dir.path}/$name');
}

/// Returns whether [id] is considered connected.
///
/// - Simulators (`emulator == true`) are always connected — Flutter only
///   lists booted simulators.
/// - Non-iOS platforms (Android, macOS, web) are always connected — Flutter
///   only surfaces them when available.
/// - iOS physical devices:
///   - [unavailableIosUdids] == `null` → xcrun failed; fall back to `true`.
///   - [unavailableIosUdids] contains [id] → device is explicitly unavailable.
///   - [id] absent from [unavailableIosUdids] → device is connected (USB-
///     connected devices may not appear in xcrun output at all).
bool _isConnected({
  required String id,
  required String platform,
  required bool emulator,
  required Set<String>? unavailableIosUdids,
}) {
  if (emulator) return true;
  if (platform != 'ios') return true;
  if (unavailableIosUdids == null) return true;
  return !unavailableIosUdids.contains(id);
}
