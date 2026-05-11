import 'package:fdb/src/controller/commands/shared/fdb_action_response.dart';

class FdbWidgetActionCommandResponse extends FdbActionCommandResponse {
  const FdbWidgetActionCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.widgetType,
    required this.x,
    required this.y,
    required this.warning,
  });

  final String? widgetType;
  final Object? x;
  final Object? y;
  final String? warning;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widgetType': widgetType,
        'x': x,
        'y': y,
        'warning': warning,
      };
}
