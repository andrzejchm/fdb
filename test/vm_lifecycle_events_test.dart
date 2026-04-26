import 'dart:async';

import 'package:fdb/vm_lifecycle_events.dart';
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

    test('ignores non-frame extension events for reload completion', () {
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

    test('waits until a matching VM event arrives', () async {
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      final future = waitForVmServiceEvent(
        events: controller.stream,
        matches: isFlutterFrameEvent,
        timeout: const Duration(seconds: 1),
      );

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
      controller.add({
        'method': 'streamNotify',
        'params': {
          'streamId': 'Extension',
          'event': {
            'kind': 'Extension',
            'extensionKind': 'Flutter.Frame',
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
  });
}
