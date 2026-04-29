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
