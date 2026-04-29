import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/process_utils.dart';

/// Reads native system logs from the device under debug.
///
/// Platform dispatch:
///   Android       — adb logcat
///   iOS simulator — xcrun simctl spawn device log show
///   iOS physical  — idevicesyslog (requires libimobiledevice)
///   macOS         — log show on the host
///
/// Usage:
///   fdb syslog [--since <duration>] [--predicate <pattern>] [--last <n>] [--follow]
Future<int> runSyslog(List<String> args) async {
  var since = '5m';
  var sinceExplicit = false;
  String? predicate;
  int? last;
  var follow = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--since':
        since = args[++i];
        sinceExplicit = true;
      case '--predicate':
        predicate = args[++i];
      case '--last':
        final raw = args[++i];
        last = int.tryParse(raw);
        if (last == null) {
          stderr.writeln('ERROR: Invalid value for --last: $raw');
          return 1;
        }
      case '--follow':
        follow = true;
      default:
        stderr.writeln('ERROR: Unknown flag: ${args[i]}');
        return 1;
    }
  }

  if (last != null && last <= 0) {
    stderr.writeln('ERROR: --last must be a positive integer');
    return 1;
  }

  if (follow && last != null) {
    stderr.writeln('ERROR: --last is not supported with --follow');
    return 1;
  }

  if (follow && sinceExplicit) {
    stderr.writeln(
      'ERROR: --since is not supported with --follow (log stream always starts from now)',
    );
    return 1;
  }

  final sinceSeconds = _parseDurationSeconds(since);
  if (sinceSeconds == null) {
    stderr.writeln(
      'ERROR: Invalid --since value: $since. '
      'Use a number followed by s, m, or h (e.g. 30s, 5m, 1h)',
    );
    return 1;
  }

  final platformInfo = readPlatformInfo();
  if (platformInfo == null) {
    stderr.writeln('ERROR: No platform info found. Is the app running?');
    return 1;
  }

  final platform = platformInfo.platform.toLowerCase();
  final emulator = platformInfo.emulator;
  final device = readDevice();

  if (platform.startsWith('android')) {
    return _runAndroid(
      device: device,
      since: since,
      predicate: predicate,
      last: last,
      follow: follow,
    );
  } else if (platform == 'ios' || platform.startsWith('ios-')) {
    if (emulator) {
      return _runIosSimulator(
        device: device,
        since: since,
        predicate: predicate,
        last: last,
        follow: follow,
      );
    } else {
      return _runIosPhysical(
        sinceExplicit: sinceExplicit,
        predicate: predicate,
        last: last,
        follow: follow,
      );
    }
  } else if (platform == 'darwin' || platform == 'macos') {
    return _runMacos(
      since: since,
      predicate: predicate,
      last: last,
      follow: follow,
    );
  } else {
    stderr.writeln('ERROR: Unsupported platform: $platform');
    return 1;
  }
}

Future<int> _runAndroid({
  required String? device,
  required String since,
  required String? predicate,
  required int? last,
  required bool follow,
}) async {
  if (!_isToolOnPath('adb')) {
    stderr.writeln(
      'ERROR: adb not found. Install Android SDK platform-tools and ensure adb is on PATH.',
    );
    return 1;
  }

  final sinceSeconds = _parseDurationSeconds(since)!;
  final sinceTime = DateTime.now().subtract(Duration(seconds: sinceSeconds));
  final sinceFormatted = '${sinceTime.month.toString().padLeft(2, '0')}-'
      '${sinceTime.day.toString().padLeft(2, '0')} '
      '${sinceTime.hour.toString().padLeft(2, '0')}:'
      '${sinceTime.minute.toString().padLeft(2, '0')}:'
      '${sinceTime.second.toString().padLeft(2, '0')}.'
      '${sinceTime.millisecond.toString().padLeft(3, '0')}';
  final adbArgs = <String>[
    if (device != null) ...['-s', device],
    'logcat',
    if (!follow) ...['-d', '-T', sinceFormatted],
  ];

  return _spawnAndStream(
    executable: 'adb',
    args: adbArgs,
    predicate: predicate,
    last: last,
    follow: follow,
  );
}

Future<int> _runIosSimulator({
  required String? device,
  required String since,
  required String? predicate,
  required int? last,
  required bool follow,
}) async {
  if (!_isToolOnPath('xcrun')) {
    stderr.writeln(
      'ERROR: xcrun not found. Install Xcode command-line tools: xcode-select --install',
    );
    return 1;
  }

  if (device == null) {
    stderr.writeln('ERROR: No device ID found. Is the app running?');
    return 1;
  }

  final escapedPredicate = predicate?.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final nsPredicate = escapedPredicate != null ? 'eventMessage CONTAINS "$escapedPredicate"' : null;

  if (follow) {
    // Use `log stream` for live output on the simulator
    final streamArgs = <String>[
      'simctl',
      'spawn',
      device,
      'log',
      'stream',
      if (nsPredicate != null) ...['--predicate', nsPredicate],
    ];
    return _spawnAndStream(
      executable: 'xcrun',
      args: streamArgs,
      predicate: null, // already filtered natively
      last: last,
      follow: true,
    );
  }

  final xcrunArgs = <String>[
    'simctl',
    'spawn',
    device,
    'log',
    'show',
    '--last',
    since,
    '--style',
    'compact',
    if (nsPredicate != null) ...['--predicate', nsPredicate],
  ];

  return _spawnAndStream(
    executable: 'xcrun',
    args: xcrunArgs,
    predicate: null, // already filtered natively
    last: last,
    follow: false,
  );
}

