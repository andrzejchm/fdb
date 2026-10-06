/// Whether a selector gesture (tap, long-press, double-tap) that failed with
/// [error] may succeed if retried before `--timeout`: the widget is not there
/// yet, is covered (a dialog closing, a sheet animating), or is disabled
/// until the app enables it (a send button waiting for the draft to update).
///
/// With [waitForMatch] false, a missing match is final. `fdb tap @N` uses that:
/// a widget that left its described position will not come back to it.
bool isRetryableGestureError(String error, {bool waitForMatch = true}) =>
    (waitForMatch && (error.contains('not found') || error.contains('No hittable element'))) ||
    error.contains(' is not hittable: ') ||
    error.endsWith(' is disabled');
