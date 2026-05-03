import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class GetMemoryUsageCommandRequest extends IsolateIdCommandRequest {
  const GetMemoryUsageCommandRequest({required super.token, required super.isolateId});
  factory GetMemoryUsageCommandRequest.fromJson(Map<String, Object?> json) => GetMemoryUsageCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.getMemoryUsage;

  @override
  CommandRunner createRunner(ControllerContext controller) => const GetMemoryUsageCommandRunner();
}
