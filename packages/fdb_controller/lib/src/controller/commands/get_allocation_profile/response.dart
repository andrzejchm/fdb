import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class VmAllocationProfileCommandResponse extends VmServiceCommandResponse {
  const VmAllocationProfileCommandResponse({
    required this.members,
  });

  factory VmAllocationProfileCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = (response['result'] as Map<String, dynamic>?) ?? response;
    return VmAllocationProfileCommandResponse(
      members: result['members'] as List<dynamic>?,
    );
  }

  final List<dynamic>? members;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'members': members};
}
