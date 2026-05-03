import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/controller_response.dart';
import 'request.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import 'package:fdb/core/app_died_exception.dart';
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
