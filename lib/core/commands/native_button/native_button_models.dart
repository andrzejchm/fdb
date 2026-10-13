import 'package:fdb/core/models/command_result.dart';

typedef NativeButtonInput = ({String button});

sealed class NativeButtonResult extends CommandResult {
  const NativeButtonResult();
}

class NativeButtonSuccess extends NativeButtonResult {
  const NativeButtonSuccess(this.platform, this.button);
  final String platform;
  final String button;
}

class NativeButtonError extends NativeButtonResult {
  const NativeButtonError(this.message);
  final String message;
}
