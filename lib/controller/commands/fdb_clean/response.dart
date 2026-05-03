import 'package:fdb/controller/vm_service/deserialise.dart';
import 'package:fdb/controller/commands/shared/fdb_action_response.dart';

class FdbCleanCommandResponse extends FdbActionCommandResponse {
  const FdbCleanCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.dirs,
    required this.deletedEntries,
  });

  factory FdbCleanCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbCleanCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      dirs: (result?['dirs'] as List<dynamic>?)?.cast<String>() ?? const [],
      deletedEntries: result?['deletedEntries'] as int?,
      unexpected: result ?? response,
    );
  }

  final List<String> dirs;
  final int? deletedEntries;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'dirs': dirs,
        'deletedEntries': deletedEntries,
      };
}
