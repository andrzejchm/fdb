import 'dart:io';
import 'dart:isolate';

/// Prints the using-fdb SKILL.md to stdout.
///
/// Resolves the file relative to the package root. Handles both
/// `dart run bin/fdb.dart` and `dart pub global activate` installs
/// by resolving through the package URI.
Future<int> runSkill(List<String> args) async {
  const relativePath = 'skills/using-fdb/SKILL.md';

  // Resolve from the package URI — works for both local and global installs.
  // package:fdb/commands/skill.dart lives in lib/commands/, so ../../ is the
  // package root.
  final packageUri = Uri.parse('package:fdb/commands/skill.dart');
  final resolved = await Isolate.resolvePackageUri(packageUri);
  if (resolved != null) {
    final packageRoot = File.fromUri(resolved).parent.parent.parent;
    final candidate = File('${packageRoot.path}/$relativePath');
    if (candidate.existsSync()) {
      stdout.write(candidate.readAsStringSync());
      return 0;
    }
  }

  // Fallback: resolve relative to Platform.script (works for `dart run`).
  final scriptDir = Directory.fromUri(Platform.script).parent;
  final packageRoot = scriptDir.parent;
  final fallback = File('${packageRoot.path}/$relativePath');
  if (fallback.existsSync()) {
    stdout.write(fallback.readAsStringSync());
    return 0;
  }

  stderr.writeln('ERROR: SKILL.md not found');
  return 1;
}
