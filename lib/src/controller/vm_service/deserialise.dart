import 'dart:convert';

import 'package:fdb/src/controller/commands/shared/fdb_widget_action_response.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

typedef WidgetResultFactory<T extends FdbWidgetActionCommandResponse> = T Function({
  required String? status,
  required String? error,
  required Object? unexpected,
  required String? widgetType,
  required Object? x,
  required Object? y,
  required String? warning,
});

Map<String, dynamic>? extensionResultAsMap(Map<String, dynamic> response) {
  if (_isRpcEnvelope(response)) {
    return legacyExtensionEnvelopeResult(response);
  }
  return _withoutVmProtocolFields(response);
}

T widgetActionResult<T extends FdbWidgetActionCommandResponse>(
  Map<String, dynamic> response,
  WidgetResultFactory<T> create,
) {
  final result = extensionResultAsMap(response);
  return create(
    status: result?['status'] as String?,
    error: result?['error'] as String?,
    widgetType: result?['widgetType'] as String?,
    x: result?['x'],
    y: result?['y'],
    warning: result?['warning'] as String?,
    unexpected: result ?? response,
  );
}

Map<String, dynamic> vmServiceResponseAsMap(vm_service.Response response) {
  return _withoutVmProtocolFields(response.toJson()) ?? <String, dynamic>{};
}

Map<String, dynamic> vmServiceRpcErrorAsMap(vm_service.RPCError error) {
  final errorMap = error.toMap();
  final details = _errorDetails(errorMap);
  final decoded = _decodeJsonObject(details);
  return {
    if (decoded != null) ...decoded,
    if (decoded == null && details != null) 'error': details,
    'errorCode': errorMap['code'],
    'errorMessage': errorMap['message'],
    'errorDetails': details,
  };
}

/// Unwraps a legacy JSON-RPC service extension response.
/// Shape: {"result": {"type": "_extensionType", "method": "...", ...actual fields...}}
///
/// Also handles older error envelopes from ServiceExtensionResponse.error(),
/// which arrived as:
/// {"error": {"code": -32000, "message": "Server error",
///            "data": {"details": "{\"error\": \"actual message\"}"}}}
/// The actual error detail is in error['data']['details'] as a JSON-encoded string
/// (double-encoded, so the details value must itself be JSON-decoded).
Map<String, dynamic>? legacyExtensionEnvelopeResult(
  Map<String, dynamic> response,
) {
  final error = response['error'] as Map<String, dynamic>?;
  if (error != null) {
    final data = error['data'];
    if (data is Map<String, dynamic>) {
      // ServiceExtensionResponse.error() puts the detail in data['details']
      // as a JSON-encoded string, e.g. "{\"error\": \"actual message\"}"
      final details = data['details'];
      if (details is String) {
        try {
          final decoded = jsonDecode(details);
          if (decoded is Map<String, dynamic>) return decoded;
          return {'error': details};
        } catch (_) {
          return {'error': details};
        }
      }
      // details absent or wrong type — fall through to generic message below
    } else if (data is String) {
      // Fallback: data itself is a JSON-encoded string
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'error': data};
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

/// Unwraps a Flutter inspector extension response.
/// Inspector extensions return a nested JSON string in the `result` field.
/// Legacy JSON-RPC envelopes are accepted for controller response compatibility.
///
/// Extension responses have the shape: `{"result": "<json string>", "type": "_extensionType"}`
/// The inner "result" is a JSON-encoded string that needs to be decoded.
Map<String, dynamic>? unwrapExtensionResult(Map<String, dynamic> response) {
  final outer = _isRpcEnvelope(response) ? response['result'] as Map<String, dynamic>? : response;
  if (outer == null) return null;

  final inner = outer['result'];
  if (inner == null) return null;
  if (inner is String) {
    try {
      final decoded = jsonDecode(inner);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
  return inner is Map<String, dynamic> ? inner : null;
}

bool _isRpcEnvelope(Map<String, dynamic> response) {
  return response.containsKey('result') && response['result'] is Map ||
      response.containsKey('error') && response['error'] is Map;
}

Map<String, dynamic>? _withoutVmProtocolFields(Map<String, dynamic>? value) {
  if (value == null) return null;
  final copy = Map<String, dynamic>.from(value);
  copy.remove('type');
  copy.remove('method');
  return copy;
}

String? _errorDetails(Map<String, dynamic> error) {
  final data = error['data'];
  if (data is Map<String, dynamic>) {
    return data['details'] as String?;
  }
  return data is String ? data : null;
}

Map<String, dynamic>? _decodeJsonObject(String? details) {
  if (details == null) return null;
  try {
    final decoded = jsonDecode(details);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
