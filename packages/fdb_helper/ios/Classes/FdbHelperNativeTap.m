// See FdbHelperNativeTap.h for rationale.
//
// Closely mirrors KIF v3.12.2's tap injection (Sources/KIF/Additions/
// UIView-KIFAdditions.m + UITouch-KIFAdditions.m + UIEvent+KIFAdditions.m
// + IOHIDEvent+KIF.m). KIF is BSD-licensed; selectors and approach
// reproduced here are documented private UIKit/IOKit APIs.

#import "FdbHelperNativeTap.h"

#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - IOKit / IOHIDEvent declarations
//
// IOKit is not importable as a Swift module on iOS; even from ObjC we
// can't link against the full IOKit headers. We declare just the symbols
// we need, matching the signatures from IOKit's private headers.

typedef struct {
  uint32_t hi;
  uint32_t lo;
} FdbAbsoluteTime;

typedef double IOHIDFloat;
typedef uint32_t IOOptionBits;
typedef uint32_t IOHIDDigitizerTransducerType;
typedef uint32_t IOHIDEventField;

#define IOHIDEventFieldBase(type) ((type) << 16)

enum {
  kIOHIDDigitizerTransducerTypeStylus = 0,
  kIOHIDDigitizerTransducerTypePuck,
  kIOHIDDigitizerTransducerTypeFinger,
  kIOHIDDigitizerTransducerTypeHand
};

enum {
  kIOHIDEventTypeDigitizer = 11,
};

enum {
  kIOHIDDigitizerEventRange    = 0x00000001,
  kIOHIDDigitizerEventTouch    = 0x00000002,
  kIOHIDDigitizerEventPosition = 0x00000004,
};

enum {
  kIOHIDEventFieldDigitizerIsDisplayIntegrated =
      IOHIDEventFieldBase(kIOHIDEventTypeDigitizer) + 25,
};

// IOKit private function pointer types — resolved via dlsym at runtime.
typedef CFTypeRef (*FdbIOHIDEventCreateDigitizerEventFn)(
    CFAllocatorRef allocator, FdbAbsoluteTime timeStamp,
    IOHIDDigitizerTransducerType type, uint32_t index, uint32_t identity,
    uint32_t eventMask, uint32_t buttonMask, IOHIDFloat x, IOHIDFloat y,
    IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat barrelPressure,
    Boolean range, Boolean touch, IOOptionBits options);

typedef CFTypeRef (*FdbIOHIDEventCreateDigitizerFingerEventFn)(
    CFAllocatorRef allocator, FdbAbsoluteTime timeStamp, uint32_t index,
    uint32_t identity, uint32_t eventMask, IOHIDFloat x, IOHIDFloat y,
    IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat twist,
    IOHIDFloat minorRadius, IOHIDFloat majorRadius, IOHIDFloat quality,
    IOHIDFloat density, IOHIDFloat irregularity, Boolean range, Boolean touch,
    IOOptionBits options);

typedef void (*FdbIOHIDEventAppendEventFn)(
    CFTypeRef event, CFTypeRef childEvent);
typedef void (*FdbIOHIDEventSetIntegerValueFn)(
    CFTypeRef event, IOHIDEventField field, int value);

#pragma mark - Private UIKit selector declarations
//
// We declare these in a private interface so the compiler accepts the
// performSelector calls and direct invocations below.

@interface UIApplication (FdbPrivate)
- (UIEvent *)_touchesEvent;
@end

@interface UIEvent (FdbPrivate)
- (void)_clearTouches;
- (void)_setHIDEvent:(CFTypeRef)hidEvent;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
@end

@interface UITouch (FdbPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)touchPhase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)firstTouchForView;
- (void)_setHidEvent:(CFTypeRef)event;
@end

#pragma mark - Helpers

