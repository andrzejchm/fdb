import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/commands/syslog/syslog.dart';
import 'package:test/test.dart';

void main() {
  group('syslog decoding', () {
    // Raw logcat output from a real device can contain bytes such as 0xFF that
    // are never valid UTF-8; the chunk boundary also splits a multi-byte char.
    final stdoutChunks = [
      [...utf8.encode('I/flutter: ok\nE/native: bad '), 0xFF, 0xE2, 0x82],
      [0xAC, ...utf8.encode(' end\n')],
    ];
    const expected = ['I/flutter: ok', 'E/native: bad \uFFFD\u20AC end'];

    for (final follow in [false, true]) {
      test('replaces invalid UTF-8 instead of failing (follow: $follow)', () async {
        final process = _FakeProcess(stdoutChunks, stderrBytes: [...utf8.encode('syslog test stderr '), 0xFF, 10]);

        final result = await streamSyslogProcess(process, predicate: null, last: null, follow: follow);

        final stream = result as SyslogStream;
        expect(await stream.lines.toList(), expected);
        expect(await stream.exitCode, 0);
      });
    }
  });
}

/// Emits the given output, then exits with 0 once stdout has been drained,
/// like a real process whose pipe closes as it exits.
class _FakeProcess implements Process {
  _FakeProcess(List<List<int>> stdoutChunks, {required List<int> stderrBytes}) : stderr = Stream.value(stderrBytes) {
    stdout = Stream.fromIterable(stdoutChunks).transform(
      StreamTransformer.fromHandlers(handleDone: (sink) {
        sink.close();
        _exit.complete(0);
      }),
    );
  }

  final _exit = Completer<int>();

  @override
  late final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 0;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
