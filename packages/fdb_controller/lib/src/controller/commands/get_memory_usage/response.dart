import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class VmMemoryUsageCommandResponse extends VmServiceCommandResponse {
  const VmMemoryUsageCommandResponse({
    required this.heapUsage,
    required this.externalUsage,
    required this.heapCapacity,
  });

  factory VmMemoryUsageCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = (response['result'] as Map<String, dynamic>?) ?? response;
    return VmMemoryUsageCommandResponse(
      heapUsage: (result['heapUsage'] as num?)?.toInt(),
      externalUsage: (result['externalUsage'] as num?)?.toInt(),
      heapCapacity: (result['heapCapacity'] as num?)?.toInt(),
    );
  }

  final int? heapUsage;
  final int? externalUsage;
  final int? heapCapacity;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'heapUsage': heapUsage,
        'externalUsage': externalUsage,
        'heapCapacity': heapCapacity,
      };
}
