import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';

class RestartCommandRequest extends ControllerRequest {
  const RestartCommandRequest({required super.token});
  factory RestartCommandRequest.fromJson(Map<String, Object?> json) =>
      RestartCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.restart;

  @override
  CommandRunner createRunner(ControllerContext controller) => RestartCommandRunner(controller);
}

class RestartCommandRunner implements CommandRunner {
  const RestartCommandRunner(this.controller);

  final ControllerContext controller;

  @override
  Future<CommandResponse> execute(ControllerRequest request) async {
    final result = await controller.sendFlutterRequest('app.restart', {
      'appId': controller.requireAppId(),
      'fullRestart': true,
      'pause': false,
      'reason': 'fdb',
    });
    final payload = result['result'] as Map<String, dynamic>?;
    final message = payload?['message'] as String? ?? '';
    if (payload?['code'] == 0) {
      return ControllerResponse.success({'message': message, 'result': payload});
    }
    return ControllerResponse.failure(message);
  }
}
