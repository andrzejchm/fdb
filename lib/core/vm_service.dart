import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/controller_client.dart';
import 'package:fdb/core/process_utils.dart';

/// Sends a JSON-RPC request to the Flutter VM service over websocket.
/// Returns the parsed JSON response.
/// Throws [AppDiedException] when the app process is detected as dead,
/// or on connection failure / timeout.
Future<Map<String, dynamic>> vmServiceCall(
  String method, {
  Map<String, dynamic> params = const {},
  Duration timeout = const Duration(seconds: 30),
}) async {
  var recoveredOnce = false;

  while (true) {
    var uri = readVmUri();
    if (uri == null || uri.isEmpty) {
      uri = await _refreshVmUriFromController();
    }
    if (uri == null || uri.isEmpty) {
      throw StateError('VM service URI not found. Is the app running?');
    }

    // Pre-check: if the process is dead, short-circuit immediately without
    // even attempting a WebSocket connection.
    if (_isMacOsTarget()) {
      final pid = readAppPid() ?? readPid();
      if (pid != null && !isProcessAlive(pid)) {
        throw await buildAppDiedException(pid: pid);
      }
    }

    final wsUri = uri.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        wsUri,
        customClient: HttpClient()..maxConnectionsPerHost = 1,
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      if (_isMacOsTarget()) {
        final currentPid = readAppPid() ?? readPid();
        if (currentPid != null && !isProcessAlive(currentPid)) {
          throw await buildAppDiedException(pid: currentPid);
        }
      }
      if (!recoveredOnce) {
        final recovered = await _refreshVmUriFromController();
        if (recovered != null && recovered.isNotEmpty && recovered != uri) {
          recoveredOnce = true;
          continue;
        }
      }
      rethrow;
    } catch (e) {
      if (_isConnectionRefused(e)) {
        if (!recoveredOnce) {
          final recovered = await _refreshVmUriFromController();
          if (recovered != null && recovered.isNotEmpty && recovered != uri) {
            recoveredOnce = true;
            continue;
          }
        }
        if (isAndroidTarget()) {
          final appPid = readAppPid();
          if (appPid != null && isAndroidAppPidAlive(appPid)) {
            rethrow;
          }
        }
        final pid = _isMacOsTarget() ? (readAppPid() ?? readPid()) : readPid();
        throw await buildAppDiedException(pid: pid);
      }
      if (_isMacOsTarget()) {
        final currentPid = readAppPid() ?? readPid();
        if (currentPid != null && !isProcessAlive(currentPid)) {
          throw await buildAppDiedException(pid: currentPid);
        }
      }
      rethrow;
    }

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
          _buildDeadAppError().then((ex) {
            if (!completer.isCompleted) completer.completeError(ex);
          }).catchError((Object _) {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('WebSocket closed before response'),
              );
            }
          });
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
      if (_isMacOsTarget()) {
        final currentPid = readAppPid() ?? readPid();
        if (currentPid != null && !isProcessAlive(currentPid)) {
          throw await buildAppDiedException(pid: currentPid);
        }
      }
      rethrow;
    } on AppDiedException {
      try {
        await ws.close();
      } catch (_) {}
      rethrow;
    }
  }
}

Future<String?> _refreshVmUriFromController() async {
  try {
    final response = await sendControllerCommand(
      'refresh_vm_uri',
      timeout: const Duration(seconds: 5),
    );
    return response['vmServiceUri'] as String?;
  } on ControllerUnavailable {
    return null;
  }
}

/// Builds an [AppDiedException] after a mid-call connection drop.
/// Uses the app PID on a macOS target (host-visible); on Android/iOS the
/// app PID lives in the device namespace and is not host-visible, so the
/// flutter-tools PID is the only useful value.
Future<AppDiedException> _buildDeadAppError() async {
  if (isAndroidTarget()) {
    final appPid = readAppPid();
    if (appPid != null && isAndroidAppPidAlive(appPid)) {
      throw StateError(
        'VM service connection closed while Android app PID is still alive',
      );
    }
  }
  final pid = _isMacOsTarget() ? (readAppPid() ?? readPid()) : readPid();
  return buildAppDiedException(pid: pid);
}

/// Returns true when the *target* device for this session is macOS desktop.
///
/// `Platform.isMacOS` checks the HOST OS (always macOS in fdb's supported
/// configurations), not the target. Reading the platform from the session file
/// is required to distinguish a macOS target from an Android or iOS target
/// when fdb itself runs on macOS. Returns false if the platform file is
/// missing (no session) — callers should treat this conservatively.
bool _isMacOsTarget() {
  final info = readPlatformInfo();
  if (info == null) return false;
  final p = info.platform.toLowerCase();
  return p == 'darwin' || p == 'macos';
}

/// Returns true when [error] indicates the OS refused the TCP connection,
/// which is the reliable signal that the VM service is no longer running.
bool _isConnectionRefused(Object error) {
  if (error is SocketException) {
    // errno 61 = ECONNREFUSED on macOS/Linux
    final errno = error.osError?.errorCode;
    return errno == 61 || errno == 111;
  }
  return false;
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
    } on AppDiedException {
      rethrow;
    } catch (_) {
      // This isolate doesn't have Flutter inspector, try next
    }
  }
  // Fallback: return last isolate (often the UI one)
  return ids.isNotEmpty ? ids.last : null;
}

/// Unwraps the VM service extension response.
/// Extension responses have the shape: `{"result": {"result": "<json string>", "type": "_extensionType"}}`
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
/// Shape: {"result": {"type": "_extensionType", "method": "...", ...actual fields...}}
/// The success path is NOT double-encoded like Flutter inspector extensions.
///
/// Also handles error responses from ServiceExtensionResponse.error(),
/// which arrive as:
/// {"error": {"code": -32000, "message": "Server error",
///            "data": {"details": "{\"error\": \"actual message\"}"}}}
/// The actual error detail is in error['data']['details'] as a JSON-encoded string
/// (double-encoded — the details value must itself be JSON-decoded).
dynamic unwrapRawExtensionResult(Map<String, dynamic> response) {
  // Check for error response first
  final error = response['error'] as Map<String, dynamic>?;
  if (error != null) {
    final data = error['data'];
    if (data is Map<String, dynamic>) {
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
      // details absent or wrong type — fall through to generic message below
    } else if (data is String) {
      // Fallback: data itself is a JSON-encoded string
      try {
        return jsonDecode(data);
      } catch (_) {
        return {'error': data};
      }
    }
    // No usable detail found; return the generic server error message
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
///
/// Re-throws [AppDiedException] so the caller can surface a structured error
/// instead of a misleading "fdb_helper not detected" message.
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
  } on AppDiedException {
    rethrow;
  } catch (_) {
    return null;
  }
}
