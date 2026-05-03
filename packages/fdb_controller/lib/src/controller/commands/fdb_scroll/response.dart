import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/fdb_action_response.dart';

class FdbScrollCommandResponse extends FdbActionCommandResponse {
  const FdbScrollCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
  });

  factory FdbScrollCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbScrollCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      unexpected: result ?? response,
    );
  }
}
