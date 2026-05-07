import 'package:fdb/src/controller/app_died_exception.dart';
import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/controller_request.dart';
import 'package:fdb/src/controller/controller_response.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class CheckFdbHelperCommandRequest extends ControllerRequest {
  const CheckFdbHelperCommandRequest({required super.token});
  factory CheckFdbHelperCommandRequest.fromJson(Map<String, Object?> json) =>
      CheckFdbHelperCommandRequest(token: ControllerJson.token(json));
  @override
  ControllerCommand get command => ControllerCommand.checkFdbHelper;

  @override
  CommandRunner createRunner(ControllerContext controller) => const CheckFdbHelperCommandRunner();
}

class CheckFdbHelperCommandRunner extends VmServiceCommand<CheckFdbHelperCommandRequest> {
  const CheckFdbHelperCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(CheckFdbHelperCommandRequest request) async {
    try {
      final isolateId = await findFlutterIsolateIdForController();
      if (isolateId == null) {
        return ControllerResponse.success({'isolateId': null});
      }
      await callVmServiceMethod(
        'ext.fdb.elements',
        params: {'isolateId': isolateId},
        timeout: const Duration(seconds: 3),
      );
      return ControllerResponse.success({'isolateId': isolateId});
    } on AppDiedException {
      rethrow;
    } catch (_) {
      return ControllerResponse.success({'isolateId': null});
    }
  }
}
