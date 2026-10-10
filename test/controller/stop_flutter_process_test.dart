import 'dart:async';
import 'dart:io';

import 'package:fdb/src/controller/controller.dart';
import 'package:test/test.dart';

void main() {
  group('stopFlutterProcess', () {
    test('sends SIGTERM and stops there when the process exits', () async {
      final process = _FakeProcess(exitOn: {ProcessSignal.sigterm});

      await stopFlutterProcess(process, exitTimeout: const Duration(milliseconds: 200));

      expect(process.signals, [ProcessSignal.sigterm]);
    });

    test('sends SIGKILL when SIGTERM is ignored', () async {
      final process = _FakeProcess(exitOn: {ProcessSignal.sigkill});

      await stopFlutterProcess(process, exitTimeout: const Duration(milliseconds: 100));

      expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
    });

    test('does nothing to a process that already exited', () async {
      final process = _FakeProcess()..exit(0);

      await stopFlutterProcess(process, exitTimeout: const Duration(milliseconds: 100));

      expect(process.signals, isEmpty);
    });
  });
}

class _FakeProcess implements Process {
  _FakeProcess({this.exitOn = const {}});

  final Set<ProcessSignal> exitOn;
  final signals = <ProcessSignal>[];
  final _exitCode = Completer<int>();

  void exit(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (exitOn.contains(signal)) exit(-signal.signalNumber);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
