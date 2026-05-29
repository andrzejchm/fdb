import 'dart:async';
import 'dart:io';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void _noop(String _) {}

/// Attempts to discover the Dart VM service URL for a Flutter app that was
/// launched outside of fdb by scanning the relevant device log.
///
/// Returns the HTTP-normalised VM service URL on success, or null when
/// discovery is not supported on this platform or timed out.
///
/// On Android the function also runs `adb forward` so that the device-local
/// port becomes accessible on the host's localhost.
///
/// Platform support:
/// - **Android** (physical + emulator): `adb logcat -d -s flutter`
/// - **iOS Simulator**: `xcrun simctl spawn <device> log show --last 5m`
/// - **iOS physical**: `idevicesyslog` live stream with [timeout]
/// - **macOS / Linux / Windows / Web**: returns null — use `--debug-url`
///
/// Never throws.
Future<String?> discoverVmServiceUrl({
  required String device,
  required ({String platform, bool emulator}) platformInfo,
  Duration timeout = const Duration(seconds: 5),
  void Function(String) onProgress = _noop,
}) async {
  try {
    final platform = platformInfo.platform.toLowerCase();

    if (platform.startsWith('android')) {
      return await _discoverAndroid(device: device, timeout: timeout, onProgress: onProgress);
    } else if (platform == 'ios' || platform.startsWith('ios-')) {
      if (platformInfo.emulator) {
        return await _discoverIosSimulator(device: device, timeout: timeout, onProgress: onProgress);
      } else {
        return await _discoverIosPhysical(timeout: timeout, onProgress: onProgress);
      }
    }
    // macOS, Linux, Windows, Web: auto-discovery not supported.
    return null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Platform implementations
// ---------------------------------------------------------------------------

Future<String?> _discoverAndroid({
  required String device,
  required Duration timeout,
  required void Function(String) onProgress,
}) async {
  if (!_isToolOnPath('adb')) return null;
  onProgress('attach: scanning Android logcat for VM service URI');
  try {
    // Dump the current logcat buffer for the flutter tag only.
    final result = await Process.run(
      'adb',
      ['-s', device, 'logcat', '-d', '-s', 'flutter'],
    ).timeout(timeout, onTimeout: () => ProcessResult(0, 1, '', ''));

    if (result.exitCode != 0) return null;

    final uri = _extractVmUri(result.stdout as String);
    if (uri == null) return null;

    // The URI is device-local (127.0.0.1:PORT). Forward the port so it is
    // reachable from the host machine.
    final port = Uri.tryParse(uri)?.port;
    if (port != null && port > 0) {
      await Process.run('adb', ['-s', device, 'forward', 'tcp:$port', 'tcp:$port'])
          .timeout(const Duration(seconds: 5), onTimeout: () => ProcessResult(0, 1, '', ''));
      onProgress('attach: forwarded Android VM service port $port via adb');
    }

    return _normalizeUri(uri);
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

Future<String?> _discoverIosSimulator({
  required String device,
  required Duration timeout,
  required void Function(String) onProgress,
}) async {
  if (!_isToolOnPath('xcrun')) return null;
  onProgress('attach: scanning iOS Simulator log for VM service URI');
  try {
    // Try the last 5 minutes of the unified log with a predicate filter.
    final predicate = 'eventMessage CONTAINS "[FDB_VM_URI]"'
        ' OR eventMessage CONTAINS "VM Service"'
        ' OR eventMessage CONTAINS "Observatory"';

    final result = await Process.run(
      'xcrun',
      ['simctl', 'spawn', device, 'log', 'show', '--last', '5m', '--predicate', predicate],
    ).timeout(timeout, onTimeout: () => ProcessResult(0, 1, '', ''));

    final output = result.exitCode == 0 ? result.stdout as String : '';
    final uri = _extractVmUri(output);
    if (uri != null) return _normalizeUri(uri);

    // Fallback: scan the last 2 minutes without a predicate.
    final fallback = await Process.run(
      'xcrun',
      ['simctl', 'spawn', device, 'log', 'show', '--last', '2m'],
    ).timeout(timeout, onTimeout: () => ProcessResult(0, 1, '', ''));

    return _normalizeUri(_extractVmUri(fallback.stdout as String) ?? '');
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

/// Discovers the VM service URI from a physical iOS device by requesting a
/// short log archive from the device and scanning it — mirroring the
/// [_discoverIosSimulator] "look-back" approach used on iOS simulators.
///
/// `idevicesyslog archive PATH --age-limit <seconds>` collects recent device
/// logs into a tar archive. After extraction and renaming to `.logarchive`,
/// the standard `log show --archive` command searches the contents.
///
/// This works for apps launched via Xcode or another tooling that properly
/// handles the iOS ptrace requirement and enables the Dart VM service.
Future<String?> _discoverIosPhysical({
  required Duration timeout,
  required void Function(String) onProgress,
}) async {
  if (!_isToolOnPath('idevicesyslog')) return null;
  onProgress('attach: scanning physical iOS device log for VM service URI');

  final tmpDir = Directory.systemTemp.createTempSync('fdb_ios_log_');
  final tarPath = '${tmpDir.path}/device.tar';
  // Extract into a dedicated subdirectory so the flat tar contents form a
  // complete logarchive directory that `log show --archive` can accept.
  final extractDir = Directory('${tmpDir.path}/extracted')..createSync();
  final archivePath = '${tmpDir.path}/device.logarchive';

  try {
    // Collect the last 5 minutes of device logs into a tar archive.
    final collectResult = await Process.run(
      'idevicesyslog',
      ['archive', tarPath, '--age-limit', '300'],
    ).timeout(timeout, onTimeout: () => ProcessResult(0, 1, '', ''));

    if (collectResult.exitCode != 0 || !File(tarPath).existsSync()) return null;

    // Extract the tar into extractDir, then rename it to .logarchive.
    await Process.run('tar', ['xf', tarPath, '-C', extractDir.path])
        .timeout(const Duration(seconds: 30), onTimeout: () => ProcessResult(0, 1, '', ''));

    extractDir.renameSync(archivePath);

    // Query the archive for VM URI patterns.
    final predicate = 'eventMessage CONTAINS "[FDB_VM_URI]"'
        ' OR eventMessage CONTAINS "VM Service"'
        ' OR eventMessage CONTAINS "Observatory"';
    final showResult = await Process.run(
      '/usr/bin/log',
      ['show', '--archive', archivePath, '--predicate', predicate],
    ).timeout(const Duration(seconds: 30), onTimeout: () => ProcessResult(0, 1, '', ''));

    final uri = _extractVmUri(showResult.stdout as String);
    return uri != null ? _normalizeUri(uri) : null;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// URI extraction helpers (also exported for unit testing)
// ---------------------------------------------------------------------------

/// Patterns searched in order. The first capturing group must hold the raw URI.
final _vmUriPatterns = [
  // fdb_helper structured marker (most reliable, stable format).
  RegExp(r'\[FDB_VM_URI\]\s+(https?://\S+)'),
  // Flutter engine line format as of Flutter 3.x.
  RegExp(r'The Dart VM service is listening on (wss?://\S+)'),
  // Flutter tool daemon format (seen on Android logcat).
  RegExp(r'Dart VM Service .* is available at:\s*(https?://\S+)'),
  // Legacy Observatory format.
  RegExp(r'Observatory listening on (https?://\S+)'),
];

/// Scans [text] for a Dart VM service URI and returns the normalised HTTP URL,
/// or null if none is found.
///
/// Searches in reverse order (most-recent line wins) and prefers the
/// `[FDB_VM_URI]` marker emitted by `fdb_helper` over Flutter engine lines.
///
/// Exposed as a top-level function so it can be unit-tested independently of
/// the process-spawning discovery functions.
String? extractVmUriFromLog(String text) {
  final lines = text.split('\n');

  // First pass: prefer the stable [FDB_VM_URI] marker.
  for (final line in lines.reversed) {
    final m = _vmUriPatterns[0].firstMatch(line);
    if (m != null) return _normalizeUri(m.group(1)!.trimRight());
  }

  // Second pass: fall back to Flutter engine output patterns.
  for (final line in lines.reversed) {
    for (final pattern in _vmUriPatterns.skip(1)) {
      final m = pattern.firstMatch(line);
      if (m != null) return _normalizeUri(m.group(1)!.trimRight());
    }
  }

  return null;
}

String? _extractVmUri(String text) => extractVmUriFromLog(text);

/// Normalises a VM service URI to HTTP form expected by `flutter attach --debug-url`.
///
/// Converts `ws://` → `http://` and strips trailing `/ws` path segment.
String? _normalizeUri(String uri) {
  var normalized = uri.trim();
  if (normalized.isEmpty) return null;

  if (normalized.startsWith('ws://')) {
    normalized = 'http://${normalized.substring(5)}';
  } else if (normalized.startsWith('wss://')) {
    normalized = 'https://${normalized.substring(6)}';
  }

  if (normalized.endsWith('/ws/')) return normalized.substring(0, normalized.length - 3);
  if (normalized.endsWith('/ws')) return normalized.substring(0, normalized.length - 2);
  return normalized;
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

bool _isToolOnPath(String tool) {
  try {
    final result = Process.runSync('which', [tool]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
