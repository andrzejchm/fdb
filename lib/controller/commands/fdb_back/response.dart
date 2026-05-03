import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/commands/shared/fdb_action_response.dart';

class FdbBackCommandResponse extends FdbActionCommandResponse {
  const FdbBackCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.popped,
  });

  factory FdbBackCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbBackCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      popped: result?['popped'] as bool?,
      unexpected: result ?? response,
    );
  }

  final bool? popped;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'popped': popped,
      };
}
