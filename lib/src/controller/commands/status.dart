import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/process_utils.dart';

class StatusCommandRequest extends ControllerRequest {
  const StatusCommandRequest({required super.token});
  factory StatusCommandRequest.fromJson(Map<String, Object?> json) =>
      StatusCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.status;

  @override
  CommandRunner createRunner(ControllerContext controller) => StatusCommandRunner(controller);
}

class StatusCommandRunner implements CommandRunner {
  const StatusCommandRunner(this.controller);

  final ControllerContext controller;

  @override
  Future<CommandResponse> execute(ControllerRequest request) async {
    return ControllerResponse.success({
      'running': controller.running,
      'pid': readAppPid() ?? readPid(),
      'vmServiceUri': controller.vmServiceUri,
    });
  }
}
