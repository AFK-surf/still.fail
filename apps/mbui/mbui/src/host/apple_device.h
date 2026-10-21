// The device beyond the window on macOS and iOS (src/host/device.mbt): a key catcher's keys, the soft keyboard's
// height, the clipboard read and written (pictures as PNG), the screen kept awake, haptics. Included by mac_app.m and
// ios_app.m before their view's implementation (their mb_cb and the_view declared above it); everything here runs on
// the main thread, MoonBit's.

#include <TargetConditionals.h>
#import <ImageIO/ImageIO.h>

void mb_host_request_frame(void);

// ---- a key catcher (@host.key_catch) ----

// the focus is a key catcher's: the view's keys are its (catch_key below), its input method has no text of its own
static int key_catching;

void mb_host_key_catch(int32_t on) { key_catching = on != 0; }

// The framework's modifiers (src/ui/desktop.mbt: Shift 1, Ctrl 2, Alt 4, ⌘ 8) and a key's code for the catcher, by
// the keyboard's own (HID usage on iOS, the virtual key code on macOS: kVK_*): the named keys; a character with
// Ctrl, Alt or ⌘ held as its key (1000 + it, lower case). 0: not the catcher's as a key (text, through the input
// method).
static int catch_code(int named, NSString *chars, int mods) {
  if (named) return named;
  if (!(mods & (2 | 4 | 8)) || chars.length != 1) return 0;
  unichar c = [chars.lowercaseString characterAtIndex:0];
  return c >= 32 && c < 0xF700 ? 1000 + c : 0;
}

#if TARGET_OS_IPHONE

static int catch_press(UIPress *p) {
  UIKeyModifierFlags m = p.key.modifierFlags;
  int mods = ((m & UIKeyModifierShift) ? 1 : 0) | ((m & UIKeyModifierControl) ? 2 : 0) |
             ((m & UIKeyModifierAlternate) ? 4 : 0) | ((m & UIKeyModifierCommand) ? 8 : 0);
  int named = 0;
  switch (p.key.keyCode) {
    case UIKeyboardHIDUsageKeyboardDeleteOrBackspace: named = 1; break;
    case UIKeyboardHIDUsageKeyboardDeleteForward: named = 2; break;
    case UIKeyboardHIDUsageKeyboardLeftArrow: named = 3; break;
    case UIKeyboardHIDUsageKeyboardRightArrow: named = 4; break;
    case UIKeyboardHIDUsageKeyboardUpArrow: named = 5; break;
    case UIKeyboardHIDUsageKeyboardDownArrow: named = 6; break;
    case UIKeyboardHIDUsageKeyboardReturnOrEnter:
    case UIKeyboardHIDUsageKeypadEnter: named = 7; break;
    case UIKeyboardHIDUsageKeyboardHome: named = 8; break;
    case UIKeyboardHIDUsageKeyboardEnd: named = 9; break;
    case UIKeyboardHIDUsageKeyboardPageUp: named = 15; break;
    case UIKeyboardHIDUsageKeyboardPageDown: named = 16; break;
    case UIKeyboardHIDUsageKeyboardEscape: named = 17; break;
    case UIKeyboardHIDUsageKeyboardTab: named = 18; break;
    case UIKeyboardHIDUsageKeyboardSpacebar: named = 1032; break;
    default: break;
  }
  int code = catch_code(named, p.key.charactersIgnoringModifiers, mods);
  if (code) mb_cb.key(code, mods);
  return code != 0;
}

#else

static int catch_key_down(NSEvent *e) {
  NSEventModifierFlags m = e.modifierFlags;
  int mods = ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
             ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
  // ⌘Q quits still
  if ((m & NSEventModifierFlagCommand) && [e.charactersIgnoringModifiers.lowercaseString isEqualToString:@"q"]) return 0;
  int named = 0;
  switch (e.keyCode) {
    case 51: named = 1; break;            // Delete (Backspace)
    case 117: named = 2; break;           // Forward Delete
    case 123: named = 3; break;
    case 124: named = 4; break;
    case 126: named = 5; break;
    case 125: named = 6; break;
    case 36: case 76: named = 7; break;   // Return, Enter
    case 115: named = 8; break;           // Home
    case 119: named = 9; break;           // End
    case 116: named = 15; break;          // Page Up
    case 121: named = 16; break;          // Page Down
    case 53: named = 17; break;           // Escape
    case 48: named = 18; break;           // Tab
    case 49: named = 1032; break;         // Space
    default: break;
  }
  int code = catch_code(named, e.charactersIgnoringModifiers, mods);
  if (code) mb_cb.key(code, mods);
  return code != 0;
}

