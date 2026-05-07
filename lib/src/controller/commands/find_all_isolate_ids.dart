import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FindAllIsolateIdsCommandRequest extends ControllerRequest {
  const FindAllIsolateIdsCommandRequest({required super.token});
  factory FindAllIsolateIdsCommandRequest.fromJson(Map<String, Object?> json) =>
      FindAllIsolateIdsCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.findAllIsolateIds;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FindAllIsolateIdsCommandRunner();
}

class FindAllIsolateIdsCommandRunner extends VmServiceCommand<FindAllIsolateIdsCommandRequest> {
  const FindAllIsolateIdsCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FindAllIsolateIdsCommandRequest request) async {
    final vm = await getVm();
    return ControllerResponse.success({'isolates': vm?.isolates ?? const <String>[]});
  }
}
