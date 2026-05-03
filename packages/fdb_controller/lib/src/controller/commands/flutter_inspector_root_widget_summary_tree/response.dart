import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class FlutterInspectorTreeCommandResponse extends VmServiceCommandResponse {
  const FlutterInspectorTreeCommandResponse({required this.tree});

  factory FlutterInspectorTreeCommandResponse.fromResponse(Map<String, dynamic> response) {
    final tree = response['tree'];
    if (tree is Map<String, dynamic>) {
      return FlutterInspectorTreeCommandResponse(tree: tree);
    }
    final result = unwrapExtensionResult(response);
    return FlutterInspectorTreeCommandResponse(
      tree: result ?? _directTree(response['result']) ?? _directTree(response),
    );
  }

  final Map<String, dynamic>? tree;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'tree': tree,
      };
}

Map<String, dynamic>? _directTree(Object? value) {
  if (value is Map<String, dynamic> && value['description'] is String && value['children'] is List) {
    return value;
  }
  return null;
}
