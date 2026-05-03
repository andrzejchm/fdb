import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbBackCommandRunner extends VmServiceCommand<FdbBackCommandRequest> {
  const FdbBackCommandRunner() : super(_execute);

  static Future<CommandResponse> _execute(FdbBackCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.back',
      params: {'isolateId': request.isolateId},
    );
    return FdbBackCommandResponse.fromResponse(response);
  }
}
