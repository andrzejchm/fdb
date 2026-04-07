import 'dart:io';

import 'package:fdb/constants.dart';

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

  // Detect platform by checking adb devices
  final isAndroid = await _isAndroidDevice();

  if (isAndroid) {
    final result = await Process.run(
      'adb',
      ['exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      stderr.writeln('ERROR: Screenshot failed: ${result.stderr}');
      return 1;
    }
    File(output).writeAsBytesSync(result.stdout as List<int>);
  } else {
    // Assume iOS simulator
    final result = await Process.run('xcrun', [
      'simctl',
      'io',
      'booted',
      'screenshot',
      output,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('ERROR: Screenshot failed: ${result.stderr}');
      return 1;
    }
  }

  final file = File(output);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: Screenshot file not created');
    return 1;
  }

  if (!fullResolution) {
    final resizeResult = await _resizeToLogicalResolution(output);
    if (resizeResult != 0) return resizeResult;
  }

  final sizeBytes = file.lengthSync();
  stdout.writeln('SCREENSHOT_SAVED=$output');
  stdout.writeln('SIZE=${_formatSize(sizeBytes)}');
  return 0;
}

/// Reads the pixel width of [path] via `sips` and downscales to logical
/// resolution (1x) in-place. Returns 0 on success, 1 on failure.
Future<int> _resizeToLogicalResolution(String path) async {
  final queryResult = await Process.run('sips', ['-g', 'pixelWidth', path]);
  if (queryResult.exitCode != 0) {
    stderr.writeln(
        'ERROR: Could not read image dimensions: ${queryResult.stderr}');
    return 1;
  }

  final pixelWidth = _parsePixelWidth(queryResult.stdout as String);
  if (pixelWidth == null) {
    stderr.writeln('ERROR: Could not parse image width from sips output');
    return 1;
  }

  final logicalWidth = _logicalWidth(pixelWidth);
  if (logicalWidth == pixelWidth) return 0; // already 1x, nothing to do

  final resizeResult = await Process.run('sips', [
    '--resampleWidth',
    '$logicalWidth',
    path,
    '--out',
    path,
  ]);
  if (resizeResult.exitCode != 0) {
    stderr.writeln('ERROR: Could not resize image: ${resizeResult.stderr}');
    return 1;
  }

  return 0;
}

/// Parses the pixel width from `sips -g pixelWidth` output.
///
/// Example output:
/// ```
///   /tmp/fdb_screenshot.png
///     pixelWidth: 1170
/// ```
int? _parsePixelWidth(String sipsOutput) {
  final match = RegExp(r'pixelWidth:\s*(\d+)').firstMatch(sipsOutput);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Returns the logical (1x) width for a given native [pixelWidth].
///
/// Heuristic:
/// - > 1000 px → 3x Retina device → divide by 3
/// - > 500 px  → 2x Retina device → divide by 2
/// - otherwise → already 1x
int _logicalWidth(int pixelWidth) {
  if (pixelWidth > 1000) return pixelWidth ~/ 3;
  if (pixelWidth > 500) return pixelWidth ~/ 2;
  return pixelWidth;
}

Future<bool> _isAndroidDevice() async {
  try {
    final result = await Process.run('adb', ['devices']);
    final output = result.stdout as String;
    // Check if there's at least one device listed (beyond the header line)
    final lines =
        output.split('\n').where((l) => l.contains('\tdevice')).toList();
    return lines.isNotEmpty;
  } catch (_) {
    return false;
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
