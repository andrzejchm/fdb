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

  final wsUri =
      uri.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

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

/// Returns all isolate IDs from the VM service.
Future<List<String>> findAllIsolateIds() async {
  final vmResponse = await vmServiceCall('getVM');
  final result = vmResponse['result'] as Map<String, dynamic>?;
  if (result == null) return [];

  final isolates = result['isolates'] as List<dynamic>?;
  if (isolates == null || isolates.isEmpty) return [];

  return isolates
      .map((i) => (i as Map<String, dynamic>)['id'] as String?)
      .where((id) => id != null)
      .cast<String>()
      .toList();
}

/// Finds the Flutter UI isolate by trying each isolate until one returns
/// a non-null widget tree. Returns the isolate ID or null.
Future<String?> findFlutterIsolateId() async {
  final ids = await findAllIsolateIds();
  for (final id in ids) {
    try {
      final response = await vmServiceCall(
        'ext.flutter.inspector.isWidgetTreeReady',
        params: {'isolateId': id},
        timeout: const Duration(seconds: 5),
      );
      final result = response['result'] as Map<String, dynamic>?;
      if (result != null && response['error'] == null) return id;
    } catch (_) {
      // This isolate doesn't have Flutter inspector, try next
    }
  }
  // Fallback: return last isolate (often the UI one)
  return ids.isNotEmpty ? ids.last : null;
}

/// Unwraps the VM service extension response.
/// Extension responses have the shape: {"result": {"result": "<json string>", "type": "_extensionType"}}
/// The inner "result" is a JSON-encoded string that needs to be decoded.
dynamic unwrapExtensionResult(Map<String, dynamic> response) {
  final outer = response['result'] as Map<String, dynamic>?;
  if (outer == null) return null;

  final inner = outer['result'];
  if (inner == null) return null;
  if (inner is String) {
    try {
      return jsonDecode(inner);
    } catch (_) {
      return inner;
    }
  }
  return inner;
}

/// Unwraps a raw service extension response (from dart:developer.registerExtension).
/// These are NOT double-encoded like Flutter inspector extensions.
/// Shape: {"result": {"type": "_extensionType", "method": "...", ...actual fields...}}
///
/// Also handles error responses from ServiceExtensionResponse.error(),
/// which arrive as:
/// {"error": {"code": -32000, "message": "Server error",
///            "data": {"details": "{\"error\": \"actual message\"}"}}}
/// The actual error detail is in error['data']['details'] as a JSON-encoded string.
dynamic unwrapRawExtensionResult(Map<String, dynamic> response) {
  // Check for error response first
  final error = response['error'] as Map<String, dynamic>?;
  if (error != null) {
    final data = error['data'];
    if (data is Map) {
      // ServiceExtensionResponse.error() puts the detail in data['details']
      // as a JSON-encoded string, e.g. "{\"error\": \"actual message\"}"
      final details = data['details'];
      if (details is String) {
        try {
          return jsonDecode(details);
        } catch (_) {
          return {'error': details};
        }
      }
    }
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return {'error': data};
      }
    }
    final message = error['message'] as String?;
    return {'error': message ?? 'Unknown error'};
  }

  final result = response['result'] as Map<String, dynamic>?;
  if (result == null) return null;
  // Remove protocol fields, return the rest
  final copy = Map<String, dynamic>.from(result);
  copy.remove('type');
  copy.remove('method');
  return copy;
}

/// Checks if fdb_helper extensions are registered in the running app.
///
/// Returns the Flutter isolate ID if fdb_helper is available, or null if not.
/// Callers can reuse the returned isolate ID to avoid a second round-trip.
Future<String?> checkFdbHelper() async {
  try {
    final isolateId = await findFlutterIsolateId();
    if (isolateId == null) return null;
    await vmServiceCall(
      'ext.fdb.elements',
      params: {'isolateId': isolateId},
      timeout: const Duration(seconds: 3),
    );
    return isolateId;
  } catch (_) {
    return null;
  }
}
