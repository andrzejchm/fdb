import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

class CheckFdbHelperCommandRequest extends ControllerRequest {
  const CheckFdbHelperCommandRequest({required super.token});
  factory CheckFdbHelperCommandRequest.fromJson(Map<String, Object?> json) =>
      CheckFdbHelperCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.checkFdbHelper;

  @override
  CommandRunner createRunner(ControllerContext controller) => const CheckFdbHelperCommandRunner();
}
