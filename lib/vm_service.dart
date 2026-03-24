import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/process_utils.dart';

/// Sends a JSON-RPC request to the Flutter VM service over websocket.
/// Returns the parsed JSON response.
/// Throws on connection failure or timeout.
Future<Map<String, dynamic>> vmServiceCall(
  String method, {
  Map<String, dynamic> params = const {},
  Duration timeout = const Duration(seconds: 30),
}) async {
  final uri = readVmUri();
  if (uri == null || uri.isEmpty) {
    throw StateError('VM service URI not found. Is the app running?');
  }

  final wsUri = uri
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://');

  final ws = await WebSocket.connect(
    wsUri,
    customClient: HttpClient()..maxConnectionsPerHost = 1,
  );

  // Widget trees can be 500KB+, no built-in buffer size limit on dart:io WebSocket
  // but we need to handle large responses properly.

  final completer = Completer<Map<String, dynamic>>();
  final requestId = DateTime.now().microsecondsSinceEpoch.toString();

  final request = jsonEncode({
    'jsonrpc': '2.0',
    'id': requestId,
    'method': method,
    'params': params,
  });

  ws.listen(
    (data) {
      final response = jsonDecode(data as String) as Map<String, dynamic>;
      if (response['id'] == requestId && !completer.isCompleted) {
        completer.complete(response);
      }
    },
    onError: (Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(StateError('WebSocket closed before response'));
      }
    },
  );

  ws.add(request);

  try {
    final response = await completer.future.timeout(timeout);
    await ws.close();
    return response;
  } on TimeoutException {
    await ws.close();
    rethrow;
  }
}

/// Finds the first isolate with a valid response from the VM service.
Future<String?> findMainIsolateId() async {
  final vmResponse = await vmServiceCall('getVM');
  final result = vmResponse['result'] as Map<String, dynamic>?;
  if (result == null) return null;

  final isolates = result['isolates'] as List<dynamic>?;
  if (isolates == null || isolates.isEmpty) return null;

  for (final isolate in isolates) {
    final id = (isolate as Map<String, dynamic>)['id'] as String?;
    if (id != null) return id;
  }
  return null;
}
