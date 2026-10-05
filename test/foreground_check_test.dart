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
  test('foreground warning contract', () {
    expect(foregroundWarning('resumed'), isNull);
    expect(foregroundWarning(null), isNull);
    expect(foregroundWarning('paused'), startsWith('WARNING: App is not in the foreground (lifecycle=paused).'));
    expect(foregroundWarning('inactive'), startsWith('WARNING: App is inactive (lifecycle=inactive).'));
    expect(const VmNotRespondingException(pid: 7).toString(), vmNotRespondingMessage(7));
  });

  test('classifyLifecycleQueryError: only a timeout with the app alive means not responding', () {
    final timeout = TimeoutException('t');
    expect(classifyLifecycleQueryError(timeout, appAlive: true), isA<LifecycleVmNotResponding>());
    const suspended = VmNotRespondingException();
    expect(classifyLifecycleQueryError(suspended, appAlive: true), isA<LifecycleVmNotResponding>());
    expect(classifyLifecycleQueryError(timeout, appAlive: false), isA<LifecycleUnavailable>());
    expect(classifyLifecycleQueryError(StateError('no session'), appAlive: true), isA<LifecycleUnavailable>());
  });

  group('queryLifecycleState', () {
    test('returns unavailable instead of throwing when there is no session', () async {
      await _createTempSessionRoot();
      expect(await queryLifecycleState(), isA<LifecycleUnavailable>());
    });

    test('reads the state from the ext.fdb.lifecycle payload relayed by the controller', () async {
      await _createTempSessionRoot();
      await _startFakeController({
        ControllerCommand.findFlutterIsolateId: {'isolateId': 'isolates/1'},
        ControllerCommand.extCall: {
          'result': {
            'result': {'status': 'Success', 'lifecycleState': 'paused'},
          },
        },
      });
      final result = await queryLifecycleState();
      expect(result, isA<LifecycleReported>().having((r) => r.state, 'state', 'paused'));
    });

    test('reports not responding when the controller hangs past the budget', () async {
      await _createTempSessionRoot();
      final port = await _startSilentServer();
      File(controllerPortFile).writeAsStringSync('$port');
      File(controllerTokenFile).writeAsStringSync('token');
      final result = await queryLifecycleState(timeout: const Duration(milliseconds: 300));
      expect(result, isA<LifecycleVmNotResponding>());
    });
  });

  group('describeScreen with checkFdbHelper', () {
    test('returns DescribeVmNotResponding when the controller reports an unresponsive VM', () async {
      await _createTempSessionRoot();
      await _startFakeController({
        ControllerCommand.checkFdbHelper: {'isolateId': null, vmNotRespondingField: true},
      });
      // This test process is alive; platform file makes isAppPidAlive use kill -0.
      File(platformFile).writeAsStringSync('ios true');
      File(appPidFile).writeAsStringSync('$pid');
      final result = await describeScreen(());
      expect(result, isA<DescribeVmNotResponding>().having((r) => r.pid, 'pid', pid));
    });

    test('keeps DescribeNoFdbHelper when the extension is simply not registered', () async {
      await _createTempSessionRoot();
      await _startFakeController({
        ControllerCommand.checkFdbHelper: {'isolateId': null},
      });
      expect(await describeScreen(()), isA<DescribeNoFdbHelper>());
    });
  });

  test('CheckFdbHelperCommandRunner flags vmNotResponding when the VM service never answers', () async {
    await _createTempSessionRoot();
    final port = await _startSilentServer();
    File(platformFile).writeAsStringSync('ios true');
    File(vmUriFile).writeAsStringSync('ws://127.0.0.1:$port/ws');
    final response = await const CheckFdbHelperCommandRunner().execute(const CheckFdbHelperCommandRequest(token: 't'));
    final result = response.toJson()['result'] as Map<String, Object?>;
    expect(result['isolateId'], isNull);
    expect(result[vmNotRespondingField], isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('captureScreenshot appends the lifecycle query warning', () async {
    Future<List<String>> captureWarnings(LifecycleQueryResult lifecycle) async {
      final root = await _createTempSessionRoot();
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

    expect(await captureWarnings(const LifecycleReported('paused')), [foregroundWarning('paused')]);
    expect(await captureWarnings(const LifecycleVmNotResponding()), [vmNotRespondingWarning]);
    expect(await captureWarnings(const LifecycleReported('resumed')), isEmpty);
    expect(await captureWarnings(const LifecycleUnavailable()), isEmpty);
  });
}

/// Starts a server that accepts TCP connections but never answers, like the
/// VM service of an app that iOS suspended in the background. Returns its port.
Future<int> _startSilentServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  server.listen(sockets.add);
  addTearDown(() async {
    for (final s in sockets) {
      s.destroy();
    }
    await server.close();
  });
  return server.port;
}

/// Starts a fake controller that answers each command in [responses] with its
/// fields, and fails any other command.
Future<void> _startFakeController(Map<ControllerCommand, Map<String, Object?>> responses) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  File(controllerPortFile).writeAsStringSync('${server.port}');
  File(controllerTokenFile).writeAsStringSync('token');
  server.listen((socket) async {
    final request = await readControllerRequest(socket);
    final fields = responses[request.command];
    final response = fields != null ? ControllerResponse.success(fields) : ControllerResponse.failure('Unexpected');
    await writeControllerResponse(socket, response);
    await socket.close();
  });
}

Future<Directory> _createTempSessionRoot() async {
  final root = await Directory.systemTemp.createTemp('fdb_foreground_test_');
  final session = Directory('${root.path}/.fdb');
  session.createSync(recursive: true);
  initSessionDirFromPath(session.path);
  addTearDown(() => root.delete(recursive: true));
  return root;
}
