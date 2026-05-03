import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_request.dart';
import 'package:fdb/controller/controller_response.dart';

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
