import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'package:fdb_controller/src/controller/controller_response.dart';
import 'package:fdb_controller/src/process_utils.dart';

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
