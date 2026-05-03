import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/fdb_action_response.dart';

class FdbScrollToCommandResponse extends FdbActionCommandResponse {
  const FdbScrollToCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.widgetType,
    required this.x,
    required this.y,
  });

  factory FdbScrollToCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbScrollToCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      widgetType: result?['widgetType'] as String?,
      x: (result?['x'] as num?)?.toDouble(),
      y: (result?['y'] as num?)?.toDouble(),
      unexpected: result ?? response,
    );
  }

  final String? widgetType;
  final double? x;
  final double? y;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widgetType': widgetType,
        'x': x,
        'y': y,
      };
}
