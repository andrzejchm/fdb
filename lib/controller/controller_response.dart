import 'dart:convert';
import 'package:fdb/controller/command_response.dart';

class ControllerResponse implements CommandResponse {
  const ControllerResponse._({
    required this.ok,
    Map<String, Object?> fields = const {},
    this.error,
    this.appDied = false,
    this.reason,
    this.logLines = const [],
  }) : _fields = fields;

  factory ControllerResponse.fromJsonLine(String line) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    return ControllerResponse.fromJson(json);
  }

  factory ControllerResponse.fromJson(Map<String, dynamic> json) {
    return ControllerResponse._(
      ok: json['ok'] == true,
      fields: (json['result'] as Map?)?.cast<String, Object?>() ?? const {},
      error: json['error'] as String?,
      appDied: json['appDied'] == true,
      reason: json['reason'] as String?,
      logLines: (json['logLines'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  factory ControllerResponse.success(Map<String, Object?> fields) {
    return ControllerResponse._(
      ok: true,
      fields: fields,
    );
  }

  factory ControllerResponse.failure(String message) {
    return ControllerResponse._(ok: false, error: message);
  }

  factory ControllerResponse.appDied({
    required List<String> logLines,
    String? reason,
  }) {
    return ControllerResponse._(
      ok: false,
      appDied: true,
      reason: reason,
      logLines: logLines,
    );
  }

  @override
  final bool ok;
  final Map<String, Object?> _fields;
  @override
  final String? error;
  @override
  final bool appDied;
  @override
  final String? reason;
  @override
  final List<String> logLines;

  @override
  Object? field(String name) => _fields[name];

  @override
  Map<String, Object?> toJson() => {
        'ok': ok,
        if (_fields.isNotEmpty) 'result': _fields,
        if (error != null) 'error': error,
        if (appDied) 'appDied': true,
        if (reason != null) 'reason': reason,
        if (logLines.isNotEmpty) 'logLines': logLines,
      };
}
