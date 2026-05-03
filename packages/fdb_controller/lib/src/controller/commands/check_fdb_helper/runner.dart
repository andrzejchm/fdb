import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'package:fdb_controller/src/controller/controller_response.dart';
import 'request.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import 'package:fdb_controller/src/app_died_exception.dart';
import '../shared/runner.dart';

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
