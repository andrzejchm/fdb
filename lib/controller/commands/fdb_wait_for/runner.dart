import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbWaitForCommandRunner extends VmServiceCommand<FdbWaitForCommandRequest> {
  const FdbWaitForCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbWaitForCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.waitFor',
      params: Map<String, dynamic>.from(request.toVmStringParams()),
      timeout: Duration(milliseconds: request.timeoutMilliseconds),
    );
    return FdbWaitForCommandResponse.fromResponse(response);
  }
}
