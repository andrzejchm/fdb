import 'package:fdb/controller/command_response.dart';

abstract class VmServiceCommandResponse implements CommandResponse {
  const VmServiceCommandResponse();

  @override
  bool get ok => true;

  @override
  String? get error => null;

  @override
  bool get appDied => false;

  @override
  String? get reason => null;

  @override
  List<String> get logLines => const [];

  @override
  Object? field(String name) => toJson()[name];

  @override
  Map<String, Object?> toJson() => {
        'ok': true,
      };
}