/// Returns the topmost visible UIWindow that contains [point], preferring
/// windows of presented view controllers (e.g. UIAlertController) which
/// are not always enumerated in the scene's window list.
static UIWindow *FdbTopmostWindowAtPoint(CGPoint point) {
  // Walk presented view controllers to find an alert/sheet window.
  UIWindowScene *keyScene = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      UIWindowScene *ws = (UIWindowScene *)scene;
      for (UIWindow *window in ws.windows) {
        if (window.isKeyWindow) {
          keyScene = ws;
          break;
        }
      }
      if (keyScene) break;
    }
  }

  if (keyScene) {
    UIWindow *keyWindow = nil;
    for (UIWindow *w in keyScene.windows) {
      if (w.isKeyWindow) { keyWindow = w; break; }
    }
    UIViewController *vc = keyWindow.rootViewController;
    while (vc.presentedViewController) {
      vc = vc.presentedViewController;
    }
    UIWindow *presentedWindow = vc.view.window;
    if (presentedWindow && !presentedWindow.hidden) {
      return presentedWindow;
    }

    // Fallback: highest-level visible window in the key scene.
    UIWindow *top = nil;
    for (UIWindow *w in keyScene.windows) {
      if (w.hidden || w.alpha == 0) continue;
      if (!top || w.windowLevel > top.windowLevel) top = w;
    }
    if (top) return top;
  }

  // Last resort: first window of any scene.
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
    UIWindowScene *ws = (UIWindowScene *)scene;
    if (ws.windows.firstObject) return ws.windows.firstObject;
  }
  return nil;
}

