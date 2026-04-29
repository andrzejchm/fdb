import 'dart:io';

import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/skill.dart';

/// CLI adapter for `fdb skill`. Prints the SKILL.md contents to stdout.
///
/// Output contract:
///   SKILL.md found  → stdout: full file contents (no trailing newline added),
///                     exit 0
///   SKILL.md missing → stderr: ERROR: SKILL.md not found, exit 1
Future<int> runSkillCli(List<String> args) => runSimpleCliAdapter(
      args,
      _execute,
      helpText: 'Usage: fdb skill\n\nPrints the AI agent skill file (SKILL.md) to stdout.',
    );

Future<int> _execute(List<String> _) async {
  final result = await resolveSkill();
  return _format(result);
}

int _format(SkillResult result) {
  switch (result) {
    case SkillContent(:final content):
      // Use write (not writeln) to preserve exact byte output from the file.
      stdout.write(content);
      return 0;
    case SkillNotFound():
      stderr.writeln('ERROR: SKILL.md not found');
      return 1;
  }
}
