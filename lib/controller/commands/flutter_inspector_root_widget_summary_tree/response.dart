import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/commands/shared/vm_service_response.dart';

class FlutterInspectorTreeCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorTreeCommandResponse({required this.tree});

  factory FlutterInspectorTreeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final tree = response['tree'];
    if (tree is Map<String, dynamic>) {
      return FlutterInspectorTreeCommandResponse(tree: tree);
    }
    final result = unwrapExtensionResult(response);
    return FlutterInspectorTreeCommandResponse(
      tree: result is Map<String, dynamic> ? result : null,
    );
  }

  final Map<String, dynamic>? tree;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'tree': tree,
      };
}
