import 'package:fdb/controller/commands/shared/vm_service_response.dart';

class FlutterInspectorShowCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorShowCommandResponse({required this.error});

  factory FlutterInspectorShowCommandResponse.fromResponse(
    Map<String, dynamic> response,
  ) {
    if (response.containsKey('error') && response['error'] is String?) {
      return FlutterInspectorShowCommandResponse(error: response['error'] as String?);
    }
    final error = response['error'] as Map<String, dynamic>?;
    return FlutterInspectorShowCommandResponse(
      error: error?['message'] as String?,
    );
  }

  @override
  final String? error;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'error': error};
}
