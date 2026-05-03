import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class GetIsolateCommandRunner extends VmServiceCommand<GetIsolateCommandRequest> {
  const GetIsolateCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(GetIsolateCommandRequest request) async {
    final response = await callVmServiceMethod(
      'getIsolate',
      params: {'isolateId': request.isolateId},
    );
    return VmIsolateCommandResponse.fromResponse(response);
  }
}
