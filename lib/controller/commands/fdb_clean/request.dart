import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbCleanCommandRequest extends IsolateIdCommandRequest {
  const FdbCleanCommandRequest({required super.token, required super.isolateId});
  factory FdbCleanCommandRequest.fromJson(Map<String, Object?> json) => FdbCleanCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbClean;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbCleanCommandRunner();
}
