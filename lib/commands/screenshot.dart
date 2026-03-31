import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';
import 'package:fdb/vm_service.dart';

Future<int> runScreenshot(List<String> args) async {
  String? deviceId;
  String? output;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
      case '--output':
        output = args[++i];
    }
  }

  final session = resolveSession(deviceId);
  if (session == null) return 1;

  final resolvedDeviceId = session['deviceId'] as String? ?? deviceId ?? '';
  final platform = session['platform'] as String?;
  final pid = session['pid'];
  final vmServiceUri = session['vmServiceUri'] as String?;
  final cdpPort = session['cdpPort'] as int?;
  final emulator = session['emulator'] as bool? ?? false;

  final resolvedOutput = output ?? screenshotPath(resolvedDeviceId);

  if (platform == null) {
    stderr.writeln('ERROR: No platform found in session. Re-launch the app.');
    return 1;
  }

  // Ensure the output directory exists
  Directory(File(resolvedOutput).parent.path).createSync(recursive: true);

  final exitCode = await _dispatchScreenshot(
    platform: platform,
    deviceId: resolvedDeviceId,
    pid: pid is int ? pid : (pid is String ? int.tryParse(pid) : null),
    vmServiceUri: vmServiceUri,
    cdpPort: cdpPort,
    emulator: emulator,
    output: resolvedOutput,
  );

  if (exitCode != 0) return exitCode;

  final file = File(resolvedOutput);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: Screenshot file was not created at $resolvedOutput');
    return 1;
  }

  final sizeBytes = file.lengthSync();
  stdout.writeln('SCREENSHOT_SAVED=$resolvedOutput');
  stdout.writeln('SIZE=${_formatSize(sizeBytes)}');
  return 0;
}

Future<int> _dispatchScreenshot({
  required String platform,
  required String deviceId,
  required int? pid,
  required String? vmServiceUri,
  required int? cdpPort,
  required bool emulator,
  required String output,
}) async {
  if (platform.startsWith('android')) {
    return _screenshotAndroid(deviceId, output);
  }

  if (platform.startsWith('ios') && emulator) {
    return _screenshotIosSimulator(deviceId, output);
  }

  if (platform.startsWith('ios') && !emulator) {
    stderr.writeln(
      'WARNING: No native screenshot tool available for physical iOS devices. '
      'Falling back to fdb_helper.',
    );
    return _screenshotViaFdbHelper(vmServiceUri, output);
  }

  if (platform.startsWith('darwin')) {
    return _screenshotMacOs(pid, vmServiceUri, output);
  }

  if (platform.startsWith('linux')) {
    return _screenshotLinux(pid, vmServiceUri, output);
  }

  if (platform.startsWith('windows')) {
    stderr.writeln(
      'WARNING: No native screenshot CLI available for Windows. '
      'Falling back to fdb_helper.',
    );
    return _screenshotViaFdbHelper(vmServiceUri, output);
  }

  if (platform == 'web-javascript') {
    if (cdpPort == null) {
      stderr.writeln('ERROR: No CDP port found in session for web platform.');
      return 1;
    }
    return _screenshotViaCdp(cdpPort, output);
  }

  stderr.writeln('ERROR: Unsupported platform: $platform');
  return 1;
}

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

