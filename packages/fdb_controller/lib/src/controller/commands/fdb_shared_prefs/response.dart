import 'package:fdb_controller/src/controller/vm_service/deserialise.dart';
import 'package:fdb_controller/src/controller/commands/shared/vm_service_response.dart';

class FdbSharedPrefsCommandResponse extends VmServiceCommandResponse {
  const FdbSharedPrefsCommandResponse({
    required this.error,
    required this.exists,
    required this.value,
    required this.values,
  });

  factory FdbSharedPrefsCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbSharedPrefsCommandResponse(
      error: result?['error'] as String?,
      exists: result?['exists'] as bool?,
      value: result?['value'],
      values: result?['values'] as Map<String, dynamic>?,
    );
  }

  @override
  final String? error;
  final bool? exists;
  final Object? value;
  final Map<String, dynamic>? values;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'error': error,
        'exists': exists,
        'value': value,
        'values': values,
      };
}
