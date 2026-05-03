import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_request.dart';
import 'package:fdb/controller/controller_response.dart';

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
