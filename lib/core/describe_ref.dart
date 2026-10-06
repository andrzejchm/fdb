/// Error for an `@N` request that reached an fdb_helper without describe refs.
const helperTooOldForRefs =
    'fdb_helper in the app is too old for @N refs. Update fdb_helper to the version of fdb and rebuild the app.';

/// [error] from fdb_helper for a request with describe ref [ref], or
/// [helperTooOldForRefs] when the helper did not understand the `ref` param.
///
/// An fdb_helper without refs finds no selector in `{ref: N}` and rejects
/// the request, so nothing was tapped or typed.
String refAwareError(String error, int? ref) =>
    ref != null && error.contains('params must contain at least one of') ? helperTooOldForRefs : error;
