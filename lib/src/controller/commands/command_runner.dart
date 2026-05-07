import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/controller_request.dart';

abstract class CommandRunner {
  Future<CommandResponse> execute(ControllerRequest request);
}
