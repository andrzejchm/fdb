import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/screenshot/screenshot_models.dart';
import 'package:fdb/core/process_utils.dart';
import 'package:fdb/core/vm_service.dart';
import 'package:image/image.dart' as img;

export 'package:fdb/core/commands/screenshot/screenshot_models.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Captures a screenshot of the running Flutter app.
///
/// Never throws (except [AppDiedException] which the dispatcher handles).
/// All other error conditions are represented as [ScreenshotFailed].
Future<ScreenshotResult> captureScreenshot(ScreenshotInput input) async {
  final warnings = <String>[];
  final output = input.output;

  // Read session state.
  final platformInfo = readPlatformInfo();
  final deviceId = readDevice();

  // Dispatch to the correct capture backend.
  final String? captureError;
  if (platformInfo != null) {
    captureError = await _dispatchScreenshot(
      platform: platformInfo.platform,
      emulator: platformInfo.emulator,
      deviceId: deviceId,
      output: output,
      warnings: warnings,
    );
  } else {
    captureError = await _legacyCapture(output, warnings);
  }

  if (captureError != null) {
    return ScreenshotFailed(message: captureError, warnings: warnings);
  }

  final file = File(output);
  if (!file.existsSync()) {
    return ScreenshotFailed(
      message: 'Screenshot file not created',
      warnings: warnings,
    );
  }

  if (!input.fullResolution) {
    final resizeError = await _resizeToMaxDimension(output);
    if (resizeError != null) {
      return ScreenshotFailed(message: resizeError, warnings: warnings);
    }
  }

  final sizeBytes = file.lengthSync();
  return ScreenshotSaved(
    path: output,
    sizeBytes: sizeBytes,
    warnings: warnings,
  );
}

// ---------------------------------------------------------------------------
// Platform dispatch
// ---------------------------------------------------------------------------

/// Returns null on success, an error message (without "ERROR: ") on failure.
Future<String?> _dispatchScreenshot({
  required String platform,
  required bool emulator,
  required String? deviceId,
  required String output,
  required List<String> warnings,
}) async {
  if (platform.startsWith('android')) {
    return _captureAndroid(deviceId, output);
  }

  if (platform.startsWith('ios') && emulator) {
    return _captureIosSimulator(deviceId, output);
  }

  if (platform.startsWith('ios') && !emulator) {
    warnings.add(
      'WARNING: No native screenshot tool for physical iOS.\n'
      '  Falling back to fdb_helper (Flutter surface only, no status bar).\n'
      '  Ensure your app includes fdb_helper and calls '
      'FdbBinding.ensureInitialized().',
    );
    return _captureViaFdbHelper(output);
  }

  if (platform.startsWith('darwin')) {
    return _captureMacOs(output, warnings);
  }

  if (platform.startsWith('linux')) {
    return _captureLinux(output, warnings);
  }

  if (platform.startsWith('windows')) {
    warnings.add(
      'WARNING: No native screenshot CLI for Windows.\n'
      '  Falling back to fdb_helper (Flutter surface only, no window chrome).\n'
      '  Ensure your app includes fdb_helper and calls '
      'FdbBinding.ensureInitialized().',
    );
    return _captureViaFdbHelper(output);
  }

  if (platform.startsWith('web')) {
    return _captureWeb(output);
  }

  // Unknown platform — try fdb_helper as last resort.
  warnings.add(
    'WARNING: Unsupported platform "$platform".\n'
    '  Attempting fdb_helper fallback.',
  );
  return _captureViaFdbHelper(output);
}

// ---------------------------------------------------------------------------
// Legacy capture (no platform.txt — sessions before platform tracking)
// ---------------------------------------------------------------------------

