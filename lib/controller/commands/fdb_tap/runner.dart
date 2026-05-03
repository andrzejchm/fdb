import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbTapCommandRunner extends VmServiceCommand<FdbTapCommandRequest> {
  const FdbTapCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbTapCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.tap',
      params: request.toVmParams(),
    );
    return FdbTapCommandResponse.fromResponse(response);
  }
}
