import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';

abstract class CommandRunner {
  Future<CommandResponse> execute(ControllerRequest request);
}
