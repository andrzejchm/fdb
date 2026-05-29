import 'dart:io';

import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/skill/skill.dart';

/// CLI adapter for `fdb skill [<topic>]`.
///
/// Without a topic, prints the core skill file (install, fdb_helper setup,
/// and the full command index with routing to sub-topics).
///
/// With a topic, prints the corresponding sub-document:
///   launch       — Devices, launch, doctor, reload, restart, status, kill, deeplink
///   interact     — Screenshot, describe, tap, input, scroll, swipe, tree, and more
///   data         — SharedPreferences, clean, ext, grant-permission
///   diagnostics  — Logs, syslog, crash-report, websocat fallback, debugging tips
///   memory       — Heap inspection, forced GC, heap snapshots
///   simulator    — iOS simulator: appearance, text-size, location, push, defaults
///
/// Output contract:
///   File found          → stdout: full file contents (no trailing newline added), exit 0
///   Core file missing   → stderr: ERROR: SKILL.md not found, exit 1
///   Unknown topic       → stderr: ERROR: Unknown skill topic: `topic`, exit 1
Future<int> runSkillCli(List<String> args) => runSimpleCliAdapter(
      args,
      _execute,
      helpText: '''Usage: fdb skill [<topic>]

Prints the AI agent skill documentation to stdout.

Without a topic, prints the core skill with install instructions, fdb_helper
setup, and the full command index. Use this first in any fdb session.

Available topics:
  launch       Devices, launch, doctor, reload, restart, status, kill, deeplink
  interact     Screenshot, describe, tap, input, scroll, swipe, tree, and more
  data         SharedPreferences, clean, ext (VM extensions), grant-permission
  diagnostics  Logs, syslog, crash-report, websocat fallback, debugging tips
  memory       Heap inspection, forced GC, heap snapshots
  simulator    iOS simulator: appearance, text-size, location, push, defaults

Examples:
  fdb skill               # core reference + command index
  fdb skill launch        # launch and session commands
  fdb skill interact      # UI interaction commands''',
    );

Future<int> _execute(List<String> args) async {
  final topic = args.isEmpty ? null : args.first;
  final result = await resolveSkill(topic: topic);
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
    case SkillTopicNotFound(:final topic):
      stderr.writeln('ERROR: Unknown skill topic: $topic');
      stderr.writeln('Available topics: launch, interact, data, diagnostics, memory, simulator');
      return 1;
  }
}
