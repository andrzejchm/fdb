import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_request.dart';
import 'package:fdb/controller/controller_response.dart';
import 'package:fdb/core/process_utils.dart';

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
