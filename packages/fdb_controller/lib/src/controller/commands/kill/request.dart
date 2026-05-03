import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

class KillCommandRequest extends ControllerRequest {
  const KillCommandRequest({required super.token});
  factory KillCommandRequest.fromJson(Map<String, Object?> json) =>
      KillCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.kill;

  @override
  CommandRunner createRunner(ControllerContext controller) => KillCommandRunner(controller);
}