/// Heuristic capture used when no platform file exists:
/// checks adb for Android, otherwise assumes iOS simulator.
Future<String?> _legacyCapture(String output, List<String> warnings) async {
  if (await _isAndroidConnected()) {
    return _captureAndroid(null, output);
  }
  return _captureIosSimulator(null, output);
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

Future<String?> _captureAndroid(String? deviceId, String output) async {
  try {
    final args = deviceId != null ? ['-s', deviceId] : <String>[];
    final result = await Process.run(
      'adb',
      [...args, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      return 'adb screencap failed: ${result.stderr}';
    }
    File(output).writeAsBytesSync(result.stdout as List<int>);
    return null;
  } catch (e) {
    return 'Failed to run adb: $e';
  }
}

// ---------------------------------------------------------------------------
// iOS Simulator
// ---------------------------------------------------------------------------

Future<String?> _captureIosSimulator(String? deviceId, String output) async {
  try {
    final target = deviceId ?? 'booted';
    final result = await Process.run('xcrun', [
      'simctl',
      'io',
      target,
      'screenshot',
      output,
    ]);
    if (result.exitCode != 0) {
      return 'xcrun simctl screenshot failed: ${result.stderr}';
    }
    return null;
  } catch (e) {
    return 'Failed to run xcrun: $e';
  }
}

// ---------------------------------------------------------------------------
// macOS desktop
// ---------------------------------------------------------------------------

/// Captures the macOS Flutter app window using `screencapture -l <windowId>`.
///
/// Looks up the window by walking the process tree rooted at the stored PID.
/// Falls back to fdb_helper if the window cannot be found or `screencapture`
/// lacks Screen Recording permission.
Future<String?> _captureMacOs(String output, List<String> warnings) async {
  final pid = readPid();
  if (pid == null) {
    return 'No PID in session — cannot locate macOS window. Re-launch the app.';
  }

  try {
    final windowId = await _macWindowId(pid);
    if (windowId == null) {
      warnings.add(
        'WARNING: Could not find macOS window for PID $pid.\n'
        '  Falling back to fdb_helper (Flutter surface only, no title bar).',
      );
      return _captureViaFdbHelper(output);
    }

    final result = await Process.run('screencapture', [
      '-l',
      windowId.toString(),
      '-o', // omit window shadow
      output,
    ]);
    if (result.exitCode != 0) {
      warnings.add(
        'WARNING: screencapture failed — Screen Recording permission may be\n'
        '  required: System Settings > Privacy & Security > Screen Recording.\n'
        '  Falling back to fdb_helper (Flutter surface only, no title bar).',
      );
      return _captureViaFdbHelper(output);
    }
    return null;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    return 'macOS screenshot failed: $e';
  }
}

/// Returns the CGWindowID for the on-screen window owned by [pid] or any of
/// its child processes.
Future<int?> _macWindowId(int pid) async {
  final pids = <int>[pid];
  try {
    final pg = await Process.run('pgrep', ['-P', '$pid']);
    if (pg.exitCode == 0) {
      for (final line in (pg.stdout as String).trim().split('\n')) {
        final child = int.tryParse(line.trim());
        if (child != null) pids.add(child);
      }
    }
  } catch (_) {}

  final pidsArg = pids.join(',');
  final result = await Process.run('swift', [
    '-e',
    '''
import Cocoa
let pidStrs = "$pidsArg".split(separator: ",")
let pids = pidStrs.compactMap { Int32(\$0) }
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [NSDictionary] else { exit(0) }
for w in list {
  guard let ownerPid = w[kCGWindowOwnerPID] as? Int32, pids.contains(ownerPid) else { continue }
  if let num = w[kCGWindowNumber] as? Int { print(num); break }
}
''',
  ]);
  if (result.exitCode != 0) return null;
  return int.tryParse((result.stdout as String).trim());
}

// ---------------------------------------------------------------------------
// Linux
// ---------------------------------------------------------------------------

/// Captures the Linux Flutter app window.
///
/// On X11: uses `xdotool` + ImageMagick `import` to capture the window.
/// On Wayland (or if xdotool is unavailable): falls back to fdb_helper.
Future<String?> _captureLinux(String output, List<String> warnings) async {
  final pid = readPid();
  if (pid != null) {
    final ok = await _captureLinuxNative(pid, output);
    if (ok) return null;
    // native attempt failed — fall through to fdb_helper.
  }

  final reason = pid == null
      ? 'No PID in session'
      : 'xdotool/import not available or Wayland display (native capture not '
          'supported on Wayland).\n'
          '  For X11: install xdotool and ImageMagick '
          '(e.g. sudo apt install xdotool imagemagick)';
  warnings.add(
    'WARNING: $reason.\n'
    '  Falling back to fdb_helper (Flutter surface only, no window chrome).\n'
    '  Ensure your app includes fdb_helper and calls '
    'FdbBinding.ensureInitialized().',
  );
  return _captureViaFdbHelper(output);
}

/// Tries `xdotool search --pid` + `import -window` to capture the window.
/// Returns true on success, false to signal the caller should try the fallback.
Future<bool> _captureLinuxNative(int pid, String output) async {
  try {
    final xdo = await Process.run('xdotool', [
      'search',
      '--onlyvisible',
      '--pid',
      '$pid',
    ]);
    if (xdo.exitCode != 0) return false;

    final windowId = (xdo.stdout as String).trim().split('\n').first.trim();
    if (windowId.isEmpty) return false;

    final imp = await Process.run('import', ['-window', windowId, output]);
    return imp.exitCode == 0;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Web (Chrome DevTools Protocol)
// ---------------------------------------------------------------------------

/// Captures a Flutter Web app screenshot via CDP `Page.captureScreenshot`.
Future<String?> _captureWeb(String output) async {
  final portStr = Platform.environment['CHROME_CDP_PORT'] ?? '9222';
  final port = int.tryParse(portStr) ?? 9222;

  final String wsUrl;
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('http://localhost:$port/json'));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      final pages = jsonDecode(body) as List<dynamic>;
      if (pages.isEmpty) {
        return 'No Chrome pages found on CDP port $port.\n'
            '  Launch Chrome with --remote-debugging-port=$port.';
      }
      final page = pages.firstWhere(
        (p) => (p as Map<String, dynamic>)['type'] == 'page',
        orElse: () => pages.first,
      ) as Map<String, dynamic>;
      final url = page['webSocketDebuggerUrl'] as String?;
      if (url == null) {
        return 'No WebSocket debugger URL in CDP page list.';
      }
      wsUrl = url;
    } finally {
      client.close();
    }
  } catch (e) {
    return 'Could not connect to Chrome CDP on port $port: $e';
  }

  WebSocket? ws;
  StreamSubscription<dynamic>? subscription;
  try {
    ws = await WebSocket.connect(wsUrl);
    final completer = Completer<Map<String, dynamic>>();

    subscription = ws.listen(
      (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['id'] == 1 && !completer.isCompleted) completer.complete(msg);
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('WebSocket closed before CDP response'),
          );
        }
      },
    );

    ws.add(jsonEncode({'id': 1, 'method': 'Page.captureScreenshot', 'params': {}}));

    final response = await completer.future.timeout(const Duration(seconds: 10));
    final data = (response['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data == null) {
      return 'CDP screenshot returned no image data.';
    }
    File(output).writeAsBytesSync(base64Decode(data));
    return null;
  } on TimeoutException {
    return 'CDP screenshot timed out.';
  } catch (e) {
    return 'CDP screenshot failed: $e';
  } finally {
    await subscription?.cancel();
    await ws?.close();
  }
}

