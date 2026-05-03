import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class FlutterInspectorTreeReadyCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorTreeReadyCommandResponse(this.ready);

  factory FlutterInspectorTreeReadyCommandResponse.fromResponse(
    Map<String, dynamic> response,
  ) {
    if (response.containsKey('ready')) {
      return FlutterInspectorTreeReadyCommandResponse(response['ready'] == true);
    }
    return FlutterInspectorTreeReadyCommandResponse(
      response['error'] == null && response['errorCode'] == null && response['errorMessage'] == null,
    );
  }

  final bool ready;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'ready': ready};
}
