import 'dart:io';

/// Opens a deep link URL on the connected device (Android or iOS simulator).
Future<int> runDeeplink(List<String> args) async {
  String? url;

  for (var i = 0; i < args.length; i++) {
    // First positional argument is the URL
    if (!args[i].startsWith('-')) {
      url = args[i];
    }
  }

  if (url == null) {
    stderr.writeln('ERROR: No URL provided');
    return 1;
  }

  // Detect platform: Android first, then iOS simulator, else unsupported
  final isAndroid = await _isAndroidDevice();
  if (isAndroid) {
    return _openAndroid(url);
  }

  final isIos = await _isIosSimulatorBooted();
  if (isIos) {
    return _openIos(url);
  }

  stderr.writeln(
      'ERROR: Deep links are only supported on Android devices and iOS simulators');
  return 1;
}

Future<int> _openAndroid(String url) async {
  final result = await Process.run('adb', [
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

  final stdoutStr = result.stdout as String;
  final stderrStr = result.stderr as String;

  if (result.exitCode != 0 || stdoutStr.contains('Error:')) {
    final details = stderrStr.isNotEmpty ? stderrStr.trim() : stdoutStr.trim();
    stderr.writeln('ERROR: Failed to open deep link: $details');
    return 1;
  }

  stdout.writeln('DEEPLINK_OPENED=$url');
  return 0;
}

Future<int> _openIos(String url) async {
  // Warn about Universal Links potentially opening Safari
  if (url.startsWith('http://') || url.startsWith('https://')) {
    stderr.writeln(
      'WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator',
    );
  }

  final result =
      await Process.run('xcrun', ['simctl', 'openurl', 'booted', url]);

  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    stderr.writeln('ERROR: Failed to open deep link: $details');
    return 1;
  }

  stdout.writeln('DEEPLINK_OPENED=$url');
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

/// Returns true if at least one iOS simulator is currently booted.
Future<bool> _isIosSimulatorBooted() async {
  try {
    final result =
        await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted']);
    final output = result.stdout as String;
    // A booted device entry contains a UUID in parentheses, e.g. (A1B2C3D4-...)
    return RegExp(r'\([\dA-F-]{36}\)').hasMatch(output);
  } catch (_) {
    return false;
  }
}
