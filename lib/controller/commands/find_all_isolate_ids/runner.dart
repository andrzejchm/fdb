import 'package:fdb/controller/command_response.dart';
import 'package:fdb/controller/controller_response.dart';
import 'request.dart';
import 'package:fdb/controller/vm_service/vm_service_impl.dart';
import '../shared/runner.dart';

class FindAllIsolateIdsCommandRunner extends VmServiceCommand<FindAllIsolateIdsCommandRequest> {
  const FindAllIsolateIdsCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FindAllIsolateIdsCommandRequest request) async {
    final vm = await getVm();
    return ControllerResponse.success({'isolates': vm?.isolates ?? const <String>[]});
  }
}
