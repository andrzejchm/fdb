import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbCleanCommandRunner extends VmServiceCommand<FdbCleanCommandRequest> {
  const FdbCleanCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbCleanCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.clean',
      params: {'isolateId': request.isolateId},
    );
    return FdbCleanCommandResponse.fromResponse(response);
  }
}
