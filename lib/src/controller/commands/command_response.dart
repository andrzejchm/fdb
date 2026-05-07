abstract class CommandResponse {
  bool get ok;

  String? get error;

  bool get appDied;

  String? get reason;

  List<String> get logLines;

  Object? field(String name);

  Map<String, Object?> toJson();
}
