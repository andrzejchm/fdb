import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class FlutterInspectorSelectedWidgetCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorSelectedWidgetCommandResponse({required this.widget});

  factory FlutterInspectorSelectedWidgetCommandResponse.fromResponse(
    Map<String, dynamic> response,
  ) {
    final widget = response['widget'];
    if (widget is Map<String, dynamic>) {
      return FlutterInspectorSelectedWidgetCommandResponse(widget: widget);
    }
    final result = unwrapExtensionResult(response);
    return FlutterInspectorSelectedWidgetCommandResponse(
      widget: result is Map<String, dynamic> ? result : null,
    );
  }

  final Map<String, dynamic>? widget;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widget': widget,
      };
}
