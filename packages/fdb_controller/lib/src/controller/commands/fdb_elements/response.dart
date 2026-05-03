import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class FdbElementsCommandResponse extends VmServiceCommandResponse {
  const FdbElementsCommandResponse({required this.error});

  factory FdbElementsCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbElementsCommandResponse(error: result?['error'] as String?);
  }

  @override
  final String? error;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'error': error};
}
