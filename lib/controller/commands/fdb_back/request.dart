import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbBackCommandRequest extends IsolateIdCommandRequest {
  const FdbBackCommandRequest({required super.token, required super.isolateId});
  factory FdbBackCommandRequest.fromJson(Map<String, Object?> json) => FdbBackCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbBack;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbBackCommandRunner();
}
