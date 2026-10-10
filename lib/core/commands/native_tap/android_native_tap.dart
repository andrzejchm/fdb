import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/native_tap/android_ui_dump.dart';
import 'package:fdb/core/commands/native_tap/native_tap_models.dart';
import 'package:fdb/core/commands/native_tap/native_text_match.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

/// Runs `adb` with [args] (device selection already included).
typedef AdbRunner = Future<ProcessResult> Function(List<String> args);

/// Returns the running app's device pixel ratio, or null when unknown.
typedef AppDevicePixelRatioReader = Future<double?> Function();

/// Where `uiautomator dump` writes when `/dev/tty` doesn't work: unique per
/// fdb invocation so concurrent runs never read each other's dump. Under
/// `/data/local/tmp` because the shell user can always write there, unlike
/// `/sdcard` on some devices.
String androidUiDumpFileFor({required int pid, required int timestampMs}) =>
    '/data/local/tmp/fdb_window_dump_${pid}_$timestampMs.xml';

/// Android side of `fdb native-tap`: by coordinates (`--at`, optionally
/// `--logical`) or by label (`--text`).
///
/// [adb], [appDevicePixelRatio], [now], [sleep] and [dumpFile] are
/// injectable for tests. Never throws.
Future<NativeTapResult> nativeTapAndroid(
  NativeTapInput input, {
  required String? deviceId,
  AdbRunner? adb,
  AppDevicePixelRatioReader? appDevicePixelRatio,
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
  String? dumpFile,
}) async {
  final deviceArgs = deviceId != null ? ['-s', deviceId] : <String>[];
  final runAdb = adb ?? _runAdb;
  Future<ProcessResult> run(List<String> args) => runAdb([...deviceArgs, ...args]);

  try {
    final text = input.text;
    if (text != null) {
      return await _tapByText(
        query: text,
        index: input.index,
        timeout: Duration(seconds: input.timeoutSeconds ?? defaultNativeTapTextTimeoutSeconds),
        run: run,
        now: now ?? DateTime.now,
        sleep: sleep ?? Future<void>.delayed,
        dumpFile: dumpFile ?? androidUiDumpFileFor(pid: pid, timestampMs: DateTime.now().millisecondsSinceEpoch),
      );
    }

    final x = input.x!;
    final y = input.y!;
    if (!input.logical) {
      return await _inputTap(run, x.toInt(), y.toInt());
    }
    final dpr = await _resolveDevicePixelRatio(run, appDevicePixelRatio ?? readAppDevicePixelRatio);
    switch (dpr) {
      case _DprUnavailable(:final reason):
        return NativeTapDevicePixelRatioUnavailable(reason);
      case _DprKnown(:final value):
        final physical = logicalToPhysical(x, y, value);
        return await _inputTap(run, physical.x, physical.y);
    }
  } on ProcessException catch (e) {
    return NativeTapAdbExecutionFailed(e.toString());
  } catch (e) {
    return NativeTapAdbFailed('$e');
  }
}

Future<ProcessResult> _runAdb(List<String> args) => Process.run(
      'adb',
      args,
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );

Future<NativeTapResult> _inputTap(
  Future<ProcessResult> Function(List<String>) run,
  int x,
  int y, {
  String? text,
}) async {
  final result = await run(['shell', 'input', 'tap', '$x', '$y']);
  return classifyAndroidInputTap(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      ) ??
      NativeTapAndroid(x: x, y: y, text: text);
}

/// Classifies the output of `adb shell input tap`. Returns null when the tap
/// went through.
///
/// adb often exits 0 even when `input` threw, so the output is checked
/// regardless of the exit code: `SecurityException` / `INJECT_EVENTS` means
/// the OS blocked injection; any other `Exception` is a failure.
NativeTapResult? classifyAndroidInputTap({required int exitCode, required String stdout, required String stderr}) {
  final output = [stdout.trim(), stderr.trim()].where((s) => s.isNotEmpty).join('\n');
  if (output.contains('INJECT_EVENTS') || output.contains('SecurityException')) {
    return NativeTapInputInjectionBlocked(output);
  }
  if (exitCode != 0) {
    return NativeTapAdbFailed(output.isNotEmpty ? output : 'adb exited with code $exitCode');
  }
  if (output.contains('Exception')) return NativeTapAdbFailed(output);
  return null;
}

// ---------------------------------------------------------------------------
// --logical
// ---------------------------------------------------------------------------

/// Converts Flutter logical pixels to the physical pixels `input tap` takes.
({int x, int y}) logicalToPhysical(double x, double y, double devicePixelRatio) =>
    (x: (x * devicePixelRatio).round(), y: (y * devicePixelRatio).round());

