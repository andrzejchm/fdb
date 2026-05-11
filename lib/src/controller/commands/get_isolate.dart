import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class GetIsolateCommandRequest extends IsolateIdCommandRequest {
  const GetIsolateCommandRequest({required super.token, required super.isolateId});
  factory GetIsolateCommandRequest.fromJson(Map<String, Object?> json) => GetIsolateCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.getIsolate;

  @override
  CommandRunner createRunner(ControllerContext controller) => const GetIsolateCommandRunner();
}

class VmIsolateCommandResponse extends VmServiceCommandResponse {
  const VmIsolateCommandResponse({
    required this.name,
    required this.extensionRPCs,
  });

  factory VmIsolateCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = (response['result'] as Map<String, dynamic>?) ?? response;
    return VmIsolateCommandResponse(
      name: result['name'] as String?,
      extensionRPCs: (result['extensionRPCs'] as List<dynamic>?)?.whereType<String>().toList() ?? const [],
    );
  }

  final String? name;
  final List<String> extensionRPCs;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'name': name,
        'extensionRPCs': extensionRPCs,
      };
}

class GetIsolateCommandRunner extends VmServiceCommand<GetIsolateCommandRequest> {
  const GetIsolateCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(GetIsolateCommandRequest request) async {
    final response = await callVmServiceMethod(
      'getIsolate',
      params: {'isolateId': request.isolateId},
    );
    return VmIsolateCommandResponse.fromResponse(response);
  }
}
