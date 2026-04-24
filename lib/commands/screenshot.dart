import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';
import 'package:fdb/vm_service.dart';

Future<int> runScreenshot(List<String> args) async {
  var output = defaultScreenshotPath;
  var fullResolution = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--output':
        output = args[++i];
      case '--full':
        fullResolution = true;
      default:
        if (arg.startsWith('--output=')) {
          output = arg.substring('--output='.length);
        }
    }
  }

  // Read session state
  final platformInfo = readPlatformInfo();
  final deviceId = readDevice();

  // Dispatch to the correct capture backend based on the stored platform.
  // Falls back to the legacy adb/xcrun heuristic when no platform file exists
  // (e.g. sessions launched before this change).
  final int captureResult;
  if (platformInfo != null) {
    captureResult = await _dispatchScreenshot(
      platform: platformInfo.platform,
      emulator: platformInfo.emulator,
      deviceId: deviceId,
      output: output,
    );
  } else {
    captureResult = await _legacyCapture(output);
  }
  if (captureResult != 0) return captureResult;

  final file = File(output);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: Screenshot file not created');
    return 1;
  }

  if (!fullResolution) {
    final resizeResult = await _resizeToMaxDimension(output);
    if (resizeResult != 0) return resizeResult;
  }

  final sizeBytes = file.lengthSync();
  stdout.writeln('SCREENSHOT_SAVED=$output');
  stdout.writeln('SIZE=${_formatSize(sizeBytes)}');
  return 0;
}

// ---------------------------------------------------------------------------
// Platform dispatch
// ---------------------------------------------------------------------------

