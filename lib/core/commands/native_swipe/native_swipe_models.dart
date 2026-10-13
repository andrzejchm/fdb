import 'package:fdb/core/models/command_result.dart';

typedef NativeSwipeInput = ({double fromX, double fromY, double toX, double toY, int durationMs});

sealed class NativeSwipeResult extends CommandResult {
  const NativeSwipeResult();
}

class NativeSwipeSuccess extends NativeSwipeResult {
  const NativeSwipeSuccess(this.platform, this.input);
  final String platform;
  final NativeSwipeInput input;
}

class NativeSwipeError extends NativeSwipeResult {
  const NativeSwipeError(this.message);
  final String message;
}