// ---------------------------------------------------------------------------
// fdb_helper VM extension fallback
// ---------------------------------------------------------------------------

/// Captures a screenshot via the `ext.fdb.screenshot` VM service extension.
///
/// Used when no native OS screenshot tool is available (physical iOS, Windows,
/// Linux Wayland).
Future<String?> _captureViaFdbHelper(String output) async {
  final vmUri = readVmUri();
  if (vmUri == null) {
    return 'No VM service URI in session and no native screenshot tool '
        'available.\n  Re-launch the app.';
  }

  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) {
      return 'fdb_helper not found in the running app.\n'
          '  Add fdb_helper to pubspec.yaml and call '
          'FdbBinding.ensureInitialized() in main().';
    }

    final response = await vmServiceCall(
      'ext.fdb.screenshot',
      params: {'isolateId': isolateId},
    );

    final result = unwrapRawExtensionResult(response);
    if (result is Map && result.containsKey('error')) {
      return 'fdb_helper screenshot: ${result['error']}';
    }

    final resultMap = result as Map<String, dynamic>?;
    final base64Data = resultMap?['screenshot'] as String?;
    if (base64Data == null) {
      return 'No screenshot data in fdb_helper response.';
    }

    File(output).writeAsBytesSync(base64Decode(base64Data));
    return null;
  } on AppDiedException {
    rethrow;
  } catch (e) {
    return 'fdb_helper screenshot failed: $e';
  }
}

// ---------------------------------------------------------------------------
// Downscaling
// ---------------------------------------------------------------------------

const _maxScreenshotDimension = 1200;

/// Downscales [path] in-place so its longest side does not exceed
/// [_maxScreenshotDimension] pixels, preserving aspect ratio, then
/// re-encodes the PNG with level-6 compression.
///
/// Returns null on success, an error message on failure.
Future<String?> _resizeToMaxDimension(String path) async {
  try {
    final file = File(path);
    final bytes = await file.readAsBytes();

    final src = img.decodePng(bytes);
    if (src == null) {
      return 'Could not decode PNG for resizing';
    }

    final img.Image resized;
    final longest = src.width > src.height ? src.width : src.height;
    if (longest > _maxScreenshotDimension) {
      final scale = _maxScreenshotDimension / longest;
      resized = img.copyResize(
        src,
        width: (src.width * scale).round(),
        height: (src.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    } else {
      resized = src;
    }

    final encoded = img.encodePng(resized, level: 6);
    await file.writeAsBytes(encoded);
    return null;
  } catch (e) {
    return 'Could not resize image: $e';
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<bool> _isAndroidConnected() async {
  try {
    final result = await Process.run('adb', ['devices']);
    final output = result.stdout as String;
    return output.split('\n').any((l) => l.contains('\tdevice'));
  } catch (_) {
    return false;
  }
}
