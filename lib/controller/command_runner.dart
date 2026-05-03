import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/controller_request.dart';

abstract class CommandRunner {
  Future<CommandResponse> execute(ControllerRequest request);
}
