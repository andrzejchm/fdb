import 'package:fdb_controller/src/controller/commands/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb_controller/src/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class GetAllocationProfileCommandRunner extends VmServiceCommand<GetAllocationProfileCommandRequest> {
  const GetAllocationProfileCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(GetAllocationProfileCommandRequest request) async {
    final params = <String, dynamic>{'isolateId': request.isolateId};
    if (request.gc != null) params['gc'] = request.gc;
    if (request.reset != null) params['reset'] = request.reset;
    final response = await callVmServiceMethod(
      'getAllocationProfile',
      params: params,
    );
    return VmAllocationProfileCommandResponse.fromResponse(response);
  }
}
