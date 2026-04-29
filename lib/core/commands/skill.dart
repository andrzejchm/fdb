import 'dart:io';
import 'dart:isolate';

import 'package:fdb/core/models/command_result.dart';

sealed class SkillResult extends CommandResult {
  const SkillResult();
}

class SkillContent extends SkillResult {
  final String content;
  const SkillContent(this.content);
}

class SkillNotFound extends SkillResult {
  const SkillNotFound();
}

/// Resolves and reads the using-fdb SKILL.md from the package root.
///
/// Package-root resolution strategy:
///   This file lives at `lib/core/commands/skill.dart`.
///   The package URI `package:fdb/core/commands/skill.dart` resolves to the
///   absolute file path. Walking `.parent` four times reaches the package root:
///     skill.dart → commands/ → core/ → lib/ → package-root
///   (Compare: the old file in lib/commands/ only needed three `.parent` calls.)
///
///   If the URI resolver returns null (unusual but possible), we fall back to
///   `Platform.script` which points to `bin/fdb.dart`; one `.parent` up is
///   `bin/`, and one more is the package root.
Future<SkillResult> resolveSkill() async {
  const relativePath = 'skills/using-fdb/SKILL.md';

  // Primary: resolve via package URI — works for both `dart run` and
  // `dart pub global activate` installs.
  final packageUri = Uri.parse('package:fdb/core/commands/skill.dart');
  final resolved = await Isolate.resolvePackageUri(packageUri);
  if (resolved != null) {
    // Four .parent calls: skill.dart → commands/ → core/ → lib/ → package root
    final packageRoot = File.fromUri(resolved).parent.parent.parent.parent;
    final candidate = File('${packageRoot.path}/$relativePath');
    if (candidate.existsSync()) {
      return SkillContent(candidate.readAsStringSync());
    }
  }

  // Fallback: resolve relative to Platform.script (`bin/fdb.dart`).
  // scriptDir = bin/, scriptDir.parent = package root.
  final scriptDir = Directory.fromUri(Platform.script).parent;
  final packageRoot = scriptDir.parent;
  final fallback = File('${packageRoot.path}/$relativePath');
  if (fallback.existsSync()) {
    return SkillContent(fallback.readAsStringSync());
  }

  return const SkillNotFound();
}
