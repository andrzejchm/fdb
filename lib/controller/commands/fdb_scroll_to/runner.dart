import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbScrollToCommandRunner extends VmServiceCommand<FdbScrollToCommandRequest> {
  const FdbScrollToCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbScrollToCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.scrollTo',
      params: Map<String, dynamic>.from(request.toVmStringParams()),
    );
    return FdbScrollToCommandResponse.fromResponse(response);
  }
}
