import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class GetMemoryUsageCommandRunner extends VmServiceCommand<GetMemoryUsageCommandRequest> {
  const GetMemoryUsageCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(GetMemoryUsageCommandRequest request) async {
    final response = await callVmServiceMethod(
      'getMemoryUsage',
      params: {'isolateId': request.isolateId},
    );
    return VmMemoryUsageCommandResponse.fromResponse(response);
  }
}
