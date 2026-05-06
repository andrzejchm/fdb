package io.fdb.fdb_helper

/// Safe release stub.
///
/// The real implementation depends on in-process input injection and must not
/// ship in production Android binaries. Profile builds keep the real
/// implementation via Flutter's `matchingFallbacks` (debug → release).
class FdbHelperNativeTapImpl(
    @Suppress("UNUSED_PARAMETER") activityProvider: () -> android.app.Activity?,
) : NativeTapApi {
    override fun nativeTap(x: Double, y: Double) {
        throw FlutterError(
            "UNAVAILABLE_IN_RELEASE",
            "Native tap is disabled in release builds of fdb_helper",
            null,
        )
    }
}
