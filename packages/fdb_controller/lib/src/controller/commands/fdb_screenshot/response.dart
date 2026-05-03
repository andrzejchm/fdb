import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class FdbScreenshotCommandResponse extends VmServiceCommandResponse {
  const FdbScreenshotCommandResponse({
    required this.error,
    required this.screenshot,
  });

  factory FdbScreenshotCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbScreenshotCommandResponse(
      error: result?['error'] as String?,
      screenshot: result?['screenshot'] as String?,
    );
  }

  @override
  final String? error;
  final String? screenshot;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'error': error,
        'screenshot': screenshot,
      };
}
