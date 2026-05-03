import 'package:fdb/controller/command_runner.dart';
import 'package:fdb/controller/controller_command.dart';
import 'package:fdb/controller/controller_context.dart';
import 'package:fdb/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbElementsCommandRequest extends IsolateIdCommandRequest {
  const FdbElementsCommandRequest({required super.token, required super.isolateId});
  factory FdbElementsCommandRequest.fromJson(Map<String, Object?> json) => FdbElementsCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbElements;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbElementsCommandRunner();
}
