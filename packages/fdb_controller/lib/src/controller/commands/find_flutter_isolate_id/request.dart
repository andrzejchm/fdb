import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import 'package:fdb_controller/src/controller/controller_request.dart';
import 'runner.dart';

class FindFlutterIsolateIdCommandRequest extends ControllerRequest {
  const FindFlutterIsolateIdCommandRequest({required super.token});
  factory FindFlutterIsolateIdCommandRequest.fromJson(Map<String, Object?> json) =>
      FindFlutterIsolateIdCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.findFlutterIsolateId;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FindFlutterIsolateIdCommandRunner();
}
