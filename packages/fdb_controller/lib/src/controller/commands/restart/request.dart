import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

class RestartCommandRequest extends ControllerRequest {
  const RestartCommandRequest({required super.token});
  factory RestartCommandRequest.fromJson(Map<String, Object?> json) =>
      RestartCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.restart;

  @override
  CommandRunner createRunner(ControllerContext controller) => RestartCommandRunner(controller);
}
