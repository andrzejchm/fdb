import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/commands/shared/vm_service_response.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbElementsCommandRequest extends IsolateIdCommandRequest {
  const FdbElementsCommandRequest({required super.token, required super.isolateId});
  factory FdbElementsCommandRequest.fromJson(Map<String, Object?> json) => FdbElementsCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbElements;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbElementsCommandRunner();
}

class FdbElementsCommandResponse extends VmServiceCommandResponse {
  const FdbElementsCommandResponse({required this.error});

  factory FdbElementsCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbElementsCommandResponse(error: result?['error'] as String?);
  }

  @override
  final String? error;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'error': error};
}

class FdbElementsCommandRunner extends VmServiceCommand<FdbElementsCommandRequest> {
  const FdbElementsCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbElementsCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.elements',
      params: {'isolateId': request.isolateId},
      timeout: const Duration(seconds: 3),
    );
    return FdbElementsCommandResponse.fromResponse(response);
  }
}
