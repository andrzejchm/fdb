import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class GetMemoryUsageCommandRequest extends IsolateIdCommandRequest {
  const GetMemoryUsageCommandRequest({required super.token, required super.isolateId});
  factory GetMemoryUsageCommandRequest.fromJson(Map<String, Object?> json) => GetMemoryUsageCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.getMemoryUsage;

  @override
  CommandRunner createRunner(ControllerContext controller) => const GetMemoryUsageCommandRunner();
}

class VmMemoryUsageCommandResponse extends VmServiceCommandResponse {
  const VmMemoryUsageCommandResponse({
    required this.heapUsage,
    required this.externalUsage,
    required this.heapCapacity,
  });

  factory VmMemoryUsageCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = (response['result'] as Map<String, dynamic>?) ?? response;
    return VmMemoryUsageCommandResponse(
      heapUsage: (result['heapUsage'] as num?)?.toInt(),
      externalUsage: (result['externalUsage'] as num?)?.toInt(),
      heapCapacity: (result['heapCapacity'] as num?)?.toInt(),
    );
  }

  final int? heapUsage;
  final int? externalUsage;
  final int? heapCapacity;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'heapUsage': heapUsage,
        'externalUsage': externalUsage,
        'heapCapacity': heapCapacity,
      };
}

class GetMemoryUsageCommandRunner extends VmServiceCommand<GetMemoryUsageCommandRequest> {
  const GetMemoryUsageCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(GetMemoryUsageCommandRequest request) async {
    final response = await callVmServiceMethod(
      'getMemoryUsage',
      params: {'isolateId': request.isolateId},
    );
    return VmMemoryUsageCommandResponse.fromResponse(response);
  }
}
