import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class GetIsolateCommandRequest extends IsolateIdCommandRequest {
  const GetIsolateCommandRequest({required super.token, required super.isolateId});
  factory GetIsolateCommandRequest.fromJson(Map<String, Object?> json) => GetIsolateCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.getIsolate;

  @override
  CommandRunner createRunner(ControllerContext controller) => const GetIsolateCommandRunner();
}
