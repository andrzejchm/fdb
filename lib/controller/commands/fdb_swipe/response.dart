import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/commands/shared/fdb_action_response.dart';

class FdbSwipeCommandResponse extends FdbActionCommandResponse {
  const FdbSwipeCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.distance,
  });

  factory FdbSwipeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbSwipeCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      distance: result?['distance'],
      unexpected: result ?? response,
    );
  }

  final Object? distance;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'distance': distance,
      };
}
