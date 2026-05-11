import 'dart:async';

import 'package:fdb/src/controller/process_utils.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

typedef VmEventMatcher = bool Function(Map<String, dynamic> event);

/// Returns true when the VM event reports a post-reload Flutter frame.
bool isFlutterFrameEvent(Map<String, dynamic> event) {
  return _isFlutterExtensionEvent(event, 'Flutter.Frame');
}

/// Returns true when the VM event reports a service extension state change.
///
/// This event fires reliably on iOS simulators after a hot reload even when
/// `Flutter.Frame` is not emitted (e.g., when 0 libraries are reloaded).
bool isFlutterServiceExtensionStateChangedEvent(Map<String, dynamic> event) {
  return _isFlutterExtensionEvent(event, 'Flutter.ServiceExtensionStateChanged');
}

/// Returns true when the VM event signals that a hot reload has completed.
///
/// Matches either a `Flutter.Frame` event (reliable on Android/desktop) or a
/// `Flutter.ServiceExtensionStateChanged` event (reliable on iOS simulators
/// where `Flutter.Frame` is not emitted when 0 libraries are reloaded).
bool isReloadCompletionEvent(Map<String, dynamic> event) {
  return isFlutterFrameEvent(event) || isFlutterServiceExtensionStateChangedEvent(event);
}

/// Returns true when the VM event reports the first frame after restart.
bool isFlutterFirstFrameEvent(Map<String, dynamic> event) {
  return _isFlutterExtensionEvent(event, 'Flutter.FirstFrame');
}

/// Returns true when the VM event signals that an isolate became runnable.
///
/// `IsolateRunnable` fires on the `Isolate` stream after every hot restart
/// and is reliable on iOS simulators where `Flutter.FirstFrame` is not emitted.
bool isIsolateRunnableEvent(Map<String, dynamic> event) {
  if (event['method'] != 'streamNotify') return false;
  final params = event['params'];
  if (params is! Map<String, dynamic>) return false;
  if (params['streamId'] != 'Isolate') return false;
  final evt = params['event'];
  if (evt is! Map<String, dynamic>) return false;
  return evt['kind'] == 'IsolateRunnable';
}

/// Returns true when the VM event signals that a hot restart has completed.
///
/// Matches either a `Flutter.FirstFrame` extension event (reliable on Android)
/// or an `IsolateRunnable` isolate event (reliable on iOS simulators where
/// `Flutter.FirstFrame` is not emitted after restart).
bool isRestartCompletionEvent(Map<String, dynamic> event) {
  return isFlutterFirstFrameEvent(event) || isIsolateRunnableEvent(event);
}

/// Waits for the first VM event that satisfies [matches].
Future<bool> waitForVmServiceEvent({
  required Stream<Map<String, dynamic>> events,
  required VmEventMatcher matches,
  required Duration timeout,
}) async {
  final completer = Completer<bool>();
  late final StreamSubscription<Map<String, dynamic>> subscription;
  Timer? timer;

  void complete(bool value) {
    if (completer.isCompleted) return;
    completer.complete(value);
  }

  subscription = events.listen(
    (event) {
      if (matches(event)) {
        complete(true);
      }
    },
    onError: (_) => complete(false),
    onDone: () => complete(false),
  );

  timer = Timer(timeout, () => complete(false));

  try {
    return await completer.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}

/// Subscribes to VM service streams, sends [signal], then waits for a matching
/// event or timeout.
Future<bool> waitForVmEventAfterSignal({
  required List<String> streamIds,
  required VmEventMatcher matches,
  required void Function() signal,
  required Duration timeout,
}) async {
  final uri = readVmUri();
  if (uri == null || uri.isEmpty) {
    throw StateError('VM service URI not found. Is the app running?');
  }

  final wsUri = uri.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
  final vm_service.VmService service;
  try {
    service = await vm_service_io
        .vmServiceConnectUri(
          wsUri,
        )
        .timeout(const Duration(seconds: 3));
  } catch (error) {
    throw StateError('Failed to connect to VM service: $error');
  }
  final events = StreamController<Map<String, dynamic>>();
  final subscriptions = <StreamSubscription<vm_service.Event>>[];

  try {
    for (final streamId in streamIds) {
      subscriptions.add(
        service.onEvent(streamId).listen(
              (event) => events.add(_streamNotifyEvent(streamId, event)),
              onError: events.addError,
            ),
      );
      try {
        await service.streamListen(streamId).timeout(const Duration(seconds: 3));
      } on vm_service.RPCError catch (error) {
        throw StateError(
          'Failed to subscribe to VM stream $streamId: ${error.message}',
        );
      }
    }

    signal();
    return await waitForVmServiceEvent(
      events: events.stream,
      matches: matches,
      timeout: timeout,
    );
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel().timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
    }
    if (!events.isClosed) {
      await events.close();
    }
    await service.dispose().timeout(
          const Duration(seconds: 1),
          onTimeout: () {},
        );
  }
}

Map<String, dynamic> _streamNotifyEvent(
  String streamId,
  vm_service.Event event,
) {
  return {
    'method': 'streamNotify',
    'params': {
      'streamId': streamId,
      'event': event.toJson(),
    },
  };
}

bool _isFlutterExtensionEvent(Map<String, dynamic> message, String extensionKind) {
  if (message['method'] != 'streamNotify') return false;

  final params = message['params'];
  if (params is! Map<String, dynamic>) return false;
  if (params['streamId'] != 'Extension') return false;

  final event = params['event'];
  if (event is! Map<String, dynamic>) return false;
  return event['kind'] == 'Extension' && event['extensionKind'] == extensionKind;
}
