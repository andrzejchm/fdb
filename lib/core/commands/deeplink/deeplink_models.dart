import 'package:fdb/core/models/command_result.dart';

/// Input parameters for [openDeeplink].
typedef DeeplinkInput = ({String url});

/// Result of a [openDeeplink] invocation.
sealed class DeeplinkResult extends CommandResult {
  const DeeplinkResult();
}

/// The deep link was opened successfully.
class DeeplinkOpened extends DeeplinkResult {
  final String url;

  /// Present when the URL uses https:// on an iOS simulator (Universal Link warning).
  final String? warning;
  const DeeplinkOpened({required this.url, this.warning});
}

/// No active fdb session was found.
class DeeplinkNoSession extends DeeplinkResult {
  const DeeplinkNoSession();
}

/// The device platform does not support deep links via fdb.
class DeeplinkUnsupportedPlatform extends DeeplinkResult {
  const DeeplinkUnsupportedPlatform();
}

/// The deep link open command failed.
class DeeplinkFailed extends DeeplinkResult {
  final String details;
  const DeeplinkFailed(this.details);
}
