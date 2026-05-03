import 'package:fdb/controller/commands/shared/vm_service_response.dart';

class FdbActionCommandResponse extends VmServiceCommandResponse {
  const FdbActionCommandResponse({
    required this.status,
    required this.error,
    required this.unexpected,
  });

  final String? status;
  @override
  final String? error;
  final Object? unexpected;

  bool get isSuccess => status == 'Success';

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'status': status,
        'error': error,
        'unexpected': unexpected,
      };
}