#endif

// ---- the soft keyboard ----

// How far the keyboard reaches over the view's foot, in points: the view ends at the keyboard layout guide's top
// (ios_app.m's MBController), which is the safe area's foot while it is down.
double mb_host_ime_inset(void) {
#if TARGET_OS_IPHONE
  UIView *root = the_view.superview;
  if (!root) return 0;
  double over = root.bounds.size.height - root.safeAreaInsets.bottom - root.keyboardLayoutGuide.layoutFrame.origin.y;
  return over > 0 ? over : 0;
#else
  return 0;
#endif
}

// No system here says a copy itself.
int32_t mb_host_copy_shown(void) { return 0; }

// ---- the clipboard read ----

enum { CLIP_NONE = 0, CLIP_PNG = 1, CLIP_TOO_LARGE = 2, CLIP_UNREADABLE = 3 };
static const NSUInteger clip_png_max = 8u << 20, clip_source_max = 32u << 20;
static const double clip_pixels_max = 16.0 * 1024 * 1024;
static NSMutableDictionary<NSNumber *, NSDictionary *> *clip_reads;
static int32_t clip_next = 1;

static BOOL clip_is_png(NSData *d) {
  static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', 13, 10, 26, 10};
  return d.length >= 8 && memcmp(d.bytes, sig, 8) == 0;
}

// A picture's bytes (another kind than PNG) as PNG, within the bounds (still.fail's ScreenClips.kt asPng).
static int clip_make_png(NSData *src, NSData **out) {
  if (src.length == 0) return CLIP_UNREADABLE;
  if (clip_is_png(src)) {
    if (src.length > clip_png_max) return CLIP_TOO_LARGE;
    *out = src;
    return CLIP_PNG;
  }
  if (src.length > clip_source_max) return CLIP_TOO_LARGE;
  CGImageSourceRef s = CGImageSourceCreateWithData((__bridge CFDataRef)src, NULL);
  if (!s) return CLIP_UNREADABLE;
  int kind = CLIP_UNREADABLE;
  NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(s, 0, NULL));
  double w = [props[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
  double h = [props[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
  if (w <= 0 || h <= 0) {
    kind = CLIP_UNREADABLE;
  } else if (w * h > clip_pixels_max) {
    kind = CLIP_TOO_LARGE;
  } else {
    CGImageRef img = CGImageSourceCreateImageAtIndex(s, 0, NULL);
    if (img) {
      NSMutableData *png = [NSMutableData data];
      CGImageDestinationRef d = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
      if (d) {
        CGImageDestinationAddImage(d, img, NULL);
        if (CGImageDestinationFinalize(d)) {
          if (png.length > clip_png_max) {
            kind = CLIP_TOO_LARGE;
          } else {
            kind = CLIP_PNG;
            *out = png;
          }
        }
        CFRelease(d);
      }
      CGImageRelease(img);
    }
  }
  CFRelease(s);
  return kind;
}

// The pasteboard read now (its words, its picture's bytes as they are there), the picture made a PNG off the main
// thread, then told (MB_OUTSIDE_CLIP).
int32_t mb_host_clip_read(void) {
  if (!clip_reads) clip_reads = [NSMutableDictionary new];
  int32_t id = clip_next++;
  clip_reads[@(id)] = @{@"state" : @0};
#if TARGET_OS_IPHONE
  UIPasteboard *pb = UIPasteboard.generalPasteboard;
  NSString *text = pb.hasStrings ? (pb.string ?: @"") : @"";
  NSData *pic = nil;
  if (pb.hasImages) {
    pic = [pb dataForPasteboardType:@"public.png"];
    if (!pic) {
      UIImage *im = pb.image;
      pic = im ? UIImagePNGRepresentation(im) : [NSData data];
    }
  }
#else
  NSPasteboard *pb = NSPasteboard.generalPasteboard;
  NSString *text = [pb stringForType:NSPasteboardTypeString] ?: @"";
  NSData *pic = [pb dataForType:NSPasteboardTypePNG];
  if (!pic) pic = [pb dataForType:NSPasteboardTypeTIFF];
  if (!pic && [pb canReadObjectForClasses:@[ NSImage.class ] options:nil]) pic = [NSData data];
#endif
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSData *png = nil;
    int kind = pic ? clip_make_png(pic, &png) : CLIP_NONE;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!clip_reads[@(id)]) return;
      clip_reads[@(id)] = @{@"state" : @1, @"text" : text, @"picture" : @(kind), @"png" : png ?: [NSData data]};
      mb_host_outside(MB_OUTSIDE_CLIP, id, 1);
      mb_host_request_frame();
    });
  });
  return id;
}