/// Builds an IOHIDEvent with one finger sub-event for [touch], matching
/// KIF's `kif_IOHIDEventWithTouches` exactly (single-finger variant).
/// Returns +1 retained CFTypeRef; caller is responsible for CFRelease.
static CFTypeRef FdbCreateHidEventForTouch(UITouch *touch) {
  static FdbIOHIDEventCreateDigitizerEventFn createDigitizer = NULL;
  static FdbIOHIDEventCreateDigitizerFingerEventFn createFinger = NULL;
  static FdbIOHIDEventAppendEventFn appendEvent = NULL;
  static FdbIOHIDEventSetIntegerValueFn setIntValue = NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    createDigitizer = (FdbIOHIDEventCreateDigitizerEventFn)dlsym(
        RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
    // KIF uses the "WithQuality" variant for the finger sub-event but the
    // shorter `IOHIDEventCreateDigitizerFingerEvent` is sufficient and is
    // what most other libraries use. Try the WithQuality form first since
    // KIF's working iOS 26 path uses it.
    createFinger = (FdbIOHIDEventCreateDigitizerFingerEventFn)dlsym(
        RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEventWithQuality");
    if (createFinger == NULL) {
      createFinger = (FdbIOHIDEventCreateDigitizerFingerEventFn)dlsym(
          RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
    }
    appendEvent = (FdbIOHIDEventAppendEventFn)dlsym(
        RTLD_DEFAULT, "IOHIDEventAppendEvent");
    setIntValue = (FdbIOHIDEventSetIntegerValueFn)dlsym(
        RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
  });
  if (createDigitizer == NULL || createFinger == NULL ||
      appendEvent == NULL || setIntValue == NULL) {
    return NULL;
  }

  uint64_t mach = mach_absolute_time();
  FdbAbsoluteTime ts = {(uint32_t)(mach >> 32), (uint32_t)(mach & 0xFFFFFFFF)};

  CFTypeRef handEvent = createDigitizer(
      kCFAllocatorDefault, ts,
      kIOHIDDigitizerTransducerTypeHand,
      0,                              // index
      0,                              // identity
      kIOHIDDigitizerEventTouch,      // eventMask
      0,                              // buttonMask
      0, 0, 0,                        // x, y, z
      0, 0,                           // tipPressure, barrelPressure
      false,                          // range
      true,                           // touch
      0);                             // options
  if (handEvent == NULL) return NULL;
  setIntValue(handEvent, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);

  uint32_t eventMask = (touch.phase == UITouchPhaseMoved)
      ? kIOHIDDigitizerEventPosition
      : (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch);
  Boolean isTouching = (touch.phase != UITouchPhaseEnded);

  CGPoint loc = [touch locationInView:touch.window];

  CFTypeRef fingerEvent = createFinger(
      kCFAllocatorDefault, ts,
      1,                          // index (1-based)
      2,                          // identity
      eventMask,
      (IOHIDFloat)loc.x, (IOHIDFloat)loc.y, 0.0,
      0,                          // tipPressure
      0,                          // twist
      5.0, 5.0,                   // minor, major radius
      1.0, 1.0, 1.0,              // quality, density, irregularity
      isTouching,                 // range
      isTouching,                 // touch
      0);
  if (fingerEvent == NULL) {
    CFRelease(handEvent);
    return NULL;
  }
  setIntValue(fingerEvent, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
  appendEvent(handEvent, fingerEvent);
  CFRelease(fingerEvent);

  return handEvent;
}

/// Sets up [touch] with the location, view, and HID event for the current
/// phase. Mirrors the second half of KIF's `-[UITouch initAtPoint:inWindow:]`
/// plus the per-phase HID event refresh that iOS 26 requires.
static void FdbConfigureTouch(UITouch *touch, CGPoint windowPoint, UIWindow *window) {
  [touch _setLocationInWindow:windowPoint resetPrevious:NO];
  [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
  CFTypeRef hid = FdbCreateHidEventForTouch(touch);
  if (hid != NULL) {
    [touch _setHidEvent:hid];
    CFRelease(hid);
  }
}

/// Builds a fresh UIEvent for [touch] in its current phase. Mirrors KIF's
/// `-[UIView eventWithTouch:]` + `-[UIEvent kif_setIOHIDEventWithTouches:]`.
/// On iOS 26 a new IOHIDEvent must be attached for each phase; UIKit
/// silently drops the touch otherwise. The UIApplication `_touchesEvent`
/// is a singleton, so we clear it and rebuild it each call.
static UIEvent *FdbBuildEventForTouch(UITouch *touch) {
  UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
  [event _clearTouches];
  CFTypeRef hid = FdbCreateHidEventForTouch(touch);
  if (hid != NULL) {
    [event _setHIDEvent:hid];
    CFRelease(hid);
  }
  [event _addTouch:touch forDelayedDelivery:NO];
  return event;
}

#pragma mark - Public entry point

BOOL FdbHelperNativeTapAtPoint(CGPoint point, NSError **error) {
  UIWindow *window = FdbTopmostWindowAtPoint(point);
  if (window == nil) {
    if (error) {
      *error = [NSError errorWithDomain:@"io.fdb.helper.tap" code:1
          userInfo:@{NSLocalizedDescriptionKey: @"No window available"}];
    }
    return NO;
  }

  // KIF passes the point in the view's coordinate space and converts to
  // window coordinates inside `initAtPoint:inWindow:`. Our Flutter logical
  // coordinates are already window-relative (Flutter renders into the
  // root window's coordinate space) so we use the window itself as the
  // hit-test origin.
  CGPoint windowPoint = point;

  // Allocate via the runtime to avoid hard-coding a non-public init
  // selector. KIF's initAtPoint:inView: ultimately calls
  // [super init] then sets ivars one by one — we replicate that here.
  UITouch *touch = [[UITouch alloc] init];
  if (touch == nil) {
    if (error) {
      *error = [NSError errorWithDomain:@"io.fdb.helper.tap" code:2
          userInfo:@{NSLocalizedDescriptionKey: @"UITouch alloc failed"}];
    }
    return NO;
  }

  // Configure touch: mirrors KIF's `initAtPoint:inWindow:` setup order.
  // Order matters: setWindow: is documented as "wipes out some values,
  // needs to be first".
  [touch setWindow:window];
  [touch setTapCount:1];
  [touch _setLocationInWindow:windowPoint resetPrevious:YES];

  UIView *hitView = [window hitTest:windowPoint withEvent:nil];
  if (hitView == nil) hitView = window;
  [touch setView:hitView];

  [touch setPhase:UITouchPhaseBegan];

  if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) {
    [touch _setIsFirstTouchForView:YES];
  }

  [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];

  if ([touch respondsToSelector:@selector(setGestureView:)]) {
    [touch setGestureView:hitView];
  }

  // Initial HID event (Began phase).
  CFTypeRef initialHid = FdbCreateHidEventForTouch(touch);
  if (initialHid != NULL) {
    [touch _setHidEvent:initialHid];
    CFRelease(initialHid);
  }

  // ----- Began -----
  // Update timestamp + rebuild HID for fresh "began" snapshot.
  [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
  [touch setPhase:UITouchPhaseBegan];
  UIEvent *beganEvent = FdbBuildEventForTouch(touch);
  [UIApplication.sharedApplication sendEvent:beganEvent];

  // ----- Ended -----
  // KIF v3.12.2 fix for iOS 26: build a NEW UIEvent for the ended phase.
  [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
  [touch setPhase:UITouchPhaseEnded];
  UIEvent *endedEvent = FdbBuildEventForTouch(touch);
  [UIApplication.sharedApplication sendEvent:endedEvent];

  return YES;
}
