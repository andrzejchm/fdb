import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';

class KillCommandRequest extends ControllerRequest {
  const KillCommandRequest({required super.token});
  factory KillCommandRequest.fromJson(Map<String, Object?> json) =>
      KillCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.kill;

  @override
  CommandRunner createRunner(ControllerContext controller) => KillCommandRunner(controller);
}

class KillCommandRunner implements CommandRunner {
  const KillCommandRunner(this.controller);

  final ControllerContext controller;

  @override
  Future<CommandResponse> execute(ControllerRequest request) async {
    controller.requestStop();
    final result = await controller.sendFlutterRequest(
      'app.stop',
      {'appId': controller.requireAppId()},
    );
    if (result['result'] == true) {
      return ControllerResponse.success({'stopped': true});
    }
    return ControllerResponse.failure('Flutter app did not stop.');
  }
}
