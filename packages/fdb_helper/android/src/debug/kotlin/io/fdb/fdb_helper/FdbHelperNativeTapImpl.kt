package io.fdb.fdb_helper

import android.app.Activity
import android.os.SystemClock
import android.view.MotionEvent

/// Injects a synthetic in-process touch at the given Flutter logical coordinates.
///
/// Uses Activity.dispatchTouchEvent() which routes through the full View hierarchy,
/// reaching native Android Views (WebViews, platform views, AlertDialogs presented
/// by the app) that Flutter's GestureBinding cannot reach.
class FdbHelperNativeTapImpl(
    private val activityProvider: () -> Activity?,
) : NativeTapApi {
    override fun nativeTap(x: Double, y: Double) {
        val activity = activityProvider()
            ?: throw FlutterError("NO_ACTIVITY", "No Activity available for native tap", null)

        // Flutter logical coordinates → physical pixels for MotionEvent.
        val density = activity.resources.displayMetrics.density
        val px = (x * density).toFloat()
        val py = (y * density).toFloat()

        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, px, py, 0)
        val up = MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, px, py, 0)

            // Block until the UI thread finishes so the Pigeon response is sent
        // only after the tap has actually been dispatched.
        val latch = java.util.concurrent.CountDownLatch(1)
        activity.runOnUiThread {
            try {
                activity.dispatchTouchEvent(down)
                activity.dispatchTouchEvent(up)
            } finally {
                down.recycle()
                up.recycle()
                latch.countDown()
            }
        }
        if (!latch.await(2, java.util.concurrent.TimeUnit.SECONDS)) {
            throw FlutterError(
                "DISPATCH_TIMEOUT",
                "UI thread did not dispatch the synthetic touch within 2s",
                null,
            )
        }
    }

    override fun nativeLongPress(x: Double, y: Double, durationMs: Long) {
        val activity = activityProvider()
            ?: throw FlutterError("NO_ACTIVITY", "No Activity available for native long-press", null)

        val density = activity.resources.displayMetrics.density
        val px = (x * density).toFloat()
        val py = (y * density).toFloat()

        // downTime is fixed; eventTime advances so the OS sees the touch held for durationMs.
        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, px, py, 0)

        // Block until the UI thread finishes dispatching the full DOWN → (wait) → UP sequence.
        val latch = java.util.concurrent.CountDownLatch(1)
        activity.runOnUiThread {
            try {
                activity.dispatchTouchEvent(down)
                down.recycle()

                // Hold the touch for durationMs so LongPressGestureDetector fires.
                // Sleeping the UI thread is safe here because we are inside a blocking
                // runOnUiThread call that holds the Pigeon reply latch — the Flutter
                // isolate is waiting on the platform-channel reply, not on the UI thread.
                Thread.sleep(durationMs)

                val upTime = SystemClock.uptimeMillis()
                val up = MotionEvent.obtain(downTime, upTime, MotionEvent.ACTION_UP, px, py, 0)
                try {
                    activity.dispatchTouchEvent(up)
                } finally {
                    up.recycle()
                }
            } finally {
                latch.countDown()
            }
        }
        // Allow up to durationMs + 3s for the UI thread to finish.
        val timeoutSeconds = (durationMs / 1000L) + 3L
        if (!latch.await(timeoutSeconds, java.util.concurrent.TimeUnit.SECONDS)) {
            throw FlutterError(
                "DISPATCH_TIMEOUT",
                "UI thread did not dispatch the native long-press within ${timeoutSeconds}s",
                null,
            )
        }
    }
}
