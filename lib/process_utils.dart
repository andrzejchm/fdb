import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';

/// Reads and parses session.json for [deviceId].
/// Returns null if the file does not exist or cannot be parsed.
Map<String, dynamic>? readSession(String deviceId) {
  final file = File(sessionFile(deviceId));
  if (!file.existsSync()) return null;
  try {
    final content = file.readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// Writes [data] to session.json for [deviceId] atomically
/// (write to .tmp then rename). Creates the session directory if needed.
void writeSession(String deviceId, Map<String, dynamic> data) {
  ensureFdbHome();
  final dir = sessionDir(deviceId);
  Directory(dir).createSync(recursive: true);
  final path = sessionFile(deviceId);
  final tmp = '$path.tmp';
  File(tmp).writeAsStringSync(jsonEncode(data));
  File(tmp).renameSync(path);
}

/// Reads the existing session for [deviceId], merges [updates], and writes back.
/// Creates the session if it does not exist.
void updateSession(String deviceId, Map<String, dynamic> updates) {
  final existing = readSession(deviceId) ?? {};
  writeSession(deviceId, {...existing, ...updates});
}

/// Reads the session for [deviceId] and returns the pid field, or null.
int? readPidFromSession(String deviceId) {
  final session = readSession(deviceId);
  if (session == null) return null;
  final pid = session['pid'];
  if (pid is int) return pid;
  if (pid is String) return int.tryParse(pid);
  return null;
}

/// Reads the session for [deviceId] and returns the vmServiceUri field, or null.
String? readVmUriFromSession(String deviceId) {
  final session = readSession(deviceId);
  return session?['vmServiceUri'] as String?;
}

/// Reads the session for [deviceId] and returns the deviceId field, or null.
String? readDeviceFromSession(String deviceId) {
  final session = readSession(deviceId);
  return session?['deviceId'] as String?;
}

/// Returns true if the process with [pid] is alive (via kill -0).
bool isProcessAlive(int pid) {
  try {
    final result = Process.runSync('kill', ['-0', pid.toString()]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Deletes the entire session directory for [deviceId].
void cleanupSession(String deviceId) {
  final dir = Directory(sessionDir(deviceId));
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

/// Creates ~/.fdb/ and ~/.fdb/sessions/ if they do not exist.
void ensureFdbHome() {
  Directory('$fdbHome/sessions').createSync(recursive: true);
}

/// Scans all session directories, reads session.json, and returns only those
/// with a live PID (verified via kill -0). Each entry includes the full session data.
List<Map<String, dynamic>> findActiveSessions() {
  final sessionsDir = Directory('$fdbHome/sessions');
  if (!sessionsDir.existsSync()) return [];

  final active = <Map<String, dynamic>>[];
  for (final entry in sessionsDir.listSync()) {
    if (entry is! Directory) continue;
    final sessionJsonFile = File('${entry.path}/session.json');
    if (!sessionJsonFile.existsSync()) continue;
    try {
      final data = jsonDecode(sessionJsonFile.readAsStringSync())
          as Map<String, dynamic>;
      final pidRaw = data['pid'];
      final int? pid;
      if (pidRaw is int) {
        pid = pidRaw;
      } else if (pidRaw is String) {
        pid = int.tryParse(pidRaw);
      } else {
        pid = null;
      }
      if (pid == null) continue;
      if (isProcessAlive(pid)) {
        active.add(data);
      }
    } catch (_) {
      // Skip unreadable or malformed session files
    }
  }
  return active;
}

/// Resolves a session by [deviceId].
///
/// If [deviceId] is provided, reads that session directly.
/// If null, auto-selects from active sessions:
/// - exactly one active session → returns it
/// - zero active sessions → writes error to stderr, returns null
/// - multiple active sessions → writes error listing them to stderr, returns null
///
/// The returned map always includes the deviceId under the 'deviceId' key.
Map<String, dynamic>? resolveSession(String? deviceId) {
  if (deviceId != null) {
    final session = readSession(deviceId);
    if (session == null) {
      stderr.writeln('ERROR: No session found for device: $deviceId');
      return null;
    }
    return {...session, 'deviceId': deviceId};
  }

  final active = findActiveSessions();
  if (active.isEmpty) {
    stderr.writeln('ERROR: No active sessions found. Is the app running?');
    return null;
  }
  if (active.length > 1) {
    final ids =
        active.map((s) => s['deviceId'] as String? ?? '<unknown>').join(', ');
    stderr.writeln(
      'ERROR: Multiple active sessions found: $ids. '
      'Specify a device with --device.',
    );
    return null;
  }
  return active.first;
}

// ---------------------------------------------------------------------------
// Shell escaping
// ---------------------------------------------------------------------------

/// Shell-escapes [value] for safe embedding in a bash command string.
///
/// Uses a permissive safe-character set that includes `:` and `@` so that
/// device IDs and VM service URIs are not unnecessarily quoted.
String shellEscape(String value) {
  if (RegExp(r'^[a-zA-Z0-9._/=:@-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}

// ---------------------------------------------------------------------------
// Device cache
// ---------------------------------------------------------------------------

/// Writes [devices] (raw list from `flutter devices --machine`) to the device
/// cache at [deviceCachePath].
///
/// Each entry is normalised to `{id, name, platform, emulator}`.
/// Calls [ensureFdbHome] before writing.
void writeDeviceCache(List<dynamic> devices) {
  ensureFdbHome();
  final entries = devices.map((d) {
    final m = d as Map<String, dynamic>;
    return {
      'id': m['id'] as String,
      'name': m['name'] as String,
      'platform': m['targetPlatform'] as String,
      'emulator': m['emulator'] as bool? ?? false,
    };
  }).toList();

  final payload = jsonEncode({
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'devices': entries,
  });

  final path = deviceCachePath;
  final tmp = '$path.tmp';
  File(tmp).writeAsStringSync(payload);
  File(tmp).renameSync(path);
}

/// Reads the device cache from [deviceCachePath].
/// Returns null if the file does not exist or cannot be parsed.
Map<String, dynamic>? _readDeviceCache() {
  final file = File(deviceCachePath);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// Looks up the platform for [deviceId] from the device cache.
/// Returns null if the device is not found or the cache does not exist.
String? lookupPlatform(String deviceId) {
  final cache = _readDeviceCache();
  if (cache == null) return null;
  final devices = cache['devices'] as List<dynamic>?;
  if (devices == null) return null;
  for (final d in devices) {
    final m = d as Map<String, dynamic>;
    if (m['id'] == deviceId) return m['platform'] as String?;
  }
  return null;
}

/// Looks up whether [deviceId] is an emulator from the device cache.
/// Returns null if the device is not found or the cache does not exist.
bool? lookupEmulator(String deviceId) {
  final cache = _readDeviceCache();
  if (cache == null) return null;
  final devices = cache['devices'] as List<dynamic>?;
  if (devices == null) return null;
  for (final d in devices) {
    final m = d as Map<String, dynamic>;
    if (m['id'] == deviceId) return m['emulator'] as bool?;
  }
  return null;
}

/// Refreshes the device cache by running `flutter devices --machine`.
///
/// Parses the output and writes to [deviceCachePath].
/// Returns true on success, false if the command fails or output cannot be
/// parsed. This is intended for callers (e.g. launch) that need an up-to-date
/// cache when a device is not found in the existing one.
Future<bool> refreshDeviceCache() async {
  try {
    final result = await Process.run('flutter', ['devices', '--machine']);
    if (result.exitCode != 0) return false;

    final json = _extractDevicesJson(result.stdout as String);
    if (json == null) return false;

    final List<dynamic> devices;
    try {
      devices = jsonDecode(json) as List<dynamic>;
    } catch (_) {
      return false;
    }

    writeDeviceCache(devices);
    return true;
  } catch (_) {
    return false;
  }
}

/// Extracts the JSON array from `flutter devices --machine` output.
///
/// Flutter may prepend non-JSON text (download progress, upgrade banners)
/// before the actual JSON array. We scan for the first `[` to find the
/// array start.
// NOTE: duplicated in devices.dart to avoid circular import.
String? _extractDevicesJson(String output) {
  final start = output.indexOf('[');
  if (start == -1) return null;
  final end = output.lastIndexOf(']');
  if (end == -1 || end < start) return null;
  return output.substring(start, end + 1);
}
