import 'dart:io';

import 'package:fdb/process_utils.dart';

/// Opens a deep link URL on the connected device (Android or iOS simulator).
Future<int> runDeeplink(List<String> args) async {
  String? deviceId;
  String? url;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
      default:
        // First positional argument is the URL
        if (!args[i].startsWith('-')) {
          url = args[i];
        }
    }
  }

  if (url == null) {
    stderr.writeln('ERROR: No URL provided');
    return 1;
  }

  final session = resolveSession(deviceId);
  if (session == null) return 1;

  final platform = session['platform'] as String?;
  final resolvedDeviceId = session['deviceId'] as String;
  final emulator = session['emulator'] as bool? ?? false;

  if (platform != null && platform.startsWith('android')) {
    return _openAndroid(url, resolvedDeviceId);
  }

  // Physical iOS devices are not supported for deep links.
  if (platform != null && platform.startsWith('ios') && !emulator) {
    stderr.writeln(
      'ERROR: Physical iOS devices not supported for deep links.',
    );
    return 1;
  }

  if (platform != null && platform.startsWith('ios')) {
    return _openIos(url, resolvedDeviceId);
  }

  if (platform != null && platform.startsWith('darwin')) {
    return _openDarwin(url);
  }

  stderr.writeln(
      'ERROR: Deep links are only supported on Android devices, iOS simulators, and macOS desktop');
  return 1;
}

Future<int> _openAndroid(String url, String deviceId) async {
  final result = await Process.run('adb', [
    '-s',
    deviceId,
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

Future<int> _openIos(String url, String deviceId) async {
  // Warn about Universal Links potentially opening Safari
  if (url.startsWith('http://') || url.startsWith('https://')) {
    stderr.writeln(
      'WARNING: Universal Links (https://) may open Safari instead of the app on iOS simulator',
    );
  }

  final result =
      await Process.run('xcrun', ['simctl', 'openurl', deviceId, url]);

  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    stderr.writeln('ERROR: Failed to open deep link: $details');
    return 1;
  }

  stdout.writeln('DEEPLINK_OPENED=$url');
  return 0;
}

Future<int> _openDarwin(String url) async {
  final result = await Process.run('open', [url]);

  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    stderr.writeln('ERROR: Failed to open deep link: $details');
    return 1;
  }

  stdout.writeln('DEEPLINK_OPENED=$url');
  return 0;
}
