abstract final class ControllerJson {
  /// @Throwing(FormatException)
  static String token(Map<String, Object?> json) => requiredString(json, 'token');

  /// @Throwing(FormatException)
  static String requiredString(Map<String, Object?> json, String name) {
    final value = json[name];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Missing required controller field: $name');
  }

  static String? optionalString(Map<String, Object?> json, String name) {
    final value = json[name];
    if (value == null) return null;
    return value.toString();
  }

  /// @Throwing(FormatException)
  static int requiredInt(Map<String, Object?> json, String name) {
    final value = json[name];
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
    throw FormatException('Missing required integer controller field: $name');
  }

  /// @Throwing(FormatException)
  static bool requiredBool(Map<String, Object?> json, String name) {
    final value = optionalBool(json, name);
    if (value != null) return value;
    throw FormatException('Missing required boolean controller field: $name');
  }

  /// @Throwing(FormatException)
  static bool? optionalBool(Map<String, Object?> json, String name) {
    final value = json[name];
    if (value == null) return null;
    if (value is bool) return value;
    if (value == 'true') return true;
    if (value == 'false') return false;
    throw FormatException('Invalid boolean controller field: $name');
  }

  static Map<String, dynamic> map(Map<String, Object?> json, String name) {
    return (json[name] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  }
}
