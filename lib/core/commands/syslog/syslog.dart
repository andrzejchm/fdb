import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/syslog/syslog_models.dart';
import 'package:fdb/core/process_utils.dart';

export 'package:fdb/core/commands/syslog/syslog_models.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Reads native system logs from the device under debug.
///
/// Platform dispatch:
///   Android       — adb logcat
///   iOS simulator — xcrun simctl spawn device log show / stream
///   iOS physical  — idevicesyslog (requires libimobiledevice)
///   macOS         — log show / stream
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<SyslogResult> runSyslog(SyslogInput input) async {
  final platformInfo = readPlatformInfo();
  if (platformInfo == null) {
    return const SyslogError('No platform info found. Is the app running?');
  }

  final platform = platformInfo.platform.toLowerCase();
  final emulator = platformInfo.emulator;
  final device = readDevice();

  if (platform.startsWith('android')) {
    return _runAndroid(device: device, input: input);
  } else if (platform == 'ios' || platform.startsWith('ios-')) {
    if (emulator) {
      return _runIosSimulator(device: device, input: input);
    } else {
      return _runIosPhysical(input: input);
    }
  } else if (platform == 'darwin' || platform == 'macos') {
    return _runMacos(input: input);
  } else {
    return SyslogError('Unsupported platform: $platform');
  }
}

// ---------------------------------------------------------------------------
// Platform implementations
// ---------------------------------------------------------------------------

Future<SyslogResult> _runAndroid({
  required String? device,
  required SyslogInput input,
}) async {
  if (!_isToolOnPath('adb')) {
    return const SyslogToolMissing(
      tool: 'adb',
      hint: 'Install Android SDK platform-tools and ensure adb is on PATH.',
    );
  }

  final sinceSeconds = _parseDurationSeconds(input.since)!;
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
    if (!input.follow) ...['-d', '-T', sinceFormatted],
  ];

  return _spawnAndStream(
    executable: 'adb',
    args: adbArgs,
    predicate: input.predicate,
    last: input.last,
    follow: input.follow,
  );
}

Future<SyslogResult> _runIosSimulator({
  required String? device,
  required SyslogInput input,
}) async {
  if (!_isToolOnPath('xcrun')) {
    return const SyslogToolMissing(
      tool: 'xcrun',
      hint: 'Install Xcode command-line tools: xcode-select --install',
    );
  }

  if (device == null) {
    return const SyslogError('No device ID found. Is the app running?');
  }

  final escapedPredicate =
      input.predicate?.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final nsPredicate = escapedPredicate != null
      ? 'eventMessage CONTAINS "$escapedPredicate"'
      : null;

  if (input.follow) {
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
      last: input.last,
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
    input.since,
    '--style',
    'compact',
    if (nsPredicate != null) ...['--predicate', nsPredicate],
  ];

  return _spawnAndStream(
    executable: 'xcrun',
    args: xcrunArgs,
    predicate: null, // already filtered natively
    last: input.last,
    follow: false,
  );
}

Future<SyslogResult> _runIosPhysical({required SyslogInput input}) async {
  if (!_isToolOnPath('idevicesyslog')) {
    return const SyslogToolMissing(
      tool: 'idevicesyslog',
      hint: 'Install: brew install libimobiledevice',
    );
  }

  if (input.sinceExplicit) {
    return const SyslogError(
      '--since is not supported on iOS physical devices (idevicesyslog does not support time filtering)',
    );
  }

  if (!input.follow) {
    return const SyslogError(
      'fdb syslog requires --follow on iOS physical devices (idevicesyslog does not support snapshot mode)',
    );
  }

  return _spawnAndStream(
    executable: 'idevicesyslog',
    args: const [],
    predicate: input.predicate,
    last: input.last,
    follow: true,
  );
}

Future<SyslogResult> _runMacos({required SyslogInput input}) async {
  if (!_isToolOnPath('log')) {
    return const SyslogToolMissing(
      tool: 'log',
      hint: 'This is unexpected on macOS — ensure /usr/bin is on PATH.',
    );
  }

  final escapedPredicate =
      input.predicate?.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final nsPredicate = escapedPredicate != null
      ? 'eventMessage CONTAINS "$escapedPredicate"'
      : null;

  if (input.follow) {
    final streamArgs = <String>[
      'stream',
      if (nsPredicate != null) ...['--predicate', nsPredicate],
    ];
    return _spawnAndStream(
      executable: 'log',
      args: streamArgs,
      predicate: null, // already filtered natively
      last: input.last,
      follow: true,
    );
  }

  final showArgs = <String>[
    'show',
    '--last',
    input.since,
    '--style',
    'compact',
    if (nsPredicate != null) ...['--predicate', nsPredicate],
  ];

  return _spawnAndStream(
    executable: 'log',
    args: showArgs,
    predicate: null, // already filtered natively
    last: input.last,
    follow: false,
  );
}

// ---------------------------------------------------------------------------
// Subprocess streaming
// ---------------------------------------------------------------------------

/// Spawns [executable] with [args] and returns a [SyslogStream].
///
/// When [follow] is false, the returned [SyslogStream.lines] is a finite
/// stream: all stdout lines are collected after the subprocess exits, filtered
/// by [predicate], capped to the last [last] lines, then emitted in order.
///
/// When [follow] is true, lines are emitted live as they arrive (filtered by
/// [predicate]). The stream ends when the subprocess exits or [cancel] is
/// called.
Future<SyslogResult> _spawnAndStream({
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
    return SyslogError('Failed to start $executable: $e');
  }

  if (follow) {
    return _followStream(process: process, predicate: predicate);
  } else {
    return _snapshotStream(process: process, predicate: predicate, last: last);
  }
}

/// Returns a [SyslogStream] for live (--follow) mode.
SyslogResult _followStream({
  required Process process,
  required String? predicate,
}) {
  var killed = false;
  StreamSubscription<ProcessSignal>? sigintSub;

  final controller = StreamController<String>();

  Future<void> cancel() async {
    killed = true;
    process.kill();
  }

  final exitCodeFuture = process.exitCode.then((code) => killed ? 0 : code);

  // Pipe stderr to our stderr.
  process.stderr
      .transform(const SystemEncoding().decoder)
      .listen(stderr.write);

  // Feed filtered stdout lines into the controller.
  process.stdout
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())
      .where((line) => predicate == null || line.contains(predicate))
      .listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );

  // Cancel the controller when the process exits.
  exitCodeFuture.then((_) {
    if (!controller.isClosed) controller.close();
  });

  // Wire up SIGINT so the CLI adapter can also close cleanly via cancel().
  sigintSub = ProcessSignal.sigint.watch().listen((_) async {
    await cancel();
    await sigintSub?.cancel();
  });

  return SyslogStream(
    lines: controller.stream,
    exitCode: exitCodeFuture,
    cancel: cancel,
  );
}

/// Returns a [SyslogStream] for snapshot (non-follow) mode.
///
/// Collects all stdout, filters, caps, then emits via a synchronous
/// [Stream.fromIterable] so the CLI adapter can use the same subscription
/// pattern as follow mode.
Future<SyslogResult> _snapshotStream({
  required Process process,
  required String? predicate,
  required int? last,
}) async {
  final stderrFuture = process.stderr
      .transform(const SystemEncoding().decoder)
      .forEach(stderr.write);

  final buffer = <String>[];
  await for (final line in process.stdout
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())) {
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

  return SyslogStream(
    lines: Stream.fromIterable(lines),
    exitCode: Future.value(exitCode),
    cancel: () async {},
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
