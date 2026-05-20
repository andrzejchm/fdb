import 'dart:io';

/// Resolve the flutter binary path for a project.
///
/// Priority:
/// 1. Explicit Flutter SDK path -> `path/bin/flutter`
/// 2. FVM auto-detect: `project/.fvm/flutter_sdk/bin/flutter`
/// 3. `flutter` from PATH
String resolveFlutterBinary(
  String projectPath, {
  String? explicitSdk,
  void Function(String)? onWarning,
}) {
  if (explicitSdk != null) {
    final bin = '$explicitSdk/bin/flutter';
    if (File(bin).existsSync()) return bin;
    onWarning?.call(
      'WARNING: --flutter-sdk path not found ($bin), falling back to PATH',
    );
  }

  // FVM stores a symlink at .fvm/flutter_sdk -> sdk-version.
  final fvmBin = '$projectPath/.fvm/flutter_sdk/bin/flutter';
  if (File(fvmBin).existsSync() || Link(fvmBin).existsSync()) {
    return fvmBin;
  }

  return 'flutter';
}