int32_t mb_host_clip_state(int32_t id) {
  NSDictionary *r = clip_reads[@(id)];
  return r ? [r[@"state"] intValue] : -1;
}

int32_t mb_host_clip_picture(int32_t id) { return [clip_reads[@(id)][@"picture"] intValue]; }

moonbit_string_t mb_host_clip_text(int32_t id) { return mb_string_from_ns(clip_reads[@(id)][@"text"] ?: @""); }

moonbit_bytes_t mb_host_clip_png(int32_t id) {
  NSData *d = clip_reads[@(id)][@"png"];
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)d.length, 0);
  if (d.length) memcpy(out, d.bytes, d.length);
  return out;
}

void mb_host_clip_end(int32_t id) { [clip_reads removeObjectForKey:@(id)]; }

// ---- the clipboard written: words, or a PNG (the label is Android's; the pasteboard has none) ----

void mb_host_clip_set(moonbit_string_t text, moonbit_bytes_t png, moonbit_string_t label) {
  (void)label;
  int32_t n = Moonbit_array_length(png);
#if TARGET_OS_IPHONE
  UIPasteboard *pb = UIPasteboard.generalPasteboard;
  if (n > 0) pb.items = @[ @{@"public.png" : [NSData dataWithBytes:png length:n]} ];
  else pb.string = mb_ns_from_string(text);
#else
  NSPasteboard *pb = NSPasteboard.generalPasteboard;
  [pb clearContents];
  if (n > 0) {
    NSData *d = [NSData dataWithBytes:png length:n];
    [pb setData:d forType:NSPasteboardTypePNG];
    // (and as TIFF, for apps that read only that)
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:d];
    NSData *tiff = rep.TIFFRepresentation;
    if (tiff) [pb setData:tiff forType:NSPasteboardTypeTIFF];
  } else {
    [pb setString:mb_ns_from_string(text) forType:NSPasteboardTypeString];
  }
#endif
}

// ---- awake, haptics ----

#if !TARGET_OS_IPHONE
static id<NSObject> awake_activity;
#endif

void mb_host_keep_awake(int32_t on) {
#if TARGET_OS_IPHONE
  UIApplication.sharedApplication.idleTimerDisabled = on ? YES : NO;
#else
  // the display kept from sleeping while idle (as IOPMAssertion's PreventUserIdleDisplaySleep), until let go
  if (on && !awake_activity) {
    awake_activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityIdleDisplaySleepDisabled | NSActivityUserInitiated
                                                                  reason:@"the app asked to keep the screen on"];
  } else if (!on && awake_activity) {
    [NSProcessInfo.processInfo endActivity:awake_activity];
    awake_activity = nil;
  }
#endif
}

// device.mbt's haptic_*: long press, context click, a handle moved, confirm, reject, a key tapped.
void mb_host_haptic(int32_t kind) {
#if TARGET_OS_IPHONE
  switch (kind) {
    case 0: [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred]; break;
    case 1: [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid] impactOccurred]; break;
    case 2: [[UISelectionFeedbackGenerator new] selectionChanged]; break;
    case 3: [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess]; break;
    case 4: [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError]; break;
    case 5: [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred]; break;
    default: break;
  }
#else
  // a Force Touch trackpad's (nothing without one)
  NSHapticFeedbackPattern p = kind == 2 ? NSHapticFeedbackPatternAlignment
                              : (kind == 0 || kind == 3) ? NSHapticFeedbackPatternLevelChange
                                                         : NSHapticFeedbackPatternGeneric;
  if (kind < 0 || kind > 5) return;
  [NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:p performanceTime:NSHapticFeedbackPerformanceTimeNow];
#endif
}

// An app's own native calls (src/host/native.mbt): none on this host yet.
int32_t mb_host_native_call(moonbit_string_t name, moonbit_string_t params) { return 0; }
int32_t mb_host_native_state(int32_t id) { return -1; }
moonbit_string_t mb_host_native_result(int32_t id) { return moonbit_make_string_raw(0); }
void mb_host_native_end(int32_t id) {}
