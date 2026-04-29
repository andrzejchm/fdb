import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/core/vm_lifecycle_events.dart';
import 'package:test/test.dart';

void main() {
  group('VM lifecycle events', () {
    test('identifies Flutter frame events as reload completion signals', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.Frame',
          },
        },
      };

      expect(isFlutterFrameEvent(event), isTrue);
    });

    test('isFlutterFrameEvent ignores non-frame extension events', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.ServiceExtensionStateChanged',
          },
        },
      };

      expect(isFlutterFrameEvent(event), isFalse);
    });

    test('identifies service extension state changed events', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.ServiceExtensionStateChanged',
          },
        },
      };

      expect(isFlutterServiceExtensionStateChangedEvent(event), isTrue);
    });

    test('isReloadCompletionEvent matches Flutter.Frame', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.Frame',
          },
        },
      };

      expect(isReloadCompletionEvent(event), isTrue);
    });

    test('isReloadCompletionEvent matches Flutter.ServiceExtensionStateChanged', () {
      // iOS simulators emit this event after reload even when Flutter.Frame is absent.
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.ServiceExtensionStateChanged',
          },
        },
      };

      expect(isReloadCompletionEvent(event), isTrue);
    });

    test('isReloadCompletionEvent ignores unrelated events', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.FrameworkInitialization',
          },
        },
      };

      expect(isReloadCompletionEvent(event), isFalse);
    });

    test('identifies Flutter first-frame events as restart completion signals', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.FirstFrame',
          },
        },
      };

      expect(isFlutterFirstFrameEvent(event), isTrue);
    });

    test('identifies IsolateRunnable events on the Isolate stream', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Isolate',
          'event': {'kind': 'IsolateRunnable'},
        },
      };

      expect(isIsolateRunnableEvent(event), isTrue);
    });

    test('isIsolateRunnableEvent ignores events from other streams', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {'kind': 'IsolateRunnable'},
        },
      };

      expect(isIsolateRunnableEvent(event), isFalse);
    });

    test('isRestartCompletionEvent matches Flutter.FirstFrame', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.FirstFrame',
          },
        },
      };

      expect(isRestartCompletionEvent(event), isTrue);
    });

    test('isRestartCompletionEvent matches IsolateRunnable', () {
      // iOS simulators emit IsolateRunnable after restart but not Flutter.FirstFrame.
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Isolate',
          'event': {'kind': 'IsolateRunnable'},
        },
      };

      expect(isRestartCompletionEvent(event), isTrue);
    });

    test('isRestartCompletionEvent ignores unrelated events', () {
      final event = {
        'method': 'streamNotify',
        'params': {
          'streamId': 'Isolate',
          'event': {'kind': 'IsolateStart'},
        },
      };

      expect(isRestartCompletionEvent(event), isFalse);
    });

    test('waits until a matching VM event arrives', () async {
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      final future = waitForVmServiceEvent(
        events: controller.stream,
        matches: isReloadCompletionEvent,
        timeout: const Duration(seconds: 1),
      );

      controller.add({
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.FrameworkInitialization',
          },
        },
      });
      controller.add({
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.ServiceExtensionStateChanged',
          },
        },
      });

      expect(await future, isTrue);
    });

    test('returns false when no matching VM event arrives before timeout', () async {
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      final result = await waitForVmServiceEvent(
        events: controller.stream,
        matches: isFlutterFrameEvent,
        timeout: const Duration(milliseconds: 1),
      );

      expect(result, isFalse);
    });

    test('fails fast when VM stream subscription is rejected', () async {
      final tempDir = await Directory.systemTemp.createTemp('fdb_vm_lifecycle_test');
      initSessionDir(tempDir.path);
      addTearDown(() async {
        initSessionDir(Directory.current.path);
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.transform(WebSocketTransformer()).listen((socket) {
        socket.listen((data) async {
          final request = jsonDecode(data as String) as Map<String, dynamic>;
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'error': {
                'code': 123,
                'message': 'subscription denied',
              },
            }),
          );
          await socket.close();
        });
      });

      final sessionDir = ensureSessionDir();
      final wsUri = 'ws://${server.address.host}:${server.port}/ws';
      await File('$sessionDir/vm_uri.txt').writeAsString(wsUri);

      await expectLater(
        waitForVmEventAfterSignal(
          streamIds: const ['Extension'],
          matches: isFlutterFrameEvent,
          signal: () {},
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
