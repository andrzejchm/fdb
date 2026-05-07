import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';

class FindFlutterIsolateIdCommandRequest extends ControllerRequest {
  const FindFlutterIsolateIdCommandRequest({required super.token});
  factory FindFlutterIsolateIdCommandRequest.fromJson(Map<String, Object?> json) =>
      FindFlutterIsolateIdCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.findFlutterIsolateId;

  @override
  CommandRunner createRunner(ControllerContext controller) => const FindFlutterIsolateIdCommandRunner();
}

class FindFlutterIsolateIdCommandRunner extends VmServiceCommand<FindFlutterIsolateIdCommandRequest> {
  const FindFlutterIsolateIdCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FindFlutterIsolateIdCommandRequest request) async {
    final isolateId = await findFlutterIsolateIdForController();
    return ControllerResponse.success({'isolateId': isolateId});
  }
}
