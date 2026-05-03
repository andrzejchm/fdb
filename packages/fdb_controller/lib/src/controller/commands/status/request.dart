import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

class StatusCommandRequest extends ControllerRequest {
  const StatusCommandRequest({required super.token});
  factory StatusCommandRequest.fromJson(Map<String, Object?> json) =>
      StatusCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.status;

  @override
  CommandRunner createRunner(ControllerContext controller) => StatusCommandRunner(controller);
}
