// fdb_helper — native UIKit tap injection helper.
//
// Implementation lives in ObjC because the surrounding code uses many
// private UIKit / IOKit APIs whose C signatures (struct-by-value,
// 17-argument digitizer event creation, runtime ivar manipulation) cannot
// be expressed cleanly through Swift's @convention(c) + dlsym path.
//
// The approach mirrors KIF v3.12.2 (kif-framework/KIF), which is the only
// in-process iOS UI testing library known to work on iOS 26 as of mid-2026
// (see KIF PR #1334). On iOS 26 UIKit enforces stricter validation that
// the UIEvent's IOHIDEvent snapshot matches the current UITouch phase —
// reusing a single UIEvent across phases (Began → Ended) silently drops
// the event for non-UIControl responders. Each phase therefore needs a
// freshly-built UIEvent with a freshly-created IOHIDEvent attached.
//
// Private API usage is intentional: fdb_helper is a dev-only debug
// tool and is never included in App Store / release builds.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Synthesises a single tap (Began → Ended) at the given window-coordinate
/// [point] by constructing a private UITouch, attaching an IOHIDEvent, and
/// dispatching it through `-[UIApplication sendEvent:]`.
///
/// Returns `YES` on success. Returns `NO` if any required private selector
/// is unavailable on this iOS version, with [error] populated. Must be
/// called on the main thread.
BOOL FdbHelperNativeTapAtPoint(CGPoint point, NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
