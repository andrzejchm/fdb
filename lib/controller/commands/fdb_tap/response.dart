import 'package:fdb/controller/commands/shared/fdb_widget_action_response.dart';
import 'package:fdb/controller/vm_service/deserialise.dart';

class FdbTapCommandResponse extends FdbWidgetActionCommandResponse {
  const FdbTapCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required super.widgetType,
    required super.x,
    required super.y,
    required super.warning,
  });

  factory FdbTapCommandResponse.fromResponse(Map<String, dynamic> response) =>
      widgetActionResult(response, FdbTapCommandResponse.new);
}
