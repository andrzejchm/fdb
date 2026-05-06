package io.fdb.fdb_helper

/// Safe release/profile stub.
///
/// The real implementation depends on debug-only in-process input injection and
/// must not ship in production Android binaries.
class FdbHelperNativeTapImpl(
    @Suppress("UNUSED_PARAMETER") activityProvider: () -> android.app.Activity?,
) : NativeTapApi {
    override fun nativeTap(x: Double, y: Double) {
        throw FlutterError(
            "UNAVAILABLE_IN_RELEASE",
            "Native tap is disabled in release/profile builds of fdb_helper",
            null,
        )
    }
}
