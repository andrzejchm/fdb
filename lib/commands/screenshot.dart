import 'dart:io';

import 'package:fdb/constants.dart';

Future<int> runScreenshot(List<String> args) async {
  var output = defaultScreenshotPath;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--output') {
      output = args[++i];
    } else if (arg.startsWith('--output=')) {
      output = arg.substring('--output='.length);
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

  final sizeBytes = file.lengthSync();
  stdout.writeln('SCREENSHOT_SAVED=$output');
  stdout.writeln('SIZE=${_formatSize(sizeBytes)}');
  return 0;
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