Future<int> _dispatchScreenshot({
  required String platform,
  required bool emulator,
  required String? deviceId,
  required String output,
}) async {
  if (platform.startsWith('android')) {
    return _captureAndroid(deviceId, output);
  }

  if (platform.startsWith('ios') && emulator) {
    return _captureIosSimulator(deviceId, output);
  }

  if (platform.startsWith('ios') && !emulator) {
    // Physical iOS: no native CLI screenshot tool available.
    // Fall through to fdb_helper VM extension.
    stderr.writeln(
      'WARNING: No native screenshot tool for physical iOS.\n'
      '  Falling back to fdb_helper (Flutter surface only, no status bar).\n'
      '  Ensure your app includes fdb_helper and calls '
      'FdbBinding.ensureInitialized().',
    );
    return _captureViaFdbHelper(output);
  }

  if (platform.startsWith('darwin')) {
    return _captureMacOs(output);
  }

  if (platform.startsWith('linux')) {
    return _captureLinux(output);
  }

  if (platform.startsWith('windows')) {
    stderr.writeln(
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
  stderr.writeln(
    'WARNING: Unsupported platform "$platform".\n'
    '  Attempting fdb_helper fallback.',
  );
  return _captureViaFdbHelper(output);
}

// ---------------------------------------------------------------------------
// Legacy capture (no platform.txt — sessions before this change)
// ---------------------------------------------------------------------------

/// Heuristic capture used when no platform file exists:
/// checks adb for Android, otherwise assumes iOS simulator.
Future<int> _legacyCapture(String output) async {
  if (await _isAndroidConnected()) {
    return _captureAndroid(null, output);
  }
  return _captureIosSimulator(null, output);
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

Future<int> _captureAndroid(String? deviceId, String output) async {
  try {
    final args = deviceId != null ? ['-s', deviceId] : <String>[];
    final result = await Process.run(
      'adb',
      [...args, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      stderr.writeln('ERROR: adb screencap failed: ${result.stderr}');
      return 1;
    }
    File(output).writeAsBytesSync(result.stdout as List<int>);
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run adb: $e');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// iOS Simulator
// ---------------------------------------------------------------------------

Future<int> _captureIosSimulator(String? deviceId, String output) async {
  try {
    // Use the stored device ID (simulator UDID) when available so we target
    // the correct simulator even if multiple are booted.
    final target = deviceId ?? 'booted';
    final result = await Process.run('xcrun', [
      'simctl',
      'io',
      target,
      'screenshot',
      output,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln(
          'ERROR: xcrun simctl screenshot failed: ${result.stderr}');
      return 1;
    }
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run xcrun: $e');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// macOS desktop
// ---------------------------------------------------------------------------

/// Captures the macOS Flutter app window using `screencapture -l <windowId>`.
///
/// Looks up the window by walking the process tree rooted at the stored PID
/// (the flutter run launcher PID). Falls back to fdb_helper if the window
/// cannot be found or `screencapture` lacks Screen Recording permission.
Future<int> _captureMacOs(String output) async {
  final pid = readPid();
  if (pid == null) {
    stderr.writeln(
      'ERROR: No PID in session — cannot locate macOS window. Re-launch the app.',
    );
    return 1;
  }

  try {
    final windowId = await _macWindowId(pid);
    if (windowId == null) {
      stderr.writeln(
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
      stderr.writeln(
        'WARNING: screencapture failed — Screen Recording permission may be\n'
        '  required: System Settings > Privacy & Security > Screen Recording.\n'
        '  Falling back to fdb_helper (Flutter surface only, no title bar).',
      );
      return _captureViaFdbHelper(output);
    }
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: macOS screenshot failed: $e');
    return 1;
  }
}

/// Returns the CGWindowID for the on-screen window owned by [pid] or any of
/// its child processes.
///
/// `flutter run` (the stored PID) spawns the actual .app as a child, so we
/// walk one level of the process tree via `pgrep -P`.
Future<int?> _macWindowId(int pid) async {
  // Collect stored PID plus immediate children.
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
    r'''
import Cocoa
let pidStrs = CommandLine.arguments[1].split(separator: ",")
let pids = pidStrs.compactMap { Int32($0) }
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [NSDictionary] else { exit(0) }
for w in list {
  guard let ownerPid = w[kCGWindowOwnerPID] as? Int32, pids.contains(ownerPid) else { continue }
  if let num = w[kCGWindowNumber] as? Int { print(num); break }
}
''',
    pidsArg,
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
Future<int> _captureLinux(String output) async {
  final pid = readPid();
  if (pid != null) {
    final result = await _captureLinuxNative(pid, output);
    if (result == 0) return 0;
    // -1 means native attempt failed — fall through to fdb_helper.
  }

  final reason = pid == null
      ? 'No PID in session'
      : 'xdotool/import not available or Wayland display (native capture not '
          'supported on Wayland).\n'
          '  For X11: install xdotool and ImageMagick '
          '(e.g. sudo apt install xdotool imagemagick)';
  stderr.writeln(
    'WARNING: $reason.\n'
    '  Falling back to fdb_helper (Flutter surface only, no window chrome).\n'
    '  Ensure your app includes fdb_helper and calls '
    'FdbBinding.ensureInitialized().',
  );
  return _captureViaFdbHelper(output);
}

/// Tries `xdotool search --pid` + `import -window` to capture the window.
/// Returns 0 on success, -1 to signal the caller should try the fallback.
Future<int> _captureLinuxNative(int pid, String output) async {
  try {
    final xdo = await Process.run('xdotool', [
      'search',
      '--onlyvisible',
      '--pid',
      '$pid',
    ]);
    if (xdo.exitCode != 0) return -1;

    final windowId = (xdo.stdout as String).trim().split('\n').first.trim();
    if (windowId.isEmpty) return -1;

    final imp = await Process.run('import', ['-window', windowId, output]);
    return imp.exitCode == 0 ? 0 : -1;
  } catch (_) {
    return -1;
  }
}

// ---------------------------------------------------------------------------
// Web (Chrome DevTools Protocol)
// ---------------------------------------------------------------------------

/// Captures a Flutter Web app screenshot via CDP `Page.captureScreenshot`.
///
/// Requires the app to be running in Chrome with `--remote-debugging-port`
/// set. fdb does not yet plumb the CDP port through session state, so this
/// checks a fixed default port (9222) and the CHROME_CDP_PORT env variable.
Future<int> _captureWeb(String output) async {
  final portStr = Platform.environment['CHROME_CDP_PORT'] ?? '9222';
  final port = int.tryParse(portStr) ?? 9222;

  // Fetch the page list from the CDP HTTP endpoint.
  final String wsUrl;
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req =
          await client.getUrl(Uri.parse('http://localhost:$port/json'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final pages = jsonDecode(body) as List<dynamic>;
      if (pages.isEmpty) {
        stderr.writeln('ERROR: No Chrome pages found on CDP port $port.\n'
            '  Launch Chrome with --remote-debugging-port=$port.');
        return 1;
      }
      final page = pages.firstWhere(
        (p) => (p as Map<String, dynamic>)['type'] == 'page',
        orElse: () => pages.first,
      ) as Map<String, dynamic>;
      final url = page['webSocketDebuggerUrl'] as String?;
      if (url == null) {
        stderr.writeln('ERROR: No WebSocket debugger URL in CDP page list.');
        return 1;
      }
      wsUrl = url;
    } finally {
      client.close();
    }
  } catch (e) {
    stderr.writeln('ERROR: Could not connect to Chrome CDP on port $port: $e');
    return 1;
  }

  // Capture via CDP Page.captureScreenshot.
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(wsUrl);
    final completer = Completer<Map<String, dynamic>>();

    ws.listen(
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
              StateError('WebSocket closed before CDP response'));
        }
      },
    );

    ws.add(jsonEncode(
        {'id': 1, 'method': 'Page.captureScreenshot', 'params': {}}));

    final response =
        await completer.future.timeout(const Duration(seconds: 10));
    final data = (response['result'] as Map<String, dynamic>?)?['data']
        as String?;
    if (data == null) {
      stderr.writeln('ERROR: CDP screenshot returned no image data.');
      return 1;
    }
    File(output).writeAsBytesSync(base64Decode(data));
    return 0;
  } on TimeoutException {
    stderr.writeln('ERROR: CDP screenshot timed out.');
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: CDP screenshot failed: $e');
    return 1;
  } finally {
    await ws?.close();
  }
}

// ---------------------------------------------------------------------------
// fdb_helper VM extension fallback
// ---------------------------------------------------------------------------

/// Captures a screenshot via the `ext.fdb.screenshot` VM service extension
/// registered by `fdb_helper`. Returns the PNG as base64 and writes it to
/// [output].
///
/// Used when no native OS screenshot tool is available (physical iOS, Windows,
/// Linux Wayland).
Future<int> _captureViaFdbHelper(String output) async {
  final vmUri = readVmUri();
  if (vmUri == null) {
    stderr.writeln(
      'ERROR: No VM service URI in session and no native screenshot tool '
      'available.\n  Re-launch the app.',
    );
    return 1;
  }

  try {
    final isolateId = await checkFdbHelper();
    if (isolateId == null) {
      stderr.writeln(
        'ERROR: fdb_helper not found in the running app.\n'
        '  Add fdb_helper to pubspec.yaml and call '
        'FdbBinding.ensureInitialized() in main().',
      );
      return 1;
    }

    final response = await vmServiceCall(
      'ext.fdb.screenshot',
      params: {'isolateId': isolateId},
    );

    final result = unwrapRawExtensionResult(response);
    if (result is Map && result.containsKey('error')) {
      stderr.writeln('ERROR: fdb_helper screenshot: ${result['error']}');
      return 1;
    }

    final resultMap = result as Map<String, dynamic>?;
    final base64Data = resultMap?['screenshot'] as String?;
    if (base64Data == null) {
      stderr.writeln('ERROR: No screenshot data in fdb_helper response.');
      return 1;
    }

    File(output).writeAsBytesSync(base64Decode(base64Data));
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: fdb_helper screenshot failed: $e');
    return 1;
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
/// Uses the pure-Dart `image` package — no external tools, cross-platform.
/// No-ops if the image already fits within the limit (still re-encodes for
/// better compression than the raw capture output).
/// Returns 0 on success, 1 on failure.
Future<int> _resizeToMaxDimension(String path) async {
  try {
    final file = File(path);
    final bytes = await file.readAsBytes();

    final src = img.decodePng(bytes);
    if (src == null) {
      stderr.writeln('ERROR: Could not decode PNG for resizing');
      return 1;
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
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Could not resize image: $e');
    return 1;
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

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
