import 'package:fdb/controller/commands/shared/vm_service_response.dart';

class VmIsolateCommandResponse extends VmServiceCommandResponse {
  const VmIsolateCommandResponse({
    required this.name,
    required this.extensionRPCs,
  });

  factory VmIsolateCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = (response['result'] as Map<String, dynamic>?) ?? response;
    return VmIsolateCommandResponse(
      name: result['name'] as String?,
      extensionRPCs: (result['extensionRPCs'] as List<dynamic>?)?.whereType<String>().toList() ?? const [],
    );
  }

  final String? name;
  final List<String> extensionRPCs;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'name': name,
        'extensionRPCs': extensionRPCs,
      };
}
