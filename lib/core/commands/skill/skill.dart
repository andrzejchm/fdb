import 'dart:io';
import 'dart:isolate';

import 'package:fdb/core/commands/skill/skill_models.dart';

export 'package:fdb/core/commands/skill/skill_models.dart';

/// Resolves and reads the bundled SKILL.md from the package root.
///
/// The authoritative skill content lives at `lib/skill/SKILL.md` (internal,
/// bundled with the CLI). This is intentionally separate from
/// `skills/using-fdb/SKILL.md`, which is the lean shim users install into
/// their OpenCode config — it simply instructs the agent to run `fdb skill`.
///
/// Package-root resolution strategy:
///   This file lives at `lib/core/commands/skill/skill.dart`.
///   The package URI `package:fdb/core/commands/skill/skill.dart` resolves to the
///   absolute file path. Walking `.parent` five times reaches the package root:
///     skill.dart → skill/ → commands/ → core/ → lib/ → package-root
///   (Compare: the old file in lib/core/commands/ only needed four `.parent` calls.)
///
///   If the URI resolver returns null (unusual but possible), we fall back to
///   `Platform.script` which points to `bin/fdb.dart`; one `.parent` up is
///   `bin/`, and one more is the package root.
Future<SkillResult> resolveSkill() async {
  const relativePath = 'lib/skill/SKILL.md';

  // Primary: resolve via package URI — works for both `dart run` and
  // `dart pub global activate` installs.
  final packageUri = Uri.parse('package:fdb/core/commands/skill/skill.dart');
  final resolved = await Isolate.resolvePackageUri(packageUri);
  if (resolved != null) {
    // Five .parent calls: skill.dart → skill/ → commands/ → core/ → lib/ → package root
    final packageRoot = File.fromUri(resolved).parent.parent.parent.parent.parent;
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
