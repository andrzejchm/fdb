import 'dart:io';

/// Prints the interacting-with-flutter-apps SKILL.md to stdout.
///
/// Resolves the file relative to the running script's package root.
Future<int> runSkill(List<String> args) async {
  final scriptUri = Platform.script;
  final scriptDir = Directory.fromUri(scriptUri).parent;
  final packageRoot = scriptDir.parent;
  final skillFile = File(
    '${packageRoot.path}/skills/interacting-with-flutter-apps/SKILL.md',
  );

  if (!skillFile.existsSync()) {
    stderr.writeln(
      'ERROR: SKILL.md not found at ${skillFile.path}',
    );
    return 1;
  }

  stdout.write(skillFile.readAsStringSync());
  return 0;
}
