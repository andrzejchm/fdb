import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';

class ReloadCommandRequest extends ControllerRequest {
  const ReloadCommandRequest({required super.token});
  factory ReloadCommandRequest.fromJson(Map<String, Object?> json) =>
      ReloadCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.reload;

  @override
  CommandRunner createRunner(ControllerContext controller) => ReloadCommandRunner(controller);
}

class ReloadCommandRunner implements CommandRunner {
  const ReloadCommandRunner(this.controller);

  final ControllerContext controller;

  @override
  Future<CommandResponse> execute(ControllerRequest request) {
    return _restart(fullRestart: false);
  }

  Future<CommandResponse> _restart({required bool fullRestart}) async {
    final result = await controller.sendFlutterRequest('app.restart', {
      'appId': controller.requireAppId(),
      'fullRestart': fullRestart,
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
