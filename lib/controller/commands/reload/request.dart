import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import 'package:fdb/controller/controller_request.dart';
import 'runner.dart';

class ReloadCommandRequest extends ControllerRequest {
  const ReloadCommandRequest({required super.token});
  factory ReloadCommandRequest.fromJson(Map<String, Object?> json) =>
      ReloadCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.reload;

  @override
  CommandRunner createRunner(ControllerContext controller) => ReloadCommandRunner(controller);
}