/// Reads the density Android uses for layout from `adb shell wm density`:
/// the override density when set, else the physical density. Returns null
/// when neither is present.
int? parseWmDensity(String output) {
  int? read(String label) {
    final m = RegExp('$label density:\\s*(\\d+)').firstMatch(output);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  final density = read('Override') ?? read('Physical');
  return density != null && density > 0 ? density : null;
}

sealed class _Dpr {
  const _Dpr();
}

class _DprKnown extends _Dpr {
  const _DprKnown(this.value);
  final double value;
}

class _DprUnavailable extends _Dpr {
  const _DprUnavailable(this.reason);
  final String reason;
}

/// Prefers the ratio the app's FlutterView reports (via `ext.fdb.lifecycle`).
/// Falls back to `wm density / 160`, which is how Android derives
/// `DisplayMetrics.density`, the value Flutter uses, so the two agree unless
/// the app runs with its own density.
Future<_Dpr> _resolveDevicePixelRatio(
  Future<ProcessResult> Function(List<String>) run,
  AppDevicePixelRatioReader appDevicePixelRatio,
) async {
  final fromApp = await appDevicePixelRatio();
  if (fromApp != null && fromApp > 0) return _DprKnown(fromApp);

  final result = await run(['shell', 'wm', 'density']);
  final density = result.exitCode == 0 ? parseWmDensity('${result.stdout}') : null;
  if (density != null) return _DprKnown(density / 160);
  final details = '${result.stdout}${result.stderr}'.trim();
  return _DprUnavailable(
    'the app did not report one and `adb shell wm density` gave '
    '${details.isEmpty ? 'no output' : '"$details"'}',
  );
}

/// Asks the running app for its FlutterView's device pixel ratio via
/// `ext.fdb.lifecycle`. Null when there is no app session, fdb_helper is
/// older than the field, or the call takes over 2 s.
Future<double?> readAppDevicePixelRatio() async {
  try {
    return await _readAppDevicePixelRatio().timeout(const Duration(seconds: 2));
  } catch (_) {
    // Advisory: the caller falls back to `wm density`.
    return null;
  }
}

Future<double?> _readAppDevicePixelRatio() async {
  final isolateId = await findFlutterIsolateId();
  if (isolateId == null) return null;
  final response = await extCall('ext.fdb.lifecycle', params: {'isolateId': isolateId});
  if (response.errorCode != null) return null;
  final payload = response.extensionResult;
  final inner = payload?['result'];
  final dpr = (inner is Map ? inner : payload)?['devicePixelRatio'];
  return dpr is num ? dpr.toDouble() : null;
}

// ---------------------------------------------------------------------------
// --text
// ---------------------------------------------------------------------------

Future<NativeTapResult> _tapByText({
  required String query,
  required int? index,
  required Duration timeout,
  required Future<ProcessResult> Function(List<String>) run,
  required DateTime Function() now,
  required Future<void> Function(Duration) sleep,
  required String dumpFile,
}) async {
  final deadline = now().add(timeout);
  final dumper = _UiDumper(run, dumpFile);
  List<String>? lastLabels;
  int? lastMatchCount;
  String? lastDumpError;

  while (true) {
    final dump = await dumper.dump();
    switch (dump) {
      case AndroidUiDumpInvalid(:final reason):
        lastDumpError = reason;
      case AndroidUiDumpParsed(:final nodes):
        lastDumpError = null;
        final matches = findAndroidUiMatches(nodes, query);
        switch (pickNativeMatch(matches, index: index)) {
          case NativeMatchPicked(:final match):
            final b = match.bounds;
            return _inputTap(run, b.centerX, b.centerY, text: oneLineLabel(match.label));
          case NativeMatchAmbiguous(:final matches):
            return NativeTapAmbiguous(
              query: query,
              candidates: [
                for (final m in matches) (label: oneLineLabel(m.label), x: m.bounds.centerX, y: m.bounds.centerY),
              ],
            );
          case NativeMatchNone():
            lastLabels = androidVisibleLabels(nodes);
            lastMatchCount = matches.length;
        }
    }
    if (!now().isBefore(deadline)) break;
    await sleep(nativeTapTextPollInterval);
  }

  if (lastLabels == null) return NativeTapUiDumpFailed(lastDumpError ?? 'no window dump');
  if (index != null && lastMatchCount != null && lastMatchCount > 0) {
    return NativeTapIndexOutOfRange(query: query, index: index, count: lastMatchCount);
  }
  return NativeTapNoMatch(query: query, visibleLabels: lastLabels);
}

/// Dumps the window with `uiautomator dump`, streaming it over `/dev/tty`
/// first and falling back to a file on devices where that doesn't work.
/// Sticks with the file once it has worked and `/dev/tty` hasn't.
///
/// "could not get idle state" is not a `/dev/tty` problem (the file dump would
/// wait for the same idle screen), so it never triggers the fallback. The
/// file is deleted before each dump, so a stale one is never read, and after
/// reading it.
class _UiDumper {
  _UiDumper(this._run, this._file);

  final Future<ProcessResult> Function(List<String>) _run;
  final String _file;
  bool _useFile = false;

  Future<AndroidUiDumpParse> dump() async {
    if (_useFile) return _dumpToFile();
    final tty = await _dumpToTty();
    if (tty is AndroidUiDumpParsed || (tty is AndroidUiDumpInvalid && isAndroidIdleStateError(tty.reason))) {
      return tty;
    }
    final file = await _dumpToFile();
    if (file is AndroidUiDumpParsed) {
      _useFile = true;
      return file;
    }
    return tty;
  }

  Future<AndroidUiDumpParse> _dumpToTty() async {
    final result = await _run(['exec-out', 'uiautomator', 'dump', '/dev/tty']);
    return parseAndroidUiDump('${result.stdout}\n${result.stderr}');
  }

  Future<AndroidUiDumpParse> _dumpToFile() async {
    final dump = await _run(['shell', 'rm -f $_file; uiautomator dump $_file']);
    final dumpOutput = '${dump.stdout}\n${dump.stderr}';
    if (dumpOutput.contains('ERROR:')) return parseAndroidUiDump(dumpOutput);
    final cat = await _run(['exec-out', 'cat', _file]);
    await _run(['shell', 'rm', '-f', _file]);
    if (cat.exitCode != 0) {
      final details = '${cat.stderr}${cat.stdout}'.trim();
      return AndroidUiDumpInvalid('could not read $_file: $details');
    }
    return parseAndroidUiDump('${cat.stdout}');
  }
}

/// True for uiautomator's "could not get idle state" error: the screen kept
/// changing while it waited.
bool isAndroidIdleStateError(String reason) => reason.contains('idle state');
