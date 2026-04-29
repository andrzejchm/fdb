import 'package:fdb/core/models/command_result.dart';

// ── Input ─────────────────────────────────────────────────────────────────────

sealed class ScrollInput {
  const ScrollInput();
}

/// Direction-based scroll: `fdb scroll down [--at x,y] [--distance pixels]`.
class ScrollDirectionMode extends ScrollInput {
  /// One of `'up'`, `'down'`, `'left'`, `'right'`.
  final String direction;

  /// Raw `"x,y"` string passed through to the VM extension unchanged.
  final String? at;

  final int distance;

  const ScrollDirectionMode({
    required this.direction,
    this.at,
    this.distance = 200,
  });
}

/// Raw coordinate drag: `fdb scroll --from x,y --to x,y`.
class ScrollRawMode extends ScrollInput {
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;

  const ScrollRawMode({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });
}

// ── Result ────────────────────────────────────────────────────────────────────

sealed class ScrollResult extends CommandResult {
  const ScrollResult();
}

/// Direction scroll succeeded.
class ScrollDirectionSuccess extends ScrollResult {
  /// Uppercase direction: `UP`, `DOWN`, `LEFT`, `RIGHT`.
  final String direction;
  final int distance;

  const ScrollDirectionSuccess({required this.direction, required this.distance});
}

/// Raw coordinate drag succeeded.
class ScrollRawSuccess extends ScrollResult {
  final int fromX;
  final int fromY;
  final int toX;
  final int toY;

  const ScrollRawSuccess({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });
}

/// fdb_helper was not detected in the running app.
class ScrollNoFdbHelper extends ScrollResult {
  const ScrollNoFdbHelper();
}

/// The VM service returned an error message relayed from the extension.
class ScrollRelayedError extends ScrollResult {
  final String message;
  const ScrollRelayedError(this.message);
}

/// The VM service returned an unexpected response shape.
class ScrollUnexpectedResponse extends ScrollResult {
  final String raw;
  const ScrollUnexpectedResponse(this.raw);
}

/// The app process died while fdb was communicating with it.
class ScrollAppDied extends ScrollResult {
  final List<String> logLines;
  final String? reason;
  const ScrollAppDied({required this.logLines, this.reason});
}

/// Generic / unrecognised error.
class ScrollError extends ScrollResult {
  final String message;
  const ScrollError(this.message);
}
