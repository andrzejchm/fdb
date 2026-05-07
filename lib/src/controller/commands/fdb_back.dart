import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/fdb_action_response.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbBackCommandRequest extends IsolateIdCommandRequest {
  const FdbBackCommandRequest({required super.token, required super.isolateId});
  factory FdbBackCommandRequest.fromJson(Map<String, Object?> json) => FdbBackCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbBack;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbBackCommandRunner();
}

class FdbBackCommandResponse extends FdbActionCommandResponse {
  const FdbBackCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.popped,
  });

  factory FdbBackCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbBackCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      popped: result?['popped'] as bool?,
      unexpected: result ?? response,
    );
  }

  final bool? popped;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'popped': popped,
      };
}

class FdbBackCommandRunner extends VmServiceCommand<FdbBackCommandRequest> {
  const FdbBackCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbBackCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.back',
      params: {'isolateId': request.isolateId},
    );
    return FdbBackCommandResponse.fromResponse(response);
  }
}
