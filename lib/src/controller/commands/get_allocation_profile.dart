import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class GetAllocationProfileCommandRequest extends IsolateIdCommandRequest {
  const GetAllocationProfileCommandRequest({
    required super.token,
    required super.isolateId,
    this.gc,
    this.reset,
  });
  factory GetAllocationProfileCommandRequest.fromJson(Map<String, Object?> json) => GetAllocationProfileCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        gc: ControllerJson.optionalBool(json, 'gc'),
        reset: ControllerJson.optionalBool(json, 'reset'),
      );

  final bool? gc;
  final bool? reset;

  @override
  ControllerCommand get command => ControllerCommand.getAllocationProfile;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (gc != null) 'gc': gc,
        if (reset != null) 'reset': reset,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const GetAllocationProfileCommandRunner();
}

class VmAllocationProfileCommandResponse extends VmServiceCommandResponse {
  const VmAllocationProfileCommandResponse({
    required this.members,
  });

  factory VmAllocationProfileCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = (response['result'] as Map<String, dynamic>?) ?? response;
    return VmAllocationProfileCommandResponse(
      members: result['members'] as List<dynamic>?,
    );
  }

  final List<dynamic>? members;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'members': members};
}

class GetAllocationProfileCommandRunner extends VmServiceCommand<GetAllocationProfileCommandRequest> {
  const GetAllocationProfileCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(GetAllocationProfileCommandRequest request) async {
    final params = <String, dynamic>{'isolateId': request.isolateId};
    if (request.gc != null) params['gc'] = request.gc;
    if (request.reset != null) params['reset'] = request.reset;
    final response = await callVmServiceMethod(
      'getAllocationProfile',
      params: params,
    );
    return VmAllocationProfileCommandResponse.fromResponse(response);
  }
}