Future<int> _runIosPhysical({
  required bool sinceExplicit,
  required String? predicate,
  required int? last,
  required bool follow,
}) async {
  if (!_isToolOnPath('idevicesyslog')) {
    stderr.writeln(
      'ERROR: idevicesyslog not found. '
      'Install: brew install libimobiledevice',
    );
    return 1;
  }

  if (sinceExplicit) {
    stderr.writeln(
      'ERROR: --since is not supported on iOS physical devices (idevicesyslog does not support time filtering)',
    );
    return 1;
  }

  if (!follow) {
    stderr.writeln(
      'ERROR: fdb syslog requires --follow on iOS physical devices (idevicesyslog does not support snapshot mode)',
    );
    return 1;
  }

  return _spawnAndStream(
    executable: 'idevicesyslog',
    args: const [],
    predicate: predicate,
    last: last,
    follow: true,
  );
}

Future<int> _runMacos({
  required String since,
  required String? predicate,
  required int? last,
  required bool follow,
}) async {
  if (!_isToolOnPath('log')) {
    stderr.writeln(
      'ERROR: log command not found. This is unexpected on macOS — ensure /usr/bin is on PATH.',
    );
    return 1;
  }

  final escapedPredicate = predicate?.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final nsPredicate = escapedPredicate != null ? 'eventMessage CONTAINS "$escapedPredicate"' : null;

  if (follow) {
    final streamArgs = <String>[
      'stream',
      if (nsPredicate != null) ...['--predicate', nsPredicate],
    ];
    return _spawnAndStream(
      executable: 'log',
      args: streamArgs,
      predicate: null, // already filtered natively
      last: last,
      follow: true,
    );
  }

  final showArgs = <String>[
    'show',
    '--last',
    since,
    '--style',
    'compact',
    if (nsPredicate != null) ...['--predicate', nsPredicate],
  ];

  return _spawnAndStream(
    executable: 'log',
    args: showArgs,
    predicate: null, // already filtered natively
    last: last,
    follow: false,
  );
}

/// Spawns [executable] with [args], streams output line-by-line.
///
/// When [follow] is false, collects all lines, applies [predicate] substring
/// filter and [last] line cap, then prints and exits.
///
/// When [follow] is true, streams each line immediately (with optional
/// [predicate] filter) until the process exits or the user hits Ctrl-C.
Future<int> _spawnAndStream({
  required String executable,
  required List<String> args,
  required String? predicate,
  required int? last,
  required bool follow,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, args);
  } catch (e) {
    stderr.writeln('ERROR: Failed to start $executable: $e');
    return 1;
  }

  if (follow) {
    // Stream live — do not buffer.
    var killed = false;
    final sigintSub = ProcessSignal.sigint.watch().listen((_) {
      killed = true;
      process.kill();
    });

    final stderrFuture = process.stderr.transform(const SystemEncoding().decoder).forEach(stderr.write);
    try {
      await for (final line in _lines(process.stdout)) {
        if (predicate == null || line.contains(predicate)) {
          stdout.writeln(line);
        }
      }
    } finally {
      await sigintSub.cancel();
    }
    await stderrFuture;
    final exitCode = await process.exitCode;
    return killed ? 0 : exitCode;
  }

  // Non-follow: collect all output, apply filter + cap.
  final stderrFuture = process.stderr.transform(const SystemEncoding().decoder).forEach(stderr.write);
  final buffer = <String>[];
  await for (final line in _lines(process.stdout)) {
    if (predicate == null || line.contains(predicate)) {
      buffer.add(line);
    }
  }

  await stderrFuture;
  final exitCode = await process.exitCode;

  var lines = buffer;
  if (last != null && lines.length > last) {
    lines = lines.sublist(lines.length - last);
  }

  for (final line in lines) {
    stdout.writeln(line);
  }

  return exitCode;
}

/// Decodes a [Stream<List<int>>] into a stream of lines.
Stream<String> _lines(Stream<List<int>> byteStream) {
  return byteStream.transform(const SystemEncoding().decoder).transform(const LineSplitter());
}

/// Returns true if [tool] can be found via `which`.
bool _isToolOnPath(String tool) {
  try {
    final result = Process.runSync('which', [tool]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Parses a duration string like `30s`, `5m`, `1h` into seconds.
/// Returns null if the format is unrecognised.
int? _parseDurationSeconds(String s) {
  if (s.isEmpty) return null;
  final suffix = s[s.length - 1];
  final numStr = s.substring(0, s.length - 1);
  final n = int.tryParse(numStr);
  if (n == null || n <= 0) return null;
  switch (suffix) {
    case 's':
      return n;
    case 'm':
      return n * 60;
    case 'h':
      return n * 3600;
    default:
      return null;
  }
}
