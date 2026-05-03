import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class VmServiceExtensionCallCommandResponse extends VmServiceCommandResponse {
  const VmServiceExtensionCallCommandResponse({
    required this.extensionResult,
    required this.errorCode,
    required this.errorMessage,
    required this.errorDetails,
  });

  factory VmServiceExtensionCallCommandResponse.fromResponse(Map<String, dynamic> response) {
    if (response.containsKey('errorCode') ||
        response.containsKey('errorMessage') ||
        response.containsKey('errorDetails')) {
      final result = Map<String, dynamic>.from(response)
        ..remove('error')
        ..remove('errorCode')
        ..remove('errorMessage')
        ..remove('errorDetails');
      return VmServiceExtensionCallCommandResponse(
        extensionResult: result.isEmpty ? null : result,
        errorCode: response['errorCode'] as int?,
        errorMessage: response['errorMessage'] as String?,
        errorDetails: response['errorDetails'] as String?,
      );
    }
    final error = response['error'] as Map<String, dynamic>?;
    final data = error?['data'];
    String? details;
    if (data is Map<String, dynamic>) {
      details = data['details'] as String?;
    }
    final result = response['result'] as Map<String, dynamic>? ?? response;
    final cleaned = Map<String, dynamic>.from(result)
      ..remove('type')
      ..remove('method');
    return VmServiceExtensionCallCommandResponse(
      extensionResult: cleaned.isEmpty ? null : cleaned,
      errorCode: error?['code'] as int?,
      errorMessage: error?['message'] as String?,
      errorDetails: details,
    );
  }

  final Map<String, dynamic>? extensionResult;
  final int? errorCode;
  final String? errorMessage;
  final String? errorDetails;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'result': extensionResult,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'errorDetails': errorDetails,
      };
}
