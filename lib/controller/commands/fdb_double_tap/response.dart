import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/vm_service/vm_service.dart';

class FdbDoubleTapCommandResponse extends FdbWidgetActionCommandResponse {
  const FdbDoubleTapCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required super.widgetType,
    required super.x,
    required super.y,
    required super.warning,
  });

  factory FdbDoubleTapCommandResponse.fromResponse(Map<String, dynamic> response) =>
      widgetActionResult(response, FdbDoubleTapCommandResponse.new);
}
