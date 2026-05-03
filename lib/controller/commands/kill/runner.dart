import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_request.dart';
import 'package:fdb/controller/controller_response.dart';

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
