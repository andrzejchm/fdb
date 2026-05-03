import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

class FindAllIsolateIdsCommandRequest extends ControllerRequest {
  const FindAllIsolateIdsCommandRequest({required super.token});
  factory FindAllIsolateIdsCommandRequest.fromJson(Map<String, Object?> json) =>
      FindAllIsolateIdsCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.findAllIsolateIds;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FindAllIsolateIdsCommandRunner();
}
