import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import 'package:fdb/controller/controller_request.dart';
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
