import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/process_utils.dart';

typedef VmEventMatcher = bool Function(Map<String, dynamic> event);

bool isFlutterFrameEvent(Map<String, dynamic> event) {
  return _isFlutterExtensionEvent(event, 'Flutter.Frame');
}

bool isFlutterFirstFrameEvent(Map<String, dynamic> event) {
  return _isFlutterExtensionEvent(event, 'Flutter.FirstFrame');
}

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
  final ws = await WebSocket.connect(
    wsUri,
    customClient: HttpClient()..maxConnectionsPerHost = 1,
  );
  final events = StreamController<Map<String, dynamic>>();
  final listenCompleters = <String, Completer<void>>{};
  var nextId = 0;

  final wsSubscription = ws.listen(
    (data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final id = message['id'] as String?;
      final listenCompleter = id != null ? listenCompleters[id] : null;
      if (listenCompleter != null) {
        listenCompleters.remove(id);
        if (!listenCompleter.isCompleted) {
          listenCompleter.complete();
        }
        return;
      }

      if (message['method'] == 'streamNotify') {
        events.add(message);
      }
    },
    onError: events.addError,
    onDone: events.close,
  );

  try {
    for (final streamId in streamIds) {
      final requestId = 'listen_${++nextId}_$streamId';
      final completer = Completer<void>();
      listenCompleters[requestId] = completer;
      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'streamListen',
          'params': {'streamId': streamId},
        }),
      );
    }

    await Future.wait(listenCompleters.values.map((completer) => completer.future)).timeout(
      const Duration(seconds: 3),
    );

    signal();
    return await waitForVmServiceEvent(
      events: events.stream,
      matches: matches,
      timeout: timeout,
    );
  } finally {
    await wsSubscription.cancel();
    await events.close();
    await ws.close();
  }
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
