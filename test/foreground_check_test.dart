import 'dart:async';
import 'dart:io';

import 'package:fdb/core/commands/describe/describe.dart';
import 'package:fdb/core/commands/screenshot/screenshot.dart';
import 'package:fdb/core/foreground_check.dart';
import 'package:fdb/src/controller/commands/check_fdb_helper.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/controller_transport.dart';
import 'package:fdb/src/controller/session.dart';
import 'package:fdb/src/controller/vm_not_responding_exception.dart';
import 'package:test/test.dart';

void main() {
  group('foregroundWarning', () {
    test('returns null when the app is resumed', () {
      expect(foregroundWarning('resumed'), isNull);
    });

    test('returns null when the state is unknown (older fdb_helper)', () {
      expect(foregroundWarning(null), isNull);
    });

    for (final state in ['paused', 'hidden', 'detached']) {
      test('warns that the app is not in the foreground when $state', () {
        final warning = foregroundWarning(state);
        expect(warning, startsWith('WARNING: App is not in the foreground (lifecycle=$state).'));
        expect(warning, contains("output reflects this app's last frame"));
        expect(warning, isNot(contains('\n')));
      });
    }

    test('warns about a covering system UI when inactive', () {
      expect(foregroundWarning('inactive'), startsWith('WARNING: App is inactive (lifecycle=inactive).'));
    });
  });

  group('lifecycleQueryWarning', () {
    test('maps a reported state through foregroundWarning', () {
      expect(lifecycleQueryWarning(const LifecycleReported('paused')), foregroundWarning('paused'));
      expect(lifecycleQueryWarning(const LifecycleReported('resumed')), isNull);
      expect(lifecycleQueryWarning(const LifecycleReported(null)), isNull);
    });

    test('is silent when the lifecycle is unavailable', () {
      expect(lifecycleQueryWarning(const LifecycleUnavailable()), isNull);
    });

    test('warns when the VM is not responding', () {
      expect(lifecycleQueryWarning(const LifecycleVmNotResponding()), vmNotRespondingWarning);
      expect(vmNotRespondingWarning, startsWith('WARNING: App is not responding to the VM service;'));
    });
  });

  group('classifyLifecycleQueryError', () {
    test('timeout with the app alive means not responding', () {
      expect(
        classifyLifecycleQueryError(TimeoutException('t'), appAlive: true),
        isA<LifecycleVmNotResponding>(),
      );
      expect(
        classifyLifecycleQueryError(const VmNotRespondingException(pid: 1), appAlive: true),
        isA<LifecycleVmNotResponding>(),
      );
    });

    test('timeout with the app dead is unavailable', () {
      expect(classifyLifecycleQueryError(TimeoutException('t'), appAlive: false), isA<LifecycleUnavailable>());
    });

    test('non-timeout failures (no session, no helper, errors) are unavailable', () {
      expect(classifyLifecycleQueryError(StateError('no session'), appAlive: true), isA<LifecycleUnavailable>());
      expect(classifyLifecycleQueryError(Exception('boom'), appAlive: true), isA<LifecycleUnavailable>());
    });
  });

  group('queryLifecycleState', () {
    test('returns unavailable instead of throwing when there is no session', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() => root.delete(recursive: true));

      expect(await queryLifecycleState(), isA<LifecycleUnavailable>());
    });

    test('reports not responding when the controller hangs past the budget', () async {
      final root = await _createTempSessionRoot();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      // Accept connections but never answer — like a suspended app's VM.
      final sockets = <Socket>[];
      server.listen(sockets.add);
      addTearDown(() async {
        for (final s in sockets) {
          s.destroy();
        }
        await server.close();
        await root.delete(recursive: true);
      });
      File(controllerPortFile).writeAsStringSync('${server.port}');
      File(controllerTokenFile).writeAsStringSync('token');

      final result = await queryLifecycleState(timeout: const Duration(milliseconds: 300));

      expect(result, isA<LifecycleVmNotResponding>());
    });
  });

  group('vmNotRespondingMessage', () {
    test('includes the pid when known', () {
      expect(
        vmNotRespondingMessage(4242),
        'App is not responding to the VM service (pid 4242 is alive). It is most likely in the background '
        'and suspended by the OS (another app is in front). Bring it to the foreground, then retry.',
      );
    });

    test('omits the pid when unknown', () {
      expect(vmNotRespondingMessage(null), startsWith('App is not responding to the VM service. It is'));
    });

    test('exception toString is the message so generic ERROR paths print it', () {
      expect(const VmNotRespondingException(pid: 7).toString(), vmNotRespondingMessage(7));
    });
  });

  group('describeScreen with checkFdbHelper', () {
    test('returns DescribeVmNotResponding when the controller reports an unresponsive VM', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() => root.delete(recursive: true));
      await _startFakeController({'isolateId': null, vmNotRespondingField: true});
      // This test process is alive; platform file makes isAppPidAlive use kill -0.
      File(platformFile).writeAsStringSync('ios true');
      File(appPidFile).writeAsStringSync('$pid');

      final result = await describeScreen(());

      expect(result, isA<DescribeVmNotResponding>().having((r) => r.pid, 'pid', pid));
    });

    test('keeps DescribeNoFdbHelper when the extension is simply not registered', () async {
      final root = await _createTempSessionRoot();
      addTearDown(() => root.delete(recursive: true));
      await _startFakeController({'isolateId': null});

      expect(await describeScreen(()), isA<DescribeNoFdbHelper>());
    });
  });

  group('CheckFdbHelperCommandRunner', () {
    test('flags vmNotResponding when the VM service never answers', () async {
      final root = await _createTempSessionRoot();
      // Accepts TCP but never completes the WebSocket handshake — like the
      // VM service of an app that iOS suspended in the background.
      final vm = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      vm.listen(sockets.add);
      addTearDown(() async {
        for (final s in sockets) {
          s.destroy();
        }
        await vm.close();
        await root.delete(recursive: true);
      });
      File(platformFile).writeAsStringSync('ios true');
      File(vmUriFile).writeAsStringSync('ws://127.0.0.1:${vm.port}/ws');

      final response = await const CheckFdbHelperCommandRunner().execute(
        const CheckFdbHelperCommandRequest(token: 't'),
      );

      final json = response.toJson();
      final result = json['result'] as Map<String, Object?>;
      expect(result['isolateId'], isNull);
      expect(result[vmNotRespondingField], isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('captureScreenshot foreground warning', () {
    Future<List<String>> captureWarnings(LifecycleQueryResult lifecycle) async {
      final root = await _createTempSessionRoot();
      addTearDown(() => root.delete(recursive: true));
      // Android with a bogus device makes the native capture fail fast,
      // which still surfaces accumulated warnings on ScreenshotFailed.
      File(platformFile).writeAsStringSync('android-arm64 true');
      File(deviceFile).writeAsStringSync('fdb-test-nonexistent-device');

      final result = await captureScreenshot(
        (output: '${root.path}/shot.png', fullResolution: false),
        lifecycleQuery: () async => lifecycle,
      );
      return switch (result) {
        ScreenshotSaved(:final warnings) => warnings,
        ScreenshotFailed(:final warnings) => warnings,
      };
    }

    test('appends the lifecycle warning reported by the injected query', () async {
      expect(await captureWarnings(const LifecycleReported('paused')), [foregroundWarning('paused')]);
    });

    test('appends the not-responding warning when the VM is unresponsive', () async {
      expect(await captureWarnings(const LifecycleVmNotResponding()), [vmNotRespondingWarning]);
    });

    test('adds no warning when the app is resumed or lifecycle is unavailable', () async {
      expect(await captureWarnings(const LifecycleReported('resumed')), isEmpty);
      expect(await captureWarnings(const LifecycleUnavailable()), isEmpty);
    });
  });
}

/// Starts a fake controller that answers `checkFdbHelper` with [fields].
Future<void> _startFakeController(Map<String, Object?> fields) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  File(controllerPortFile).writeAsStringSync('${server.port}');
  File(controllerTokenFile).writeAsStringSync('token');
  server.listen((socket) async {
    final request = await readControllerRequest(socket);
    final response = request.command == ControllerCommand.checkFdbHelper
        ? ControllerResponse.success(fields)
        : ControllerResponse.failure('Unexpected command');
    await writeControllerResponse(socket, response);
    await socket.close();
  });
}

Future<Directory> _createTempSessionRoot() async {
  final root = await Directory.systemTemp.createTemp('fdb_foreground_test_');
  final session = Directory('${root.path}/.fdb');
  session.createSync(recursive: true);
  initSessionDirFromPath(session.path);
  return root;
}
