import 'package:fdb/controller/command_response.dart';
import 'request.dart';
import 'response.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FdbDoubleTapCommandRunner extends VmServiceCommand<FdbDoubleTapCommandRequest> {
  const FdbDoubleTapCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbDoubleTapCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.doubleTap',
      params: request.toVmParams(),
    );
    return FdbDoubleTapCommandResponse.fromResponse(response);
  }
}