Future<int> _screenshotAndroid(String deviceId, String output) async {
  try {
    final result = await Process.run('bash', [
      '-c',
      'adb -s ${shellEscape(deviceId)} exec-out screencap -p > ${shellEscape(output)}',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('ERROR: adb screencap failed: ${result.stderr}');
      return 1;
    }
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: Failed to run adb: $e');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// iOS Simulator
// ---------------------------------------------------------------------------

Future<int> _screenshotIosSimulator(String deviceId, String output) async {
  try {
    final result = await Process.run('xcrun', [
      'simctl',
      'io',
      deviceId,
      'screenshot',
      output,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('ERROR: xcrun simctl screenshot failed: ${result.stderr}');
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

Future<int> _screenshotMacOs(
  int? pid,
  String? vmServiceUri,
  String output,
) async {
  if (pid == null) {
    stderr.writeln(
      'ERROR: No PID in session — cannot locate macOS window. '
      'Re-launch the app.',
    );
    return 1;
  }

  try {
    final windowId = await _getMacWindowId(pid);
    if (windowId == null) {
      stderr.writeln(
        'WARNING: Could not find macOS window for PID $pid. '
        'Falling back to fdb_helper.',
      );
      return _screenshotViaFdbHelper(vmServiceUri, output);
    }

    final result = await Process.run('screencapture', [
      '-l',
      windowId.toString(),
      '-o',
      output,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln(
        'WARNING: screencapture failed (Screen Recording permission may '
        'be needed). Falling back to fdb_helper.',
      );
      return _screenshotViaFdbHelper(vmServiceUri, output);
    }
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: macOS screenshot failed: $e');
    return 1;
  }
}

/// Returns the CGWindowID for the on-screen window owned by [pid] or any of
/// its child processes. On macOS, `flutter run` (the stored PID) spawns the
/// actual .app as a child process, so we need to walk the process tree.
Future<int?> _getMacWindowId(int pid) async {
  // Collect the stored PID plus all descendant PIDs.
  final pids = <int>[pid];
  try {
    final pgrepResult = await Process.run('pgrep', ['-P', pid.toString()]);
    if (pgrepResult.exitCode == 0) {
      for (final line in (pgrepResult.stdout as String).trim().split('\n')) {
        final childPid = int.tryParse(line.trim());
        if (childPid != null) pids.add(childPid);
      }
    }
  } catch (_) {
    // pgrep not available — fall through with just the original PID.
  }

  final pidsArg = pids.join(',');
  final result = await Process.run('swift', [
    '-e',
    '''
import Cocoa
let pidStrs = CommandLine.arguments[1].split(separator: ",")
let pids = pidStrs.compactMap { Int32(\$0) }
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

Future<int> _screenshotLinux(
  int? pid,
  String? vmServiceUri,
  String output,
) async {
  if (pid != null) {
    final nativeResult = await _screenshotLinuxNative(pid, output);
    if (nativeResult == 0) return 0;
    // nativeResult == -1 means native capture failed — fall through to fdb_helper
  }

  final reason = pid == null
      ? 'No PID in session'
      : 'Native Linux screenshot (xdotool/import) failed';
  stderr.writeln('WARNING: $reason. Falling back to fdb_helper.');
  return _screenshotViaFdbHelper(vmServiceUri, output);
}

/// Tries xdotool + ImageMagick import to capture the window.
/// Returns 0 on success, -1 to signal that the caller should try the fallback.
Future<int> _screenshotLinuxNative(int pid, String output) async {
  try {
    final xdoResult = await Process.run('xdotool', [
      'search',
      '--onlyvisible',
      '--pid',
      pid.toString(),
    ]);
    if (xdoResult.exitCode != 0) return -1;

    final windowId = (xdoResult.stdout as String).trim().split('\n').last;
    if (windowId.isEmpty) return -1;

    final importResult = await Process.run('import', [
      '-window',
      windowId,
      output,
    ]);
    return importResult.exitCode == 0 ? 0 : -1;
  } catch (_) {
    return -1;
  }
}

// ---------------------------------------------------------------------------
// Web (CDP)
// ---------------------------------------------------------------------------

Future<int> _screenshotViaCdp(int cdpPort, String output) async {
  // 1. Fetch the page list from the CDP HTTP endpoint
  final String wsUrl;
  try {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://localhost:$cdpPort/json'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      final pages = jsonDecode(body) as List<dynamic>;
      if (pages.isEmpty) {
        stderr.writeln('ERROR: No Chrome pages found on CDP port $cdpPort');
        return 1;
      }

      // Prefer a page-type tab over devtools panels
      final page = pages.firstWhere(
        (p) => (p as Map<String, dynamic>)['type'] == 'page',
        orElse: () => pages.first,
      ) as Map<String, dynamic>;

      final url = page['webSocketDebuggerUrl'] as String?;
      if (url == null) {
        stderr.writeln('ERROR: No WebSocket URL for Chrome page');
        return 1;
      }
      wsUrl = url;
    } finally {
      client.close();
    }
  } catch (e) {
    stderr.writeln('ERROR: Failed to connect to CDP on port $cdpPort: $e');
    return 1;
  }

  // 2. Connect via WebSocket and capture screenshot
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(wsUrl);
    final completer = Completer<Map<String, dynamic>>();

    ws.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        if (json['id'] == 1 && !completer.isCompleted) {
          completer.complete(json);
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('WebSocket closed before CDP response'),
          );
        }
      },
    );

    ws.add(jsonEncode({
      'id': 1,
      'method': 'Page.captureScreenshot',
      'params': {'format': 'png'},
    }));

    final cdpResponse = await completer.future.timeout(
      const Duration(seconds: 10),
    );

    final resultData =
        (cdpResponse['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (resultData == null) {
      stderr.writeln('ERROR: CDP screenshot returned no data');
      return 1;
    }

    final bytes = base64Decode(resultData);
    File(output).writeAsBytesSync(bytes);
    return 0;
  } on TimeoutException {
    stderr.writeln('ERROR: CDP screenshot timed out');
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: CDP screenshot failed: $e');
    return 1;
  } finally {
    await ws?.close();
  }
}

// ---------------------------------------------------------------------------
// fdb_helper fallback
// ---------------------------------------------------------------------------

Future<int> _screenshotViaFdbHelper(
  String? vmServiceUri,
  String output,
) async {
  if (vmServiceUri == null) {
    stderr.writeln(
      'ERROR: No VM service URI in session and no native screenshot tool '
      'available. Re-launch the app.',
    );
    return 1;
  }

  try {
    final isolateId = await checkFdbHelper(vmServiceUri);
    if (isolateId == null) {
      stderr.writeln(
        'ERROR: fdb_helper not found in app and no native screenshot tool '
        'available. Add fdb_helper to your Flutter app.',
      );
      return 1;
    }

    final response = await vmServiceCall(
      vmServiceUri,
      'ext.fdb.screenshot',
      params: {'isolateId': isolateId},
    );

    final result = unwrapRawExtensionResult(response);
    if (result is Map && result.containsKey('error')) {
      stderr.writeln('ERROR: Screenshot failed: ${result['error']}');
      return 1;
    }

    final base64Data =
        (result as Map<String, dynamic>?)?['screenshot'] as String?;
    if (base64Data == null) {
      stderr.writeln('ERROR: No screenshot data in fdb_helper response');
      return 1;
    }

    final bytes = base64Decode(base64Data);
    File(output).writeAsBytesSync(bytes);
    return 0;
  } catch (e) {
    stderr.writeln('ERROR: fdb_helper screenshot failed: $e');
    return 1;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
