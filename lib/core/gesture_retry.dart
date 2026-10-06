/// Whether a selector gesture (tap, long-press, double-tap) that failed with
/// [error] may succeed if retried before `--timeout`: the widget is not there
/// yet, is covered (a dialog closing, a sheet animating), or is disabled
/// until the app enables it (a send button waiting for the draft to update).
///
/// A stale or not-built `@N` ref is final: its error matches none of these.
bool isRetryableGestureError(String error) =>
    error.contains('not found') ||
    error.contains('No hittable element') ||
    error.contains(' is not hittable: ') ||
    error.endsWith(' is disabled');
