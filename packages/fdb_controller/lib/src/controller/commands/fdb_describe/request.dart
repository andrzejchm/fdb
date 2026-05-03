import 'package:fdb_controller/src/controller/commands/command_runner.dart';
import 'package:fdb_controller/src/controller/controller_command.dart';
import 'package:fdb_controller/src/controller/controller_context.dart';
import 'package:fdb_controller/src/controller/controller_json.dart';
import '../shared/request.dart';
import 'runner.dart';

class FdbDescribeCommandRequest extends IsolateIdCommandRequest {
  const FdbDescribeCommandRequest({required super.token, required super.isolateId});
  factory FdbDescribeCommandRequest.fromJson(Map<String, Object?> json) => FdbDescribeCommandRequest(
      token: ControllerJson.token(json), isolateId: ControllerJson.requiredString(json, 'isolateId'));
  @override
  ControllerCommand get command => ControllerCommand.fdbDescribe;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbDescribeCommandRunner();
}
