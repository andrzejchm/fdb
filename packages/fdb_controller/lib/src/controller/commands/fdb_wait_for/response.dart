import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/fdb_action_response.dart';

class FdbWaitForCommandResponse extends FdbActionCommandResponse {
  const FdbWaitForCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
  });

  factory FdbWaitForCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbWaitForCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      unexpected: result ?? response,
    );
  }
}
