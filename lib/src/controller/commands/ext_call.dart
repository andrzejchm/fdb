import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class ExtCallCommandRequest extends ControllerRequest {
  const ExtCallCommandRequest({
    required super.token,
    required this.method,
    this.extensionParams = const {},
  });
  factory ExtCallCommandRequest.fromJson(Map<String, Object?> json) => ExtCallCommandRequest(
        token: ControllerJson.token(json),
        method: ControllerJson.requiredString(json, 'method'),
        extensionParams: ControllerJson.map(json, 'params'),
      );

  final String method;
  final Map<String, dynamic> extensionParams;

  @override
  ControllerCommand get command => ControllerCommand.extCall;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'method': method,
        'params': extensionParams,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const ExtCallCommandRunner();
}

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

class ExtCallCommandRunner extends VmServiceCommand<ExtCallCommandRequest> {
  const ExtCallCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(ExtCallCommandRequest request) async {
    final response = await callVmServiceMethod(
      request.method,
      params: request.extensionParams,
    );
    return VmServiceExtensionCallCommandResponse.fromResponse(response);
  }
}
