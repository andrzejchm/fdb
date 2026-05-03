import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/commands/shared/vm_service_response.dart';

class FdbDescribeCommandResponse extends VmServiceCommandResponse {
  const FdbDescribeCommandResponse({
    required this.error,
    required this.snapshot,
    required this.unexpected,
  });

  factory FdbDescribeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final snapshot = response['snapshot'];
    if (response.containsKey('snapshot')) {
      return FdbDescribeCommandResponse(
        error: response['error'] as String?,
        snapshot: snapshot is Map<String, dynamic> ? snapshot : null,
        unexpected: response['unexpected'],
      );
    }
    final result = extensionResultAsMap(response);
    return FdbDescribeCommandResponse(
      error: result?['error'] as String?,
      snapshot: result,
      unexpected: result ?? response,
    );
  }

  @override
  final String? error;
  final Map<String, dynamic>? snapshot;
  final Object? unexpected;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'error': error,
        'snapshot': snapshot,
        'unexpected': unexpected,
      };
}
