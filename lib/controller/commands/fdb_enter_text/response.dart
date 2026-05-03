import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/commands/shared/fdb_action_response.dart';

class FdbEnterTextCommandResponse extends FdbActionCommandResponse {
  const FdbEnterTextCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.widgetType,
  });

  factory FdbEnterTextCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbEnterTextCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      widgetType: result?['widgetType'] as String?,
      unexpected: result ?? response,
    );
  }

  final String? widgetType;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widgetType': widgetType,
      };
}
