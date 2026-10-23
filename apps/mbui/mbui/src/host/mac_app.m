// macOS host: an NSWindow whose view is a CAMetalLayer, frames from the
// view's display link, input from AppKit, and the system input method
// through NSTextInputClient. The window's content is a plain view holding
// the native views' (apple_views.m) and, over them, the canvas's.
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import <Network/Network.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <dlfcn.h>
#import <mach/mach.h>
#include <pwd.h>
#import "apple.h"
#include "post.h"
#include "done_watch.h"

// (Network's path monitor, below: the framework asked of the linker by this file, as an app of mbui's links what its
// own moon.pkg names, which need not be Network)
__asm__(".linker_option \"-framework\", \"Network\"");

mb_callbacks mb_cb;

// Back (host_native.mbt `set_back`): ⌘[ and a mouse's back button, while the app takes it.
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);
static mb_back_fn back_cb;
static int back_on;
static void go_back(void) {
  if (back_cb && back_on) back_cb(2, 0, 1, 0);
}

@interface MBView : NSView <NSTextInputClient>
@property(nonatomic) BOOL imeActive;
@property(nonatomic) NSRect caretRect;
@property(nonatomic, copy) NSString *mirror;  // the field's text, for the input method
@property(nonatomic) NSRange sel;
@property(nonatomic) NSUInteger markedLen;
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic) BOOL wantFrame;
@end

static MBView *the_view;
static void notice_start(void);  // the system's notifications (below), before the app runs
static int bench_mode;
// The desktop window as the app asks for it (@hostapi.window_setup): its first size and its least, and whether its
// title bar is the app's own top row (the system's buttons in it, 16 in and centred on its 44: as still.fail's
// desktop app's hiddenInset window)
static double setup_w, setup_h, setup_min_w, setup_min_h;
static int setup_inset;
// MBUI_SAFE=<top>,<bottom> (points), in a scripted run only: a phone's system bars round the app's view, as Android's
// MainActivity and the iOS host lay the app inside them (its view that much smaller, the bands in the page's ground)
static double safe_top, safe_bottom;
static int ground_dark;
// MBUI_GROUND=#<light>,#<dark> with it: the page's grounds as the app's Android manifest says them (dev.mbui.ground,
// the same value); else the hosts' own (F5F5F7, 1B1C1F)
static uint32_t ground_light = 0xF5F5F7, ground_of_dark = 0x1B1C1F;
static NSView *the_box;
// the pointer's shape (@hostapi.set_cursor), and the press under way (what @hostapi.window_drag drags the window with)
static int cursor_kind;
static NSEvent *down_event;
static int down_secondary;
static const char *shot_path;
static void tell_state(void);
static void bring_back(void);  // the window out again (below: the app's life on the Mac)
static const char *script;

// A scripted run in stable mode (MBUI_SCRIPT with MBUI_BENCH=-1: screenshots) is settled, not paced: its frames are
// not the display's but drawn one after another as fast as they are made, on a clock of their own (1/60 s a frame,
// from 0), and none moves the clock on while the app awaits the host (what the frame just built said: an image
// decoding, a view loading — effect.mb's outside, told here by mb_host_awaiting; the host's events for them,
// mb_host_outside, end it): the app's time stands still until what it waits on is in, so what a frame shows does not
// hang on how fast the machine is. The app's timers (wake_after) are on that clock too. The script's
// steps count those frames; `shot` takes its picture of the frame at a declared moment on that clock (below).
static int settle;
static double settle_clock;        // ms, the frames' clock
static double settle_wake = -1;    // when the app asked to be woken, on that clock (-1: not)
static BOOL app_wants;             // the app (or the host for it) asked for a frame since the last one began
static BOOL in_app_frame;          // the app's frame is being built (what it asks for there, its frame's end says)
static BOOL script_wants;          // the script goes on (its next step)
static int awaiting;               // what the app awaits from the host, as its last frame said
static char awaited_what[2048];    // what it awaits, as its last frame said
static mb_outside_fn outside_cb;   // who is told as that is done (host_native.mbt's set_outside)
static void pump_soon(void);
static void script_next(void);
static int settled_run(void);
static void set_ground(void);

double mb_now_ms(void) { return CACurrentMediaTime() * 1000.0; }

CTFontRef mb_platform_font(double size, int weight, int mono) {
  NSFontWeight w = weight >= 700 ? NSFontWeightBold
                   : weight >= 600 ? NSFontWeightSemibold
                   : weight >= 500 ? NSFontWeightMedium
                                   : NSFontWeightRegular;
  NSFont *f = mono ? [NSFont monospacedSystemFontOfSize:size weight:w] : [NSFont systemFontOfSize:size weight:w];
  return (CTFontRef)CFBridgingRetain(f);
}

static void send_text(int kind, NSString *s, int a, int b) {
  mb_cb.text(kind, mb_string_from_ns(s ?: @""), a, b);
}

// ⌘V (the key, or the menu bar's 粘贴): a picture on the clipboard (not a file's icon beside its name, as the Finder
// copies one) is the app's ⌘V (1000 + v), which reads the clipboard for it (@hostapi.clip_read), as a page's paste takes
// a picture as a file; else its words, typed
static void paste_now(int mods) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  BOOL files = [pb canReadObjectForClasses:@[ NSURL.class ] options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
  if (!files && [pb canReadItemWithDataConformingToTypes:@[ NSPasteboardTypePNG, NSPasteboardTypeTIFF, @"public.image" ]]) {
    mb_cb.key(1000 + 'v', mods);
  } else {
    NSString *s = [pb stringForType:NSPasteboardTypeString];
    if (s.length) send_text(0, s, 0, 0);
  }
}

static void run_script_step(int step);

// the device beyond the window (device.mbt): a key catcher's keys, the clipboard, awake, haptics
#include "apple_device.h"

static int32_t drop_pick(NSArray<NSURL *> *urls);

// Files dragged in from outside (Finder) and let go on the window (ui/drop.mbt): where they are held, posted on
// `mbui.drop` as they move ({"type":"over","x","y"}, {"type":"left"}), then let go, their files read as a pick's
// ({"type":"drop","x","y","pick"}).
static void drop_post(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  mb_post("mbui.drop", (const char *)d.bytes, d.length, NULL, 0);
}

@implementation MBView

- (instancetype)initWithFrame:(NSRect)f {
  self = [super initWithFrame:f];
  self.wantsLayer = YES;
  self.mirror = @"";
  [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
  return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
  return [self draggingUpdated:info];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
  NSPoint p = [self convertPoint:info.draggingLocation fromView:nil];
  drop_post([NSString stringWithFormat:@"{\"type\":\"over\",\"x\":%.1f,\"y\":%.1f}", p.x, p.y]);
  return NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)info {
  (void)info;
  drop_post(@"{\"type\":\"left\"}");
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
  NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[ NSURL.class ]
                                                                  options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
  if (urls.count == 0) {
    drop_post(@"{\"type\":\"left\"}");
    return NO;
  }
  NSPoint p = [self convertPoint:info.draggingLocation fromView:nil];
  int32_t pid = drop_pick(urls);
  drop_post([NSString stringWithFormat:@"{\"type\":\"drop\",\"x\":%.1f,\"y\":%.1f,\"pick\":%d}", p.x, p.y, pid]);
  return YES;
}

- (CALayer *)makeBackingLayer {
  CAMetalLayer *l = [CAMetalLayer layer];
  mb_render_init(l);
  return l;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

// the pointer over a web view shown under the canvas goes to it
- (NSView *)hitTest:(NSPoint)p {
  NSPoint q = [self convertPoint:p fromView:self.superview];
  if (mb_views_pass_through(q.x, q.y)) return nil;
  return [super hitTest:p];
}
- (BOOL)wantsUpdateLayer { return YES; }

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window) return;
  if (!settle) {
    self.link = [self displayLinkWithTarget:self selector:@selector(tick:)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  }
  [self addTrackingArea:[[NSTrackingArea alloc]
                            initWithRect:NSZeroRect
                                 options:NSTrackingMouseMoved | NSTrackingActiveAlways |
                                         NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited |
                                         NSTrackingCursorUpdate
                                   owner:self
                                userInfo:nil]];
  [self requestFrame];
}

- (void)requestFrame {
  self.wantFrame = YES;
  if (settle) {
    app_wants = YES;
    pump_soon();
    return;
  }
  self.link.paused = NO;
}

- (void)setFrameSize:(NSSize)s {
  [super setFrameSize:s];
  [self requestFrame];
}

- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  [self requestFrame];
}

// MBUI_RECORD=<dir>: a recording, every frame on a clock of its own (60 a second, whatever the machine keeps up
// with), each drawn into <dir>/f<n>.png from frame MBUI_RECORD_FROM on (0), MBUI_RECORD_FRAMES of them (600):
// motion as it is, frame by frame (scripts/record.sh makes the video).
static const char *record_dir;
static int record_n, record_from = 0, record_frames = 600;
static double record_t0 = -1;

- (void)drawFrame {
  NSSize s = self.bounds.size;
  double scale = self.window.backingScaleFactor ?: 2.0;
  ((CAMetalLayer *)self.layer).contentsScale = scale;
  mb_text_scale = scale;
  mb_render_set_size(s.width, s.height, scale);
  self.wantFrame = NO;
  if (record_dir) {
    if (record_t0 < 0) {
      record_t0 = mb_now_ms();
      fprintf(stdout, "RECORD t0 %.6f\n", record_t0);
      fflush(stdout);
    }
    mb_cb.frame(s.width, s.height, scale, record_t0 + record_n * (1000.0 / 60.0));
    if (record_n >= record_from && record_n < record_from + record_frames) {
      char p[1024];
      snprintf(p, sizeof p, "%s/f%05d.png", record_dir, record_n - record_from);
      mb_render_snapshot(p);
    }
    record_n++;
    if (record_n >= record_from + record_frames) exit(0);
    // every frame drawn, moving or not: the video's clock
    self.wantFrame = YES;
    return;
  }
  if (settle) app_wants = NO;
  in_app_frame = YES;
  mb_cb.frame(s.width, s.height, scale, settle ? settle_clock : mb_now_ms());
  in_app_frame = NO;
}

static int frames_drawn;

// ---- a settled run's frames (settle, above) ----

static BOOL pump_queued;
static double awaiting_since = -1;
static void pump(void);

static void pump_soon(void) {
  if (pump_queued) return;
  pump_queued = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    pump_queued = NO;
    pump();
  });
}

static void script_next(void) {
  if (!settle) {
    [the_view requestFrame];
    return;
  }
  script_wants = YES;
  pump_soon();
}

static void pump(void) {
  MBView *v = the_view;
  if (!v || !(app_wants || script_wants || settle_wake >= 0)) return;
  if (awaiting > 0) {
    // the clock stands still; what the app asks for meanwhile (a read it answers, a list measured) is drawn at the
    // same time, not a step. Half a minute of it is said, and the run goes on.
    if (app_wants) [v drawFrame];
    if (awaiting_since < 0) awaiting_since = CACurrentMediaTime();
    if (CACurrentMediaTime() - awaiting_since < 30) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ pump(); });
      return;
    }
    // what never came is a failure, said: not a picture taken as if it had
    fprintf(stdout, "SETTLE FAIL: still awaiting after 30 s: %s\n", awaited_what);
    fprintf(stderr, "SETTLE FAIL: still awaiting after 30 s: %s\n", awaited_what);
    exit(3);
  }
  awaiting_since = -1;
  settle_clock = frames_drawn * (1000.0 / 60.0);
  if (settle_wake >= 0 && settle_wake <= settle_clock) {
    settle_wake = -1;
    app_wants = YES;
  }
  script_wants = NO;
  [v drawFrame];
  frames_drawn++;
  run_script_step(frames_drawn);
  if (app_wants || script_wants || settle_wake >= 0) pump_soon();
}

- (void)tick:(CADisplayLink *)l {
  if (!self.wantFrame) {
    l.paused = YES;
    return;
  }
  [self drawFrame];
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
  if (!self.wantFrame) l.paused = YES;
}

// ---- pointer ----

- (NSPoint)pt:(NSEvent *)e {
  return [self convertPoint:e.locationInWindow fromView:nil];
}
// the event's own time (seconds since startup, CACurrentMediaTime's clock) while MoonBit handles it
static double event_time = -1;
static void mouse(int kind, NSPoint p, NSEvent *e) {
  event_time = e.timestamp * 1000.0;
  mb_cb.pointer(kind, p.x, p.y, 0);
  event_time = -1;
}
static void mouse_button(int kind, NSPoint p, NSEvent *e, int button) {
  event_time = e.timestamp * 1000.0;
  mb_cb.pointer(kind, p.x, p.y, button);
  event_time = -1;
}
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self pt:e];
  [self.window makeFirstResponder:self];
  // Ctrl-click is the secondary click (a context menu's)
  down_secondary = (e.modifierFlags & NSEventModifierFlagControl) != 0;
  if (down_secondary) {
    mouse_button(0, p, e, 2);
    return;
  }
  down_event = e;
  mouse(0, p, e);
  down_event = nil;
}
- (void)mouseDragged:(NSEvent *)e {
  if (down_secondary) return;
  mouse(1, [self pt:e], e);
}
- (void)mouseMoved:(NSEvent *)e {
  mouse(1, [self pt:e], e);
}
- (void)mouseUp:(NSEvent *)e {
  if (down_secondary) {
    down_secondary = 0;
    mouse_button(2, [self pt:e], e, 2);
    return;
  }
  mouse(2, [self pt:e], e);
}
- (void)rightMouseDown:(NSEvent *)e {
  mouse_button(0, [self pt:e], e, 2);
}
- (void)rightMouseUp:(NSEvent *)e {
  mouse_button(2, [self pt:e], e, 2);
}
// the pointer gone out of the window (nothing hovered), and its shape where it comes in
- (void)mouseExited:(NSEvent *)e {
  mb_cb.pointer(7, -1, -1, 0);
}
static NSCursor *cursor_of(int kind) {
  switch (kind) {
    case 1: return NSCursor.pointingHandCursor;
    case 2: return NSCursor.IBeamCursor;
    case 3: return NSCursor.resizeLeftRightCursor;
    case 4: return NSCursor.resizeUpDownCursor;
    case 5: return NSCursor.openHandCursor;
    default: return NSCursor.arrowCursor;
  }
}
- (void)cursorUpdate:(NSEvent *)e {
  [cursor_of(cursor_kind) set];
}
- (void)otherMouseUp:(NSEvent *)e {
  if (e.buttonNumber == 3) go_back();
}
- (void)scrollWheel:(NSEvent *)e {
  NSPoint p = [self pt:e];
  // a mouse wheel's notch: 40 points, as a browser scrolls by one, eased in by the app (phase 4); a trackpad's
  // as it comes (1 the fingers on it, 3 its momentum)
  double dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 40.0;
  double dx = e.hasPreciseScrollingDeltas ? e.scrollingDeltaX : e.scrollingDeltaX * 40.0;
  int phase = !e.hasPreciseScrollingDeltas ? 4 : e.momentumPhase != NSEventPhaseNone ? 3 : (e.phase != NSEventPhaseNone ? 1 : 0);
  // what is held with it, above the phase (ui's wheel_mod_*)
  NSEventModifierFlags m = e.modifierFlags;
  int mods = ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
             ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
  mb_cb.wheel(p.x, p.y, -dx, -dy, phase | (mods << 4));
}
// a trackpad's pinch: a wheel with ⌃ held and marked a pinch (ui's wheel_mod_pinch), as a browser gives one: a
// picture zooms by it (its magnification as a hundredth of a wheel's point each way), no list scrolls
- (void)magnifyWithEvent:(NSEvent *)e {
  NSPoint p = [self pt:e];
  mb_cb.wheel(p.x, p.y, 0, -e.magnification * 100.0, 1 | ((2 | 16) << 4));
}

// ---- keys ----

// A key with ⌘ is the view's first, as it was before the app had a menu bar (the app's shortcuts, a field's editing
// keys, a key catcher's): only those the menu bar keeps for the system go on to it (⌘Q, ⌘W, ⌘H, ⌥⌘H, ⌘M, ⌃⌘F), and
// with no menu bar given (a bare run) they come back here as keys (keyDown).
- (BOOL)performKeyEquivalent:(NSEvent *)e {
  if (e.type != NSEventTypeKeyDown || !(e.modifierFlags & NSEventModifierFlagCommand) || self.window.firstResponder != self)
    return [super performKeyEquivalent:e];
  NSEventModifierFlags m = e.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagControl |
                                              NSEventModifierFlagOption | NSEventModifierFlagCommand);
  NSString *c = e.charactersIgnoringModifiers.lowercaseString;
  NSEventModifierFlags cmd = NSEventModifierFlagCommand;
  BOOL system = (m == cmd && ([c isEqualToString:@"q"] || [c isEqualToString:@"w"] || [c isEqualToString:@"h"] ||
                              [c isEqualToString:@"m"])) ||
                (m == (cmd | NSEventModifierFlagOption) && [c isEqualToString:@"h"]) ||
                (m == (cmd | NSEventModifierFlagControl) && [c isEqualToString:@"f"]);
  if (system && NSApp.mainMenu) return NO;
  [self keyDown:e];
  return YES;
}

// The menu bar's editing items (the system's Edit menu, mb_host_menu_setup): each the key it names, pressed.
- (void)cut:(id)sender { mb_cb.key(14, 8); }
- (void)copy:(id)sender { mb_cb.key(13, 8); }
- (void)paste:(id)sender { paste_now(8); }
- (void)selectAll:(id)sender { mb_cb.key(12, 8); }
- (void)undo:(id)sender { mb_cb.key(1000 + 'z', 8); }
- (void)redo:(id)sender { mb_cb.key(1000 + 'z', 9); }

- (void)keyDown:(NSEvent *)e {
  // a key catcher's focus (apple_device.h): its keys (a composition under way keeps them)
  if (key_catching && self.imeActive && self.markedLen == 0 && catch_key_down(e)) return;
  NSEventModifierFlags m = e.modifierFlags;
  int mods = ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
             ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
  // the arrows (with ⌘, ⌥ or none): a field's own moves while it has the keyboard; else the app's
  int arrow = e.keyCode == 123 ? 3 : e.keyCode == 124 ? 4 : e.keyCode == 126 ? 5 : e.keyCode == 125 ? 6 : 0;
  if (m & NSEventModifierFlagCommand) {
    NSString *c = e.charactersIgnoringModifiers.lowercaseString;
    if (arrow) {
      if (self.imeActive) [self interpretKeyEvents:@[ e ]];
      else mb_cb.key(arrow, mods);
    } else if ([c isEqualToString:@"q"]) [NSApp terminate:nil];
    else if ([c isEqualToString:@"["]) go_back();
    else if ([c isEqualToString:@"a"]) mb_cb.key(12, mods);
    else if ([c isEqualToString:@"c"]) mb_cb.key(13, mods);
    else if ([c isEqualToString:@"x"]) mb_cb.key(14, mods);
    else if ([c isEqualToString:@"v"]) paste_now(mods);
    else if (c.length == 1) {
      // any other ⌘ key: the app's shortcut (1000 + the character)
      mb_cb.key(1000 + [c characterAtIndex:0], mods);
    }
    return;
  }
  // Escape and Tab are the app's (a composition under way keeps its Escape)
  if (e.keyCode == 53 && self.markedLen == 0) {
    mb_cb.key(17, mods);
    return;
  }
  if (e.keyCode == 48 && self.markedLen == 0) {
    mb_cb.key(18, mods);
    return;
  }
  if (self.imeActive) {
    // ⌥ with an arrow and an empty field: the app's (the chat before or after)
    if (arrow && (m & NSEventModifierFlagOption) && self.mirror.length == 0) {
      mb_cb.key(arrow, mods);
      return;
    }
    [self interpretKeyEvents:@[ e ]];
    return;
  }
  // without a field to type in: keys that scroll the list under the pointer
  switch (e.keyCode) {
    case 115: mb_cb.key(8, mods); break;   // Home
    case 119: mb_cb.key(9, mods); break;   // End
    case 116: mb_cb.key(15, mods); break;  // Page Up
    case 121: mb_cb.key(16, mods); break;  // Page Down
    case 126: mb_cb.key(5, mods); break;   // up
    case 125: mb_cb.key(6, mods); break;   // down
    case 123: mb_cb.key(3, mods); break;   // left
    case 124: mb_cb.key(4, mods); break;   // right
    case 36:
    case 76: mb_cb.key(7, mods); break;    // Return, Enter
    default: {
      // a character with no field to take it (Space, a letter): the app's, as 1000 + it
      NSString *c = e.charactersIgnoringModifiers.lowercaseString;
      if (c.length == 1 && [c characterAtIndex:0] >= 32 && [c characterAtIndex:0] < 0xF700)
        mb_cb.key(1000 + [c characterAtIndex:0], mods);
    }
  }
}

static int shift_down(void) {
  return ([NSEvent modifierFlags] & NSEventModifierFlagShift) ? 1 : 0;
}

- (void)doCommandBySelector:(SEL)sel {
  NSString *s = NSStringFromSelector(sel);
  int code = 0, mods = 0;
  if ([s isEqualToString:@"deleteBackward:"]) code = 1;
  else if ([s isEqualToString:@"deleteForward:"]) code = 2;
  else if ([s hasPrefix:@"moveLeft"]) code = 3;
  else if ([s hasPrefix:@"moveRight"]) code = 4;
  else if ([s hasPrefix:@"moveUp"]) code = 5;
  else if ([s hasPrefix:@"moveDown"]) code = 6;
  else if ([s isEqualToString:@"insertNewline:"]) code = 7;
  else if ([s isEqualToString:@"insertLineBreak:"] ||
           [s isEqualToString:@"insertNewlineIgnoringFieldEditor:"]) {
    code = 7;
    mods = 1;
  } else if ([s hasPrefix:@"moveToBeginningOfLine"] || [s hasPrefix:@"moveToBeginningOfDocument"]) code = 8;
  else if ([s hasPrefix:@"moveToEndOfLine"] || [s hasPrefix:@"moveToEndOfDocument"]) code = 9;
  else if ([s hasPrefix:@"scrollPageUp"] || [s hasPrefix:@"pageUp"]) code = 15;
  else if ([s hasPrefix:@"scrollPageDown"] || [s hasPrefix:@"pageDown"]) code = 16;
  if ([s containsString:@"AndModifySelection"]) mods |= 1;
  if (code == 7 && shift_down()) mods |= 1;
  if (code) mb_cb.key(code, mods);
}

// ---- NSTextInputClient ----

- (void)insertText:(id)string replacementRange:(NSRange)r {
  NSString *s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
  self.markedLen = 0;
  send_text(0, s, 0, 0);
}
- (void)setMarkedText:(id)string selectedRange:(NSRange)sel replacementRange:(NSRange)r {
  NSString *s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
  self.markedLen = s.length;
  if (s.length == 0) send_text(1, @"", 0, 0);
  else send_text(1, s, (int)sel.location, (int)sel.length);
}
- (void)unmarkText {
  self.markedLen = 0;
  send_text(2, @"", 0, 0);
}
- (BOOL)hasMarkedText { return self.markedLen > 0; }
- (NSRange)markedRange {
  return self.markedLen ? NSMakeRange(self.sel.location, self.markedLen) : NSMakeRange(NSNotFound, 0);
}
- (NSRange)selectedRange { return self.sel; }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)actual {
  NSString *m = self.mirror ?: @"";
  NSRange clipped = NSIntersectionRange(r, NSMakeRange(0, m.length));
  if (actual) *actual = clipped;
  return [[NSAttributedString alloc] initWithString:[m substringWithRange:clipped]];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return NSNotFound; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)actual {
  NSRect inWindow = [self convertRect:self.caretRect toView:nil];
  return [self.window convertRectToScreen:inWindow];
}

@end

// ---------------------------------------------------------------------------
// Scripted runs (MBUI_SCRIPT=ime): drives the same NSTextInputClient calls an
// input method makes, and saves snapshots, so it can run unattended.

static void shot(const char *name) {
  if (!shot_path) return;
  // the pages' pictures taken as they are now: the snapshot has them once they are in (ten seconds, else said)
  mb_views_snap_all();
  int i = 0;
  for (; i < 2000 && mb_views_snapping(); i++)
    [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
  if (mb_views_snapping()) {
    fprintf(stderr, "SETTLE FAIL: a page's picture not taken in 10 s\n");
    exit(3);
  }
  char p[1024];
  snprintf(p, sizeof p, "%s/%s.png", shot_path, name);
  int ok = mb_render_snapshot(p);
  fprintf(stdout, "SHOT %s %s\n", p, ok ? "ok" : "failed");
  fflush(stdout);
}

static void run_script_step(int step) {
  MBView *v = the_view;
  NSSize s = v.bounds.size;
  if (strcmp(script, "ime") == 0) {
    switch (step) {
      case 20: shot("01-start"); break;
      case 21:  // click the composer
        mb_cb.pointer(0, 120, s.height - 30, 0);
        mb_cb.pointer(2, 120, s.height - 30, 0);
        break;
      case 30:
        [v setMarkedText:@"ni'hao" selectedRange:NSMakeRange(6, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        break;
      case 40: shot("02-composing"); break;
      case 41: [v insertText:@"你好" replacementRange:NSMakeRange(NSNotFound, 0)]; break;
      case 42: [v insertText:@"，MoonBit " replacementRange:NSMakeRange(NSNotFound, 0)]; break;
      case 43:
        [v setMarkedText:@"shi'jie" selectedRange:NSMakeRange(3, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        break;
      case 50: shot("03-composing-2"); break;
      case 51: [v insertText:@"世界 👋" replacementRange:NSMakeRange(NSNotFound, 0)]; break;
      case 60: shot("04-typed"); break;
      case 61: [v doCommandBySelector:@selector(insertNewline:)]; break;
      case 100: shot("05-sent"); break;
      case 101:
        for (int i = 0; i < 40; i++) mb_cb.wheel(300, 300, 0, -120, 0);
        break;
      case 140: shot("06-scrolled"); break;
      case 141: exit(0);
    }
    script_next();
  } else if (strcmp(script, "books") == 0) {
    // the shelf, a book opened, the next page, then the reader's panels:
    // with a mouse the contents and the layout docked at the right; in a
    // phone's window the bars a tap in the middle brings, and the contents'
    // sheet
    int narrow = s.width < 700;
    switch (step) {
      case 30: shot("books-1-shelf"); break;
      case 31: {
        double x = narrow ? 70 : 110, y = narrow ? 200 : 220;
        mb_cb.pointer(0, x, y, 0); mb_cb.pointer(2, x, y, 0); break;
      }
      case 60: shot("books-2-page"); break;
      case 61: mb_cb.pointer(0, s.width - 30, 400, 0); mb_cb.pointer(2, s.width - 30, 400, 0); break;
      case 90: shot("books-3-next"); break;
      case 91:
        if (narrow) { mb_cb.pointer(0, s.width / 2, s.height / 2, 0); mb_cb.pointer(2, s.width / 2, s.height / 2, 0); }
        else { mb_cb.pointer(0, s.width - 62, 22, 0); mb_cb.pointer(2, s.width - 62, 22, 0); }
        break;
      case 120: shot(narrow ? "books-4-bars" : "books-4-contents"); break;
      case 121: {
        double x = narrow ? 81 : s.width - 28, y = narrow ? s.height - 45 : 22;
        mb_cb.pointer(0, x, y, 0); mb_cb.pointer(2, x, y, 0); break;
      }
      case 160: shot(narrow ? "books-5-contents" : "books-5-layout"); break;
      case 161: exit(0);
    }
    script_next();
  } else if (strcmp(script, "photos") == 0) {
    // decodes take a while: shots once they have had time; far down; back
    // up and a picture opened
    int narrow = s.width < 700;
    if (step == 120) shot("photos-1");
    if (step == 121) for (int i = 0; i < 30; i++) mb_cb.wheel(300, 300, 0, 200, 0);
    if (step == 220) shot("photos-2");
    if (step == 221) for (int i = 0; i < 60; i++) mb_cb.wheel(300, 300, 0, -200, 0);
    if (step == 260) {
      double x = narrow ? 50 : 110, y = narrow ? 150 : 200;
      mb_cb.pointer(0, x, y, 0); mb_cb.pointer(2, x, y, 0);
    }
    if (step == 340) shot("photos-3-viewer");
    if (step == 341) exit(0);
    script_next();
  } else if (strcmp(script, "kit") == 0) {
    // the demo's kit screen (MBUI_SCREEN=kit): the first page; scrolled, the next one pushed (the bar's button at its
    // right); swiped back from the left edge, held halfway; let go: the first page as it was left
    switch (step) {
      case 30: shot("kit-1-root"); break;
      // scrolled down first: back, it is where it was left
      case 31: mb_cb.wheel(200, 500, 0, 360, 0); break;
      case 40: mb_cb.pointer(0, s.width - 50, 26, 0); mb_cb.pointer(2, s.width - 50, 26, 0); break;
      case 80: shot("kit-2-pushed"); break;
      case 81: mb_cb.pointer(0, 5, 400, 0); break;
      case 120: shot("kit-3-swipe"); break;
      case 121: mb_cb.pointer(2, 5 + 10 * 20, 400, 0); break;
      case 170: shot("kit-4-back"); break;
      case 171: exit(0);
    }
    if (step > 81 && step <= 91) mb_cb.pointer(1, 5 + (step - 81) * 20, 400, 0);
    script_next();
  } else if (strcmp(script, "home") == 0) {
    // still.fail's Home (APP=sffix, made-up chats; or APP=stillfail): the list (at MBUI_SHOT_AT, 30 by default: later
    // for the core's first answers); the workspaces' sheet from the name; closed, the first row tapped: its chat
    // pushed; swiped back from the left edge, held halfway. MBUI_HOME_READONLY=1 stops before the row (a real
    // account's chats are not opened).
    static int at = -1;
    if (at < 0) at = getenv("MBUI_SHOT_AT") ? atoi(getenv("MBUI_SHOT_AT")) : 30;
    int k = step - at;
    switch (k) {
      case 0: shot("home-1"); break;
      case 1: mb_cb.pointer(0, 110, 25, 0); mb_cb.pointer(2, 110, 25, 0); break;
      case 30: shot("home-2-workspaces"); break;
      case 31: mb_cb.pointer(0, s.width / 2, 80, 0); mb_cb.pointer(2, s.width / 2, 80, 0); break;
      case 40:
        if (getenv("MBUI_HOME_READONLY")) exit(0);
        mb_cb.pointer(0, s.width / 2, 176, 0); mb_cb.pointer(2, s.width / 2, 176, 0);
        break;
      case 80: shot("home-3-chat"); break;
      case 81: mb_cb.pointer(0, 5, 400, 0); break;
      case 120: shot("home-4-swipe"); break;
      case 121: mb_cb.pointer(2, 5 + 10 * 20, 400, 0); break;
      case 170: shot("home-5-back"); break;
      case 171: exit(0);
    }
    if (k > 81 && k <= 91) mb_cb.pointer(1, 5 + (k - 81) * 20, 400, 0);
    script_next();
  } else if (strcmp(script, "chat") == 0) {
    // a chat (APP=sffix MBUI_FIXTURE=chat, or APP=stillfail with MBUI_OPEN_CHAT): as it opens (at MBUI_SHOT_AT, 30 by
    // default: later for the core's first answers), then scrolled up MBUI_CHAT_UP points (900 by default), then
    // more by as much again (the page before coming in as the top nears)
    static int at = -1, up = -1;
    if (at < 0) at = getenv("MBUI_SHOT_AT") ? atoi(getenv("MBUI_SHOT_AT")) : 30;
    if (up < 0) up = getenv("MBUI_CHAT_UP") ? atoi(getenv("MBUI_CHAT_UP")) : 900;
    int k = step - at;
    switch (k) {
      case 0: shot("chat-1"); break;
      case 1: for (int i = 0; i < up / 100; i++) mb_cb.wheel(s.width / 2, s.height / 2, 0, -100, 0); break;
      case 60: shot("chat-2-up"); break;
      case 61: for (int i = 0; i < up / 100; i++) mb_cb.wheel(s.width / 2, s.height / 2, 0, -100, 0); break;
      case 160: shot("chat-3-up"); break;
      case 161: exit(0);
    }
    script_next();
  } else if (strcmp(script, "compose") == 0) {
    // still.fail's composer (APP=sffix MBUI_FIXTURE=chat, a phone's window): the field tapped, Chinese composed through
    // the input method's calls and committed, a new line (Enter), more words; ＋'s sheet; 文件 picked (MBUI_PICK_FILES
    // answers the open panel), up at once to the fixture's station; sent; the fixture's answer.
    // MBUI_SHOT_AT moves it all later (a real chat opened by the core: its first answers)
    static int at = -1;
    if (at < 0) at = getenv("MBUI_SHOT_AT") ? atoi(getenv("MBUI_SHOT_AT")) : 30;
    double fx = s.width / 2, by = s.height - 10 - 8 - 18;
    switch (step - at + 30) {
      case 30: mb_cb.pointer(0, fx, by, 0); mb_cb.pointer(2, fx, by, 0); break;
      case 40:
        [v setMarkedText:@"fa'bu" selectedRange:NSMakeRange(5, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        break;
      case 45: shot("compose-1-composing"); break;
      case 46: [v insertText:@"发布前" replacementRange:NSMakeRange(NSNotFound, 0)]; break;
      case 47: [v insertText:@"再看一眼" replacementRange:NSMakeRange(NSNotFound, 0)]; break;
      case 48: [v doCommandBySelector:@selector(insertNewline:)]; break;
      case 49: [v insertText:@"日志在附件里" replacementRange:NSMakeRange(NSNotFound, 0)]; break;
      case 60: shot("compose-2-typed"); break;
      case 61: mb_cb.pointer(0, 36, by, 0); mb_cb.pointer(2, 36, by, 0); break;
      case 90: shot("compose-3-sheet"); break;
      case 91: mb_cb.pointer(0, s.width / 2, s.height - 79, 0); mb_cb.pointer(2, s.width / 2, s.height - 79, 0); break;
      case 140: shot("compose-4-picked"); break;
      case 141: mb_cb.pointer(0, s.width - 36, by, 0); mb_cb.pointer(2, s.width - 36, by, 0); break;
      case 150: shot("compose-5-sending"); break;
      case 320: shot("compose-6-answered"); break;
      case 321: exit(0);
    }
    script_next();
  } else if (strcmp(script, "shot") == 0) {
    // a stable run: the frame at a declared moment on its own clock (MBUI_SHOT_MS, 1000 by default: the frames 1/60 s
    // apart from 0, the clock still while the app awaits the host, above), as web/host.js's shot_at and Android's
    // SHOT_AT; or at frame MBUI_SHOT_AT where a script says a frame. Never "once the app is at rest": that is settling by
    // another name (a moment is declared, or the page's own named event waited for by a drive). Not stable: at frame
    // MBUI_SHOT_AT (30)
    static int at;
    static double at_ms = -1;
    if (!at) at = getenv("MBUI_SHOT_AT") ? atoi(getenv("MBUI_SHOT_AT")) : settle ? -1 : 30;
    if (at_ms < 0) {
      const char *ms = getenv("MBUI_SHOT_MS");
      char *end = NULL;
      at_ms = ms ? strtod(ms, &end) : 1000;
      if (ms && (end == ms || *end || at_ms < 0)) {
        fprintf(stderr, "SHOT FAIL: MBUI_SHOT_MS is a moment in ms on the run's clock, not \"%s\"\n", ms);
        exit(3);
      }
    }
    if (settle) {
      if (at > 0 ? step >= at : settle_clock >= at_ms) {
        fprintf(stderr, "SHOT %d %g\n", step, settle_clock);
        shot(getenv("MBUI_SHOT_NAME") ?: "main");
        exit(0);
      }
    } else {
      if (step == at) shot(getenv("MBUI_SHOT_NAME") ?: "main");
      if (step == at + 1) exit(0);
    }
    script_next();
  }
}

// The window's buttons in the app's top row (an inset window): 16 from its left, centred on its 44, as still.fail's
// desktop app has them (Electron's trafficLightPosition {16, 15}); placed again as the window resizes.
static void place_buttons(NSWindow *w) {
  NSButton *close = [w standardWindowButton:NSWindowCloseButton];
  NSButton *mini = [w standardWindowButton:NSWindowMiniaturizeButton];
  NSButton *zoom = [w standardWindowButton:NSWindowZoomButton];
  NSView *bar = close.superview.superview;
  if (!close || !bar || (w.styleMask & NSWindowStyleMaskFullScreen)) return;
  double bh = close.frame.size.height, gap = mini.frame.origin.x - close.frame.origin.x;
  double h = bh + 2 * 15.0;
  NSRect f = bar.frame;
  f.size.height = h;
  f.origin.y = w.frame.size.height - h;
  bar.frame = f;
  NSArray<NSButton *> *bs = @[ close, mini, zoom ];
  for (NSUInteger i = 0; i < bs.count; i++) {
    NSRect b = bs[i].frame;
    b.origin.x = 16.0 + i * gap;
    b.origin.y = (h - bh) / 2.0;
    bs[i].frame = b;
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

// The window as the app wants it, asked before `run` (@hostapi.window_setup).
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  setup_min_w = min_w;
  setup_min_h = min_h;
  setup_w = w;
  setup_h = h;
  setup_inset = inset;
}

// Whether the window's buttons are in the app's top row now (an inset window, not full screen).
int32_t mb_host_window_inset(void) {
  NSWindow *w = the_view.window;
  return setup_inset && w && !(w.styleMask & NSWindowStyleMaskFullScreen) ? 1 : 0;
}

// Whether the window fills the screen now (@hostapi.full_screen), and made to or back (as its green button does).
int32_t mb_host_full_screen(void) {
  NSWindow *w = the_view.window;
  return w && (w.styleMask & NSWindowStyleMaskFullScreen) ? 1 : 0;
}

void mb_host_set_full_screen(int32_t on) {
  NSWindow *w = the_view.window;
  if (w && (on != 0) != ((w.styleMask & NSWindowStyleMaskFullScreen) != 0)) [w toggleFullScreen:nil];
}

// The press under way drags the window (the app's top row: @hostapi.window_drag); twice, what the system's title bar
// does on a double click (zoom, minimize or nothing, as set in the system's settings).
void mb_host_window_drag(void) {
  NSWindow *w = the_view.window;
  NSEvent *e = down_event;
  if (!w || !e) return;
  if (e.clickCount >= 2) {
    NSString *act = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleActionOnDoubleClick"];
    if ([act isEqualToString:@"Minimize"]) [w performMiniaturize:nil];
    else if (![act isEqualToString:@"None"]) [w performZoom:nil];
    return;
  }
  [w performWindowDragWithEvent:e];
}

// The desktop's dock (@hostapi.dock_send; apps/desktop/dock, docs/desktop-dock.md): the SwiftUI helper the desktop
// app carries (Resources/dock/StillfailDock; MBUI_DOCK: one built elsewhere), on macOS 14 or later on Apple silicon.
// Started by the first line sent, a JSON object a line on its stdin; what it says, a line each, posted on the "dock"
// channel, and {"type":"gone"} when it ends. Its settings are kept here, as the desktop app keeps them in a file of
// its own (@hostapi.dock_kept, dock_keep).
static NSTask *dock_task = nil;
static NSFileHandle *dock_in = nil;
static NSString *dock_helper(void) {
#if defined(__arm64__)
  if (@available(macOS 14, *)) {
    const char *own = getenv("MBUI_DOCK");
    NSString *p = own ? @(own) : [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"dock/StillfailDock"];
    return [NSFileManager.defaultManager isExecutableFileAtPath:p] ? p : nil;
  }
#endif
  return nil;
}
int32_t mb_host_dock_available(void) { return dock_helper() ? 1 : 0; }

// The keys held now (@hostapi.mods_held), as a key's are told: shift 1, control 2, option 4, command 8.
int32_t mb_host_mods_held(void) {
  NSEventModifierFlags m = [NSEvent modifierFlags];
  return ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
         ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
}
static void dock_heard(NSData *line) {
  if (!line.length) return;
  // a chat opened from it: the app's window in front, as the desktop app's (app.focus)
  NSString *s = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
  if ([s containsString:@"\"type\":\"open\""]) {
    dispatch_async(dispatch_get_main_queue(), ^{ bring_back(); });
  }
  mb_post("dock", (const char *)line.bytes, line.length, NULL, 0);
}
static BOOL dock_spawn(void) {
  NSString *path = dock_helper();
  if (!path) return NO;
  // (a write to a helper that has gone is an error, not the app's end)
  signal(SIGPIPE, SIG_IGN);
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:path];
  NSPipe *in = [NSPipe pipe], *out = [NSPipe pipe];
  t.standardInput = in;
  t.standardOutput = out;
  t.standardError = [NSFileHandle fileHandleWithNullDevice];
  NSMutableData *buf = [NSMutableData data];
  out.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    if (d.length == 0) {
      h.readabilityHandler = nil;
      return;
    }
    [buf appendData:d];
    for (;;) {
      NSRange nl = [buf rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buf.length)];
      if (nl.location == NSNotFound) break;
      dock_heard([buf subdataWithRange:NSMakeRange(0, nl.location)]);
      [buf replaceBytesInRange:NSMakeRange(0, nl.location + 1) withBytes:NULL length:0];
    }
  };
  t.terminationHandler = ^(NSTask *task) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (dock_task != task) return;
      dock_task = nil;
      dock_in = nil;
      dock_heard([@"{\"type\":\"gone\"}" dataUsingEncoding:NSUTF8StringEncoding]);
    });
  };
  NSError *e = nil;
  if (![t launchAndReturnError:&e]) return NO;
  dock_task = t;
  dock_in = in.fileHandleForWriting;
  return YES;
}
void mb_host_dock_send(moonbit_string_t line) {
  if (!dock_task && !dock_spawn()) return;
  NSData *d = [[mb_ns_from_string(line) stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  NSError *e = nil;
  if (@available(macOS 10.15, *)) [dock_in writeData:d error:&e];
}
void mb_host_dock_stop(void) {
  if (!dock_task) return;
  NSTask *t = dock_task;
  dock_task = nil;
  [dock_in closeFile];
  dock_in = nil;
  [t terminate];
}
moonbit_string_t mb_host_dock_kept(void) {
  NSString *s = [NSUserDefaults.standardUserDefaults stringForKey:@"fail.still.mbui.dock"];
  return mb_string_from_ns(s ?: @"");
}
void mb_host_dock_keep(moonbit_string_t json) {
  [NSUserDefaults.standardUserDefaults setObject:mb_ns_from_string(json) forKey:@"fail.still.mbui.dock"];
}

// This machine's station (@hostapi.local_station; apps/desktop/src/main.ts localStation, installed.ts): its data
// (~/.stillfail), whether it runs (run/station.json's pid alive) and by what (a launchd service the installer made, or a
// process started by hand), its release, the workspace its data is in; what is being done to it and what went wrong
// last. "" where there is neither data nor a service. Its acts (@hostapi.local_station_act) run off the main thread:
// start, stop, restart (the service's launchctl, a hand-started one only stopped), the log or the folder opened.
static NSString *local_doing = nil;
static NSString *local_failed = nil;
static int local_percent = -1;   // how far the installer's download is (local_heard, below), -1 not said
static NSString *local_said = nil; // the last step the installer said
static NSString *local_data(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@".stillfail"]; }
static NSString *local_service(void) {
  for (NSString *label in @[ @"fail.still.station", @"org.3720.ember.station" ]) {
    NSString *plist = [NSString stringWithFormat:@"%@/Library/LaunchAgents/%@.plist", NSHomeDirectory(), label];
    if ([NSFileManager.defaultManager fileExistsAtPath:plist]) return label;
  }
  return nil;
}
static NSDictionary *local_json(NSString *path) {
  NSData *d = [NSData dataWithContentsOfFile:path];
  if (!d) return nil;
  id v = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
  return [v isKindOfClass:NSDictionary.class] ? v : nil;
}
static pid_t local_pid(NSString *data, NSString **version) {
  NSDictionary *s = local_json([data stringByAppendingPathComponent:@"run/station.json"]);
  id pid = s[@"pid"];
  if (![pid isKindOfClass:NSNumber.class] || [pid intValue] <= 0) return 0;
  if (kill([pid intValue], 0) != 0 && errno != EPERM) return 0;
  if ([s[@"version"] isKindOfClass:NSString.class]) *version = s[@"version"];
  return [pid intValue];
}
moonbit_string_t mb_host_local_station(void) {
  NSString *data = local_data();
  NSString *service = local_service();
  BOOL there = [NSFileManager.defaultManager fileExistsAtPath:data];
  // none here, and nothing being done or gone wrong about it: ""; one being installed is said before it is there
  if (!there && !service && !local_doing && !local_failed) return mb_string_from_ns(@"");
  NSString *version = nil;
  pid_t pid = local_pid(data, &version);
  NSMutableDictionary *o = [NSMutableDictionary dictionary];
  if (there || service) o[@"data"] = [data stringByAbbreviatingWithTildeInPath];
  o[@"runner"] = pid == 0 ? @"none" : service ? @"service" : @"other";
  if (!version && service) {
    NSString *build = [NSString stringWithContentsOfFile:[data stringByAppendingPathComponent:@"app/BUILD"] encoding:NSUTF8StringEncoding error:nil];
    build = [build stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (build.length) version = [@"0.1." stringByAppendingString:build];
  }
  if (version) o[@"version"] = version;
  if (service) o[@"service"] = @{ @"kind" : @"launchd", @"name" : service };
  NSDictionary *c = local_json([data stringByAppendingPathComponent:@"mesh/cloud.json"]);
  if ([c[@"workspace"] isKindOfClass:NSString.class] && [c[@"workspace"] length]) {
    NSMutableDictionary *w = [NSMutableDictionary dictionaryWithObject:c[@"workspace"] forKey:@"id"];
    for (NSString *k in @[ @"workspace_name", @"station", @"name" ]) {
      if ([c[k] isKindOfClass:NSString.class] && [c[k] length]) w[[k isEqualToString:@"workspace_name"] ? @"name" : [k isEqualToString:@"name"] ? @"stationName" : k] = c[k];
    }
    w[@"removed"] = @(c[@"removed_at"] != nil && c[@"removed_at"] != NSNull.null);
    o[@"workspace"] = w;
  }
  if (local_doing) {
    o[@"doing"] = local_doing;
    if (local_percent >= 0) o[@"percent"] = @(local_percent);
    if (local_said) o[@"said"] = local_said;
  }
  if (local_failed) o[@"failed"] = local_failed;
  NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
  return mb_string_from_ns(json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"");
}
// launchctl with these arguments: nil when it did, else what it said last.
static NSString *local_launchctl(NSArray<NSString *> *args) {
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
  t.arguments = args;
  NSPipe *out = [NSPipe pipe];
  t.standardOutput = out;
  t.standardError = out;
  NSError *e = nil;
  if (![t launchAndReturnError:&e]) return e.localizedDescription ?: @"launchctl";
  NSData *said = [out.fileHandleForReading readDataToEndOfFile];
  [t waitUntilExit];
  if (t.terminationStatus == 0) return nil;
  NSString *s = [[NSString alloc] initWithData:said encoding:NSUTF8StringEncoding] ?: @"";
  s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return s.length ? s : [NSString stringWithFormat:@"launchctl %d", t.terminationStatus];
}
// The person's login shell's PATH and proxy variables, read once (as still.fail's desktop app reads them: station.ts
// ofShell): an app opened from the Finder or the Dock has neither, and the station the installer sets up runs with the
// PATH it is installed from (where the agents are found: nvm's Node, Homebrew's). A shell that does not answer in 5 s
// gives nothing.
static NSDictionary<NSString *, NSString *> *login_env(void) {
  static NSDictionary *env;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *shell = NSProcessInfo.processInfo.environment[@"SHELL"];
    if (!shell.length) {
      struct passwd *pw = getpwuid(getuid());
      shell = pw && pw->pw_shell ? @(pw->pw_shell) : @"/bin/zsh";
    }
    NSString *mark = @"__stillfail_env__";
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:shell];
    t.arguments = @[ @"-ilc", [NSString stringWithFormat:@"printf '%@'; env; printf '%@'", mark, mark] ];
    t.standardInput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSPipe *out = [NSPipe pipe];
    t.standardOutput = out;
    NSMutableDictionary *got = [NSMutableDictionary dictionary];
    if ([t launchAndReturnError:nil]) {
      dispatch_semaphore_t done = dispatch_semaphore_create(0);
      __block NSData *said = nil;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        said = [out.fileHandleForReading readDataToEndOfFile];
        dispatch_semaphore_signal(done);
      });
      if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
        [t terminate];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
      }
      NSString *s = [[NSString alloc] initWithData:said ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
      NSArray<NSString *> *parts = [s componentsSeparatedByString:mark];
      if (parts.count >= 3) {
        for (NSString *line in [parts[1] componentsSeparatedByString:@"\n"]) {
          NSRange eq = [line rangeOfString:@"="];
          if (eq.location == NSNotFound) continue;
          NSString *k = [line substringToIndex:eq.location];
          if ([k isEqualToString:@"PATH"] || [k.lowercaseString hasSuffix:@"_proxy"])
            got[k] = [line substringFromIndex:eq.location + 1];
        }
      }
    }
    env = got;
  });
  return env;
}

// The station's installer (still.fail cloud's /install.sh, as 添加 station hands it out and still.fail's desktop app
// runs it: cloud/src/install.ts), run here as the person would in a terminal (their shell's PATH and proxies): with a
// token (`install`: one-time, for a workspace: the core's workspace.enroll) it downloads the release, puts it in
// ~/.stillfail/app, joins the workspace and runs the station as a launchd service; without one (`update`) it brings the
// station here up to the latest release and runs it as a service (a station's data with none, as the desktop app ran
// it, becomes one). `ask`: {"origin", "token"?, "channel": stable | beta}. nil when it did, else the last it said.
// How far it is, as it goes (local_station's `percent` and `said`): the percent its downloads' curl shows
// (--progress-bar: "#### 45.2%", each redrawn after a \r), and the last other line it said (its step: downloading,
// installing, starting): local_percent, local_said (above).

static void local_heard(NSData *piece) {
  NSString *s = [[NSString alloc] initWithData:piece encoding:NSUTF8StringEncoding];
  s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!s.length) return;
  static NSRegularExpression *bar;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ bar = [NSRegularExpression regularExpressionWithPattern:@"^#*\\s*([0-9]+(\\.[0-9]+)?)%$" options:0 error:nil]; });
  NSTextCheckingResult *m = [bar firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
  int percent = m ? [[s substringWithRange:[m rangeAtIndex:1]] intValue] : -1;
  if (!m && [s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"#"] invertedSet]].location == NSNotFound) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (m) {
      local_percent = percent;
    } else {
      local_said = s;
      local_percent = -1;
    }
    [the_view requestFrame];
  });
}

static NSString *local_install(NSDictionary *ask) {
  NSString *origin = [ask[@"origin"] isKindOfClass:NSString.class] ? ask[@"origin"] : @"";
  if (![origin hasPrefix:@"https://"] && ![origin hasPrefix:@"http://"]) return @"origin";
  NSMutableArray *args = [@[
    @"-c",
    @"f=$(mktemp) && curl -fsSL \"$0/install.sh\" -o \"$f\" && sh \"$f\" \"$@\"; s=$?; rm -f \"$f\"; exit $s",
    origin
  ] mutableCopy];
  if ([ask[@"token"] isKindOfClass:NSString.class] && [ask[@"token"] length]) [args addObject:ask[@"token"]];
  NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
  [env addEntriesFromDictionary:login_env()];
  if ([ask[@"channel"] isEqual:@"beta"]) env[@"STILLFAIL_CHANNEL"] = @"beta";
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
  t.arguments = args;
  t.environment = env;
  t.standardInput = [NSFileHandle fileHandleWithNullDevice];
  NSPipe *out = [NSPipe pipe];
  t.standardOutput = out;
  t.standardError = out;
  NSError *e = nil;
  if (![t launchAndReturnError:&e]) return e.localizedDescription ?: @"sh";
  // what it says as it says it: each piece ended by a \r (curl's bar redrawn) or a \n heard (local_heard)
  NSMutableData *said = [NSMutableData data];
  NSUInteger from = 0;
  for (;;) {
    NSData *d = [out.fileHandleForReading availableData];
    if (d.length == 0) break;
    [said appendData:d];
    const uint8_t *b = (const uint8_t *)said.bytes;
    for (NSUInteger i = from; i < said.length; i++) {
      if (b[i] != '\r' && b[i] != '\n') continue;
      local_heard([said subdataWithRange:NSMakeRange(from, i - from)]);
      from = i + 1;
    }
  }
  [t waitUntilExit];
  NSString *s = [[NSString alloc] initWithData:said encoding:NSUTF8StringEncoding] ?: @"";
  fprintf(stdout, "mac: the station's installer (%s) exited %d\n%s\n", ask[@"token"] ? "install" : "update",
          t.terminationStatus, s.UTF8String);
  fflush(stdout);
  if (t.terminationStatus == 0) return nil;
  NSString *last = @"";
  for (NSString *line in [s componentsSeparatedByString:@"\n"]) {
    NSString *l = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (l.length) last = l;
  }
  return last.length ? last : [NSString stringWithFormat:@"install.sh %d", t.terminationStatus];
}

void mb_host_local_station_act(moonbit_string_t action) {
  NSString *a = mb_ns_from_string(action);
  NSString *data = local_data();
  // `install {…}`, `update {…}`: the installer (local_install), off the main thread, as the others
  NSRange space = [a rangeOfString:@" "];
  if (space.location != NSNotFound && ([a hasPrefix:@"install "] || [a hasPrefix:@"update "])) {
    NSString *verb = [a substringToIndex:space.location];
    NSData *j = [[a substringFromIndex:space.location + 1] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *ask = j ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    if (![ask isKindOfClass:NSDictionary.class]) return;
    if (local_doing) {
      local_failed = @"busy";
      [the_view requestFrame];
      return;
    }
    local_doing = verb;
    local_failed = nil;
    local_percent = -1;
    local_said = nil;
    [the_view requestFrame];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSString *failed = local_install(ask);
      dispatch_async(dispatch_get_main_queue(), ^{
        local_doing = nil;
        local_failed = failed;
        [the_view requestFrame];
      });
    });
    return;
  }
  if ([a isEqualToString:@"log"]) {
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:[data stringByAppendingPathComponent:@"stillfail.log"]]];
    return;
  }
  if ([a isEqualToString:@"folder"]) {
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:data]];
    return;
  }
  if (![@[ @"start", @"stop", @"restart" ] containsObject:a]) return;
  if (local_doing) {
    local_failed = @"busy";
    [the_view requestFrame];
    return;
  }
  local_doing = a;
  local_failed = nil;
  [the_view requestFrame];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *failed = nil;
    NSString *service = local_service();
    NSString *version = nil;
    pid_t pid = local_pid(data, &version);
    if (service) {
      NSString *domain = [NSString stringWithFormat:@"gui/%d", getuid()];
      NSString *target = [NSString stringWithFormat:@"%@/%@", domain, service];
      if ([a isEqualToString:@"stop"]) {
        failed = local_launchctl(@[ @"bootout", target ]);
      } else if (local_launchctl([a isEqualToString:@"restart"] ? @[ @"kickstart", @"-k", target ] : @[ @"kickstart", target ])) {
        // not loaded (stopped here, or never since login): loaded, which starts it (RunAtLoad)
        NSString *plist = [NSString stringWithFormat:@"%@/Library/LaunchAgents/%@.plist", NSHomeDirectory(), service];
        failed = local_launchctl(@[ @"bootstrap", domain, plist ]);
      }
    } else if (pid != 0) {
      // started by hand (`stillfail start`): only stopped from here, it has nothing to start it again
      if ([a isEqualToString:@"stop"]) {
        if (kill(pid, SIGTERM) != 0) failed = [NSString stringWithUTF8String:strerror(errno)];
      } else {
        failed = @"byHand";
      }
    } else {
      failed = @"noService";
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      local_doing = nil;
      local_failed = failed;
      [the_view requestFrame];
    });
  });
}

// The number on the Dock's tile (@hostapi.set_badge): what waits for the person; 0 none.
void mb_host_set_badge(int32_t n) {
  NSString *label = n > 0 ? [NSString stringWithFormat:@"%d", n] : nil;
  if ([NSThread isMainThread]) {
    NSApp.dockTile.badgeLabel = label;
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{ NSApp.dockTile.badgeLabel = label; });
  }
}

// The pointer's shape (@hostapi.set_cursor): 0 the arrow, 1 a hand, 2 the I-beam, 3 and 4 resizing sideways and up and
// down, 5 an open hand.
void mb_host_set_cursor(int32_t kind) {
  cursor_kind = kind;
  [cursor_of(kind) set];
}

// ---- The app's life on the Mac, and what the system says of it ----
// As still.fail's desktop app is on macOS (Electron's): closing the window puts it away and the app goes on (its core,
// its notifications, the Dock's badge, the dock's helper); the Dock's icon clicked, the app opened again, a
// notification or the dock's helper opening a chat brings it back; ⌘Q (the menu bar's 退出) quits. A program run bare
// (not an app's bundle: a developer's run, a script's, a test's) ends as its window closes, as before. Said to the app
// on the system's channel (hostapi's system.mbt): `shown` with how long it was away as the window comes back, and as
// the Mac wakes from sleep (a clock that counts the sleep, as iOS's and Android's); `network` as the default network
// becomes another one (Network's path monitor, as iOS's); `menu` as one of the app's items in the menu bar is chosen.

static void say_system(NSDictionary *said) {
  NSData *json = [NSJSONSerialization dataWithJSONObject:said options:0 error:NULL];
  if (json) mb_post("system", (const char *)json.bytes, json.length, NULL, 0);
}

static BOOL in_bundle(void) {
  NSBundle *b = NSBundle.mainBundle;
  return b.bundleIdentifier && [b.bundlePath.pathExtension isEqualToString:@"app"];
}

static uint64_t put_away_at;  // CLOCK_MONOTONIC's ns as the window was closed (0: it is out)
static uint64_t asleep_at;    // as the Mac went to sleep (0: awake)

static void say_shown(uint64_t since) {
  double away = (clock_gettime_nsec_np(CLOCK_MONOTONIC) - since) / 1e6;
  say_system(@{@"shown" : @{@"away" : @(away)}});
}

static void bring_back(void) {
  NSWindow *w = the_view.window;
  if (!w) return;
  if (w.isMiniaturized) [w deminiaturize:nil];
  [w makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  if (put_away_at) {
    say_shown(put_away_at);
    put_away_at = 0;
  }
}

@interface MBAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
@implementation MBAppDelegate
- (BOOL)windowShouldClose:(NSWindow *)w {
  if (!in_bundle()) return YES;
  [w orderOut:nil];
  if (!put_away_at) put_away_at = clock_gettime_nsec_np(CLOCK_MONOTONIC);
  return NO;
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
  bring_back();
  return NO;
}
// a link of one of the schemes its Info.plist names (CFBundleURLTypes) opened, the app started by it or brought back:
// to the app (the system's `link`), its window out
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
  for (NSURL *u in urls) {
    if (!u.absoluteString.length) continue;
    fprintf(stdout, "mac: opened with a link (%s://)\n", u.scheme.UTF8String ?: "");
    fflush(stdout);
    say_system(@{@"link" : u.absoluteString});
  }
  bring_back();
}
// one of the app's items in the menu bar (mb_host_menu_setup)
- (void)menuChosen:(NSMenuItem *)item {
  if ([item.representedObject isKindOfClass:NSString.class]) say_system(@{@"menu" : item.representedObject});
}
@end
static MBAppDelegate *app_delegate;

// The default network as it changes: another one than before (Wi-Fi to a cable, back online after none), not the
// first seen (ios_app.m's network_start)
static nw_path_monitor_t network_monitor;
static void network_start(void) {
  network_monitor = nw_path_monitor_create();
  nw_path_monitor_set_queue(network_monitor, dispatch_get_main_queue());
  static NSString *was;
  nw_path_monitor_set_update_handler(network_monitor, ^(nw_path_t path) {
    NSMutableString *now = [NSMutableString string];
    if (nw_path_get_status(path) == nw_path_status_satisfied) {
      nw_path_enumerate_interfaces(path, ^bool(nw_interface_t i) {
        [now appendFormat:@"%s/%d", nw_interface_get_name(i), (int)nw_interface_get_type(i)];
        return false;  // the first: the one used
      });
    }
    BOOL changed = was && ![was isEqualToString:now] && now.length > 0;
    was = now;
    if (changed) {
      fprintf(stdout, "mac: network now %s\n", now.UTF8String);
      fflush(stdout);
      say_system(@{@"network" : @YES});
    }
  });
  nw_path_monitor_start(network_monitor);
}

// The Mac asleep and awake again: how long, to the app (a sleep whose start was not seen is taken as a minute's, as
// the desktop app's followSleep)
static void watch_sleep(void) {
  NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
  [ws addObserverForName:NSWorkspaceWillSleepNotification object:nil queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *n) { asleep_at = clock_gettime_nsec_np(CLOCK_MONOTONIC); }];
  [ws addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *n) {
                say_shown(asleep_at ? asleep_at : clock_gettime_nsec_np(CLOCK_MONOTONIC) - 60000000000ull);
                asleep_at = 0;
              }];
}

// ---- The menu bar (@hostapi.menu_setup) ----
// The app's menus with its words: the system's items by their role (their actions AppKit's, or the view's for the
// editing ones: MBView's cut: …), with the keys macOS gives them; the app's own said back on the system's channel.
static NSMenuItem *menu_item(NSDictionary *it) {
  if (![it isKindOfClass:NSDictionary.class] || [it[@"separator"] isEqual:@YES]) return [NSMenuItem separatorItem];
  // (`{app}` in its words: the app's name, as the system shows it)
  NSString *title = [it[@"title"] isKindOfClass:NSString.class] ? it[@"title"] : @"";
  title = [title stringByReplacingOccurrencesOfString:@"{app}"
                                           withString:NSRunningApplication.currentApplication.localizedName ?: @""];
  NSString *role = it[@"role"], *action = it[@"action"];
  NSEventModifierFlags cmd = NSEventModifierFlagCommand;
  // role: its action, its key, the modifiers with it
  NSDictionary<NSString *, NSArray *> *roles = @{
    @"about" : @[ @"orderFrontStandardAboutPanel:", @"", @0 ],
    @"hide" : @[ @"hide:", @"h", @(cmd) ],
    @"hideOthers" : @[ @"hideOtherApplications:", @"h", @(cmd | NSEventModifierFlagOption) ],
    @"showAll" : @[ @"unhideAllApplications:", @"", @0 ],
    @"quit" : @[ @"terminate:", @"q", @(cmd) ],
    @"undo" : @[ @"undo:", @"z", @(cmd) ],
    @"redo" : @[ @"redo:", @"z", @(cmd | NSEventModifierFlagShift) ],
    @"cut" : @[ @"cut:", @"x", @(cmd) ],
    @"copy" : @[ @"copy:", @"c", @(cmd) ],
    @"paste" : @[ @"paste:", @"v", @(cmd) ],
    @"selectAll" : @[ @"selectAll:", @"a", @(cmd) ],
    @"close" : @[ @"performClose:", @"w", @(cmd) ],
    @"minimize" : @[ @"performMiniaturize:", @"m", @(cmd) ],
    @"zoom" : @[ @"performZoom:", @"", @0 ],
    @"fullScreen" : @[ @"toggleFullScreen:", @"f", @(cmd | NSEventModifierFlagControl) ],
    @"front" : @[ @"arrangeInFront:", @"", @0 ],
  };
  if ([role isKindOfClass:NSString.class] && [role isEqualToString:@"services"]) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.submenu = [[NSMenu alloc] initWithTitle:title];
    NSApp.servicesMenu = item.submenu;
    return item;
  }
  NSArray *r = [role isKindOfClass:NSString.class] ? roles[role] : nil;
  if (r) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:NSSelectorFromString(r[0]) keyEquivalent:r[1]];
    item.keyEquivalentModifierMask = [r[2] unsignedIntegerValue];
    return item;
  }
  // (to whoever takes it: the app's delegate, last of those asked)
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(menuChosen:) keyEquivalent:@""];
  item.representedObject = [action isKindOfClass:NSString.class] ? action : @"";
  return item;
}

void mb_host_menu_setup(moonbit_string_t json_s) {
  [NSApplication sharedApplication];
  NSData *d = [mb_ns_from_string(json_s) dataUsingEncoding:NSUTF8StringEncoding];
  NSArray *menus = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
  if (![menus isKindOfClass:NSArray.class]) return;
  NSMenu *bar = [NSMenu new];
  for (NSDictionary *m in menus) {
    if (![m isKindOfClass:NSDictionary.class]) continue;
    NSString *title = [m[@"title"] isKindOfClass:NSString.class] ? m[@"title"] : @"";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    if ([m[@"items"] isKindOfClass:NSArray.class])
      for (NSDictionary *it in m[@"items"]) [menu addItem:menu_item(it)];
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    top.submenu = menu;
    [bar addItem:top];
    // the window menu: the system's list of windows in it
    if ([m[@"role"] isEqual:@"window"]) NSApp.windowsMenu = menu;
  }
  NSApp.mainMenu = bar;
}

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer,
                 mb_wheel_fn wheel, mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer, wheel, key, text};
  shot_path = getenv("MBUI_SHOT_DIR");
  script = getenv("MBUI_SCRIPT");
  settle = settled_run();
  record_dir = getenv("MBUI_RECORD");
  if (getenv("MBUI_RECORD_FROM")) record_from = atoi(getenv("MBUI_RECORD_FROM"));
  if (getenv("MBUI_RECORD_FRAMES")) record_frames = atoi(getenv("MBUI_RECORD_FRAMES"));
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    // the app's life (put away as its window closes, back from the Dock) and its menu bar's items: MBAppDelegate
    if (!app_delegate) app_delegate = [MBAppDelegate new];
    NSApp.delegate = app_delegate;
    notice_start();
    // MBUI_WIN=<w>x<h>: the window's size (a phone's, for the narrow layouts)
    // (else the app's own, @hostapi.window_setup; else 900×720)
    double ww = setup_w > 0 ? setup_w : 900, wh = setup_h > 0 ? setup_h : 720;
    const char *win = getenv("MBUI_WIN");
    if (win) sscanf(win, "%lfx%lf", &ww, &wh);
    NSRect r = NSMakeRect(120, 120, ww, wh);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable;
    if (setup_inset) style |= NSWindowStyleMaskFullSizeContentView;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
    w.title = mb_ns_from_string(title);
    if (setup_min_w > 0 || setup_min_h > 0) w.contentMinSize = NSMakeSize(setup_min_w, setup_min_h);
    if (!win && setup_w > 0) [w center];
    if (setup_inset) {
      // no title bar of the system's: the app's top row is it (the buttons in it, its drag: @hostapi.window_drag)
      w.titlebarAppearsTransparent = YES;
      w.titleVisibility = NSWindowTitleHidden;
    }
    // MBUI_SAFE: the bars' bands, only where the run is a script's (a picture to put beside a phone's)
    const char *safe = getenv("MBUI_SAFE");
    if (safe && (getenv("MBUI_SCRIPT") || getenv("MBUI_DRIVE") || getenv("MBUI_DRIVE_B64") || getenv("MBUI_RECORD"))) {
      sscanf(safe, "%lf,%lf", &safe_top, &safe_bottom);
      const char *ground = getenv("MBUI_GROUND");
      unsigned int gl, gd;
      if (ground && sscanf(ground, "#%6x,#%6x", &gl, &gd) == 2) {
        ground_light = gl;
        ground_of_dark = gd;
      }
    }
    // the content: the native views' view, the canvas's over it, both its size (inside the bars' bands)
    NSView *box = [[NSView alloc] initWithFrame:r];
    box.wantsLayer = YES;
    the_box = box;
    set_ground();
    // (AppKit's y up: the bottom band first)
    NSRect inside = NSMakeRect(0, safe_bottom, ww, wh - safe_top - safe_bottom);
    NSView *under = mb_views_root(NSRectToCGRect(inside));
    under.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [box addSubview:under];
    the_view = [[MBView alloc] initWithFrame:inside];
    the_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [box addSubview:the_view];
    w.contentView = box;
    // the wheel's upright scroll over a page that gives it to the canvas (ui's Touch: VerticalOut; a list of messages
    // with a page in it scrolls as a list), the canvas's; any other the page's
    static id wheel_monitor;
    if (!wheel_monitor)
      wheel_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                                            handler:^NSEvent *(NSEvent *e) {
                                                              if (!the_view || e.window != the_view.window) return e;
                                                              NSPoint p = [the_view convertPoint:e.locationInWindow fromView:nil];
                                                              const char *m = mb_views_touch_at(p.x, p.y, NULL);
                                                              if (!m || strcmp(m, "vertical") != 0) return e;
                                                              if (fabs(e.scrollingDeltaY) < fabs(e.scrollingDeltaX)) return e;
                                                              [the_view scrollWheel:e];
                                                              return nil;
                                                            }];
    // a trackpad's pinch over a page that gives two fingers to the canvas (ui's Touch: PinchOut), the canvas's: the page
    // does not zoom (the canvas takes no pinch of its own on the Mac yet: it goes no further)
    static id magnify_monitor;
    if (!magnify_monitor)
      magnify_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMagnify
                                                              handler:^NSEvent *(NSEvent *e) {
                                                                if (!the_view || e.window != the_view.window) return e;
                                                                NSPoint p = [the_view convertPoint:e.locationInWindow fromView:nil];
                                                                const char *m = mb_views_touch_at(p.x, p.y, NULL);
                                                                if (!m || strcmp(m, "pinch") != 0) return e;
                                                                [the_view magnifyWithEvent:e];
                                                                return nil;
                                                              }];
    [w makeKeyAndOrderFront:nil];
    [w makeFirstResponder:the_view];
    if (setup_inset) {
      place_buttons(w);
      for (NSNotificationName name in @[ NSWindowDidResizeNotification, NSWindowDidEnterFullScreenNotification,
                                         NSWindowDidExitFullScreenNotification ]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:w queue:nil
                                                      usingBlock:^(NSNotification *n) {
                                                        place_buttons(w);
                                                        [the_view requestFrame];
                                                      }];
      }
    }
    [NSApp activateIgnoringOtherApps:YES];
    // closed, the program ends (an app's bundle's window is put away instead: MBAppDelegate windowShouldClose)
    w.delegate = app_delegate;
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                      object:w
                                                       queue:nil
                                                  usingBlock:^(NSNotification *n) { exit(0); }];
    watch_sleep();
    network_start();
    for (NSNotificationName name in @[ NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification,
                                       NSWindowDidMiniaturizeNotification, NSWindowDidDeminiaturizeNotification,
                                       NSWindowDidChangeOcclusionStateNotification ]) {
      [[NSNotificationCenter defaultCenter] addObserverForName:name object:w queue:nil
                                                    usingBlock:^(NSNotification *n) { tell_state(); }];
    }
    for (NSNotificationName name in @[ NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification ]) {
      [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *n) { tell_state(); }];
    }
    // the system's appearance switched (light, dark, auto at dusk): a frame, which asks it again (mb_host_system_dark)
    [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AppleInterfaceThemeChangedNotification"
                                                                 object:nil queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(NSNotification *n) { [the_view requestFrame]; }];
    dispatch_async(dispatch_get_main_queue(), ^{ tell_state(); });
    [NSApp run];
  }
}

// (settled_run, not settle: asked before the window runs too, by what the app starts first, as own_clock is)
double mb_host_now(void) { return settled_run() ? settle_clock : mb_now_ms(); }

// The time of day (host_native.mbt's wall_ms): a settled run's from a fixed day (@ui.tester_wall's), on with its
// clock, so what it shows of it is the same each run.
double mb_host_wall_ms(void) {
  return settled_run() ? 1790000000000.0 + settle_clock : [[NSDate date] timeIntervalSince1970] * 1000.0;
}

// how far local time is ahead of UTC then, in minutes (@hostapi.utc_offset_min); a settled run's UTC, its day its own
int32_t mb_host_utc_offset_min(double at_ms) {
  if (settled_run()) return 0;
  return (int32_t)([[NSTimeZone localTimeZone] secondsFromGMTForDate:[NSDate dateWithTimeIntervalSince1970:at_ms / 1000.0]] / 60);
}

int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}

void mb_host_frame_awaiting(int32_t n, moonbit_string_t what) {
  awaiting = n;
  snprintf(awaited_what, sizeof awaited_what, "%s", mb_ns_from_string(what).UTF8String ?: "");
}

void mb_host_outside(int32_t kind, int32_t id, int32_t state) {
  if (outside_cb) outside_cb(kind, id, state);
}

double mb_host_event_time(void) { return event_time; }

int32_t mb_host_platform(void) { return 0; }

void mb_host_request_frame(void) { [the_view requestFrame]; }

// A message posted from outside the frames (post.h), on whatever thread: its frame asked for on the main thread.
static void mb_post_wake(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    mb_host_request_frame();
  });
}

void mb_host_wake_after(double ms) {
  if (settle) {
    double at = settle_clock + ms;
    if (settle_wake < 0 || at < settle_wake) settle_wake = at;
    pump_soon();
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms * 1e6)), dispatch_get_main_queue(),
                 ^{ [the_view requestFrame]; });
}

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  mb_render_present(buf, count, r, g, b);
}

void mb_host_set_ime(int32_t active, double x, double y, double w, double h, moonbit_string_t text,
                     int32_t a, int32_t b) {
  MBView *v = the_view;
  v.imeActive = active != 0;
  v.caretRect = NSMakeRect(x, y, w, h);
  v.mirror = mb_ns_from_string(text);
  v.sel = NSMakeRange(a, b - a);
  if (!active) [v.inputContext discardMarkedText];
  [v.inputContext invalidateCharacterCoordinates];
}

// no floating text menu of the system's here (the field's own keys and shortcuts do what it would)
void mb_host_text_menu(int32_t shown, double x, double y, double w, double h, int32_t can) {
  (void)shown, (void)x, (void)y, (void)w, (void)h, (void)can;
}

void mb_host_clipboard_set(moonbit_string_t s) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb clearContents];
  [pb setString:mb_ns_from_string(s) forType:NSPasteboardTypeString];
}

// A secret on the clipboard (@hostapi.clipboard_set_secret): as any words here (no sensitive mark, nothing cleared yet).
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) { mb_host_clipboard_set(s); }

// A picture on the clipboard (@hostapi.clipboard_set_image): the image the bytes are, as other apps paste one.
void mb_host_clipboard_image(moonbit_bytes_t data) {
  NSImage *img = [[NSImage alloc] initWithData:[NSData dataWithBytes:data length:Moonbit_array_length(data)]];
  if (!img) return;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb clearContents];
  [pb writeObjects:@[ img ]];
}


void mb_host_log(moonbit_string_t s) {
  fprintf(stdout, "%s\n", mb_ns_from_string(s).UTF8String);
  fflush(stdout);
}

// The app over another app done (@hostapi.over_done): it never is here.
void mb_host_over_done(int32_t open_app) {}

// A page in a browser's tab over the app (@hostapi.open_tab): macOS has none of its own, so the browser, as open_url.
int32_t mb_host_open_url(moonbit_string_t s);
int32_t mb_host_open_tab(moonbit_string_t s) { return mb_host_open_url(s); }

// What holds the app up while it listens for a browser (@hostapi.hold_words): nothing to say here, the app runs on.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {}

// A URL handed to the system (@hostapi.open_url): NSWorkspace, the browser or the app that takes it. A scripted run
// (MBUI_SCRIPT, MBUI_DRIVE) only says it on the log (open-url: …), opening nothing on the machine it runs on.
int32_t mb_host_open_url(moonbit_string_t s) {
  NSString *u = mb_ns_from_string(s);
  NSURL *url = [NSURL URLWithString:u];
  fprintf(stdout, "open-url: %s\n", u.UTF8String);
  fflush(stdout);
  if (!url || !url.scheme) return 0;
  if (getenv("MBUI_SCRIPT") || getenv("MBUI_DRIVE") || getenv("MBUI_DRIVE_B64")) return 1;
  return [NSWorkspace.sharedWorkspace openURL:url] ? 1 : 0;
}

// The ground under MBUI_SAFE's bands: the dark page's or the light one's (MBUI_GROUND, as the Android host takes them
// from the manifest's dev.mbui.ground), as the hosts put under their system bars; in snapshots too.
static void set_ground(void) {
  if (safe_top <= 0 && safe_bottom <= 0) return;
  uint32_t g = ground_dark ? ground_of_dark : ground_light;
  CGColorRef c = CGColorCreateSRGB(((g >> 16) & 0xFF) / 255.0, ((g >> 8) & 0xFF) / 255.0, (g & 0xFF) / 255.0, 1);
  the_box.layer.backgroundColor = c;
  CGColorRelease(c);
  mb_render_set_bands(safe_top, safe_bottom, g);
}

// Whether the run is settled (above): a script's, in stable mode, not a recording's. From the environment, as it is
// the same before the window runs (what the app starts before @ui.run asks it: own_clock) and after.
static int settled_run(void) {
  static int known = -1;
  if (known < 0)
    known = getenv("MBUI_SCRIPT") && !getenv("MBUI_RECORD") && getenv("MBUI_BENCH") && atoi(getenv("MBUI_BENCH")) < 0;
  return known;
}

// Whether the run is on its own clock (host_native.mbt's own_clock): a settled run's, asked before the window runs too.
int32_t mb_host_own_clock(void) { return settled_run(); }

int32_t mb_host_reduce_motion(void) {
  return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 1 : 0;
}

int32_t mb_host_bench_mode(void) {
  const char *b = getenv("MBUI_BENCH");
  bench_mode = b ? atoi(b) : 0;
  return bench_mode;
}

void mb_host_exit(int32_t code) { exit(code); }

void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

moonbit_string_t mb_host_env(moonbit_string_t name) {
  const char *v = getenv(mb_ns_from_string(name).UTF8String);
  return mb_string_from_ns(v ? [NSString stringWithUTF8String:v] ?: @"" : @"");
}

// The app in front or not (@hostapi.set_app_state): 1 while the window is shown (not hidden, minimized or covered), | 2
// while it is also the active app's key window; told as any of that changes.
static void (*state_cb)(int32_t);
void mb_host_set_app_state(void (*f)(int32_t)) { state_cb = f; }
static void tell_state(void) {
  NSWindow *w = the_view.window;
  if (!state_cb || !w) return;
  int shown = w.isVisible && !w.isMiniaturized && (w.occlusionState & NSWindowOcclusionStateVisible) != 0;
  int front = shown && NSApp.isActive && w.isKeyWindow;
  state_cb((shown ? 1 : 0) | (front ? 2 : 0));
  [the_view requestFrame];
}

// Whether the system's appearance is dark (@hostapi.system_dark): the app's own (NSApp.appearance is never set, so this is
// the system's even while the window is made to look otherwise below).
// Words as the app sizes them (@hostapi.font_scale): the system's own size of words not followed here yet.
double mb_host_font_scale(void) { return 1.0; }
// The app's widgets for the system's accessibility (@hostapi.a11y_on, a11y_tree): not told here yet.
int32_t mb_host_a11y_on(void) { return 0; }
void mb_host_a11y_tree(moonbit_string_t s) { (void)s; }

int32_t mb_host_system_dark(void) {
  NSAppearanceName n = [NSApp.effectiveAppearance
      bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
  return [n isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

// Sharing out (@hostapi.share): the system's sharing picker over the window, the words or the file (kept in a folder
// of the app's own in the temporary directory). Nothing comes in on macOS but, for scripted runs, the files
// MBUI_SHARE_FILES names (paths split by |) once, as Android's ACTION_SEND of files would bring them.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)mime;
  MBView *v = the_view;
  if (!v) return 0;
  id item = mb_ns_from_string(text);
  int32_t n = Moonbit_array_length(data);
  NSString *file = mb_ns_from_string(name).lastPathComponent;
  if (n > 0 && file.length) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mbui-shared"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *p = [dir stringByAppendingPathComponent:file];
    if (![[NSData dataWithBytes:data length:n] writeToFile:p atomically:YES]) return 0;
    item = [NSURL fileURLWithPath:p];
  }
  NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[ item ]];
  NSRect r = v.bounds;
  [picker showRelativeToRect:NSMakeRect(NSMidX(r) - 1, NSMidY(r) - 1, 2, 2) ofView:v preferredEdge:NSRectEdgeMinY];
  fprintf(stdout, "share: %s to the system's sharing picker\n", n > 0 ? "a file" : "words");
  fflush(stdout);
  return 1;
}
static NSMutableArray<NSData *> *shared_files;
moonbit_string_t mb_host_shared_in(void) {
  static int taken;
  const char *given = getenv("MBUI_SHARE_FILES");
  if (taken || !given || !*given) return moonbit_make_string_raw(0);
  taken = 1;
  shared_files = [NSMutableArray new];
  NSMutableArray *files = [NSMutableArray new];
  for (NSString *p in [@(given) componentsSeparatedByString:@"|"]) {
    NSData *d = p.length ? [NSData dataWithContentsOfFile:p] : nil;
    if (!d) continue;
    [shared_files addObject:d];
    [files addObject:@{@"name" : p.lastPathComponent, @"type" : @"", @"size" : @(d.length)}];
  }
  if (!files.count) return moonbit_make_string_raw(0);
  const char *words = getenv("MBUI_SHARE_TEXT");
  NSData *j = [NSJSONSerialization dataWithJSONObject:@{@"text" : words ? @(words) : @"", @"files" : files} options:0 error:nil];
  fprintf(stdout, "shared in: %lu files\n", (unsigned long)files.count);
  fflush(stdout);
  return mb_string_from_ns([[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding]);
}

moonbit_bytes_t mb_host_shared_in_file(int32_t i) {
  if (i < 0 || i >= (int32_t)shared_files.count) return moonbit_make_bytes(0, 0);
  NSData *d = shared_files[i];
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)d.length, 0);
  memcpy(out, d.bytes, d.length);
  shared_files[i] = [NSData data];
  return out;
}

// A package for the system's installer (@hostapi.install_package): none here, said on the system channel (system.mbt).
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  NSDictionary *said = @{@"install" : @{@"name" : mb_ns_from_string(name), @"error" : @"unsupported"}};
  NSData *json = [NSJSONSerialization dataWithJSONObject:said options:0 error:NULL];
  if (json) mb_post("system", (const char *)json.bytes, json.length, NULL, 0);
}

// ---- Updates (@hostapi.app_version, update_install, update_state) ----
// The app keeping itself current, as still.fail's desktop app does (Electron's autoUpdater; on macOS Squirrel's
// ShipIt): a newer build the core found (`app.update`: the release's zip) downloaded into the app's caches, picking up
// where a cut connection left off (the bytes so far kept in `<name>.part`, the rest asked for as a range, a few times
// over with a growing pause while each try gets further: Android's Updates.java), checked against its size and
// SHA-256, unzipped beside the app (on its volume), and taken only when it is this app, newer, and signed as this one
// is (its signature valid and meeting this app's designated requirement: still.fail's team and this app's id; a build
// signed ad hoc, a developer's, takes none). It is put in this app's place (the bundles swapped, this one's thrown
// away), and opened as this one quits (a shell waits for this process to end first: two cores never share the
// data). How it goes the app reads (`update_state`: the phase, how far, what went wrong), told each time it changes
// (MB_OUTSIDE_UPDATE, id 1: 0 while the host works at it, -1 failed). Only an app's bundle has a version here (a
// build run as a bare program, 0, never asks).

static NSString *update_phase = @"idle";  // idle | downloading | retrying | installing | failed
static int update_percent = -1;
static NSString *update_error = @"";
static BOOL update_working;

int32_t mb_host_app_version(void) {
  NSBundle *b = NSBundle.mainBundle;
  if (!b.bundleIdentifier || ![b.bundlePath.pathExtension isEqualToString:@"app"]) return 0;
  return [[b objectForInfoDictionaryKey:@"CFBundleVersion"] intValue];
}

// How it goes, from the worker: kept and told on the main thread (where the frames read it).
static void update_say(NSString *phase, int percent, NSString *error) {
  dispatch_async(dispatch_get_main_queue(), ^{
    BOOL changed = ![phase isEqualToString:update_phase] || percent != update_percent;
    update_phase = phase;
    update_percent = percent;
    update_error = error ?: @"";
    if ([phase isEqualToString:@"failed"]) update_working = NO;
    if (changed) {
      mb_host_outside(MB_OUTSIDE_UPDATE, 1, [phase isEqualToString:@"failed"] ? -1 : 0);
      [the_view requestFrame];
    }
  });
}

// What an update did, on the log and in the app's caches (<caches>/<id>/update.log: an app's stdout goes nowhere), where
// the shell that opens the new build adds its own line.
static NSString *update_log_path(void) {
  NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
  return [[caches stringByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier] stringByAppendingPathComponent:@"update.log"];
}

static void update_log(NSString *s) {
  fprintf(stdout, "update: %s\n", s.UTF8String);
  fflush(stdout);
  NSString *path = update_log_path();
  [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                                           attributes:nil error:NULL];
  NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
  if (!h) {
    [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    h = [NSFileHandle fileHandleForWritingAtPath:path];
  }
  [h seekToEndOfFile];
  [h writeData:[[NSString stringWithFormat:@"%@ %@\n", [NSDate date], s] dataUsingEncoding:NSUTF8StringEncoding]];
  [h closeFile];
}

// One try of the download (a data task, its bytes appended to the part as they come): whether the file is whole, or
// why not (`retry`: a cut connection or the server's trouble, tried again; else given up at once).
@interface MBUpdateFetch : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSFileHandle *out;
@property(nonatomic) long long done, size;
@property(nonatomic) NSInteger status;
@property(nonatomic, strong) NSError *error;
@property(nonatomic, strong) dispatch_semaphore_t finished;
@end
@implementation MBUpdateFetch
- (void)URLSession:(NSURLSession *)s
              dataTask:(NSURLSessionDataTask *)t
    didReceiveResponse:(NSURLResponse *)r
     completionHandler:(void (^)(NSURLSessionResponseDisposition))h {
  self.status = [(NSHTTPURLResponse *)r statusCode];
  if (self.status == 200) {
    // the whole file again (the server took no range): from its start
    [self.out truncateFileAtOffset:0];
    self.done = 0;
  }
  h(self.status == 200 || self.status == 206 ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
  [self.out writeData:d];
  self.done += d.length;
  if (self.size > 0) update_say(@"downloading", (int)(self.done * 100 / self.size), nil);
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
  self.error = e;
  dispatch_semaphore_signal(self.finished);
}
@end

static BOOL update_fetch(NSURL *url, NSString *part, long long size, BOOL *retry, NSString **why) {
  if (![NSFileManager.defaultManager fileExistsAtPath:part])
    [NSFileManager.defaultManager createFileAtPath:part contents:nil attributes:nil];
  MBUpdateFetch *f = [MBUpdateFetch new];
  f.out = [NSFileHandle fileHandleForWritingAtPath:part];
  f.done = (long long)[f.out seekToEndOfFile];
  f.size = size;
  f.finished = dispatch_semaphore_create(0);
  NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  cfg.timeoutIntervalForRequest = 30;
  cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:f delegateQueue:nil];
  NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:url];
  if (f.done > 0) [rq setValue:[NSString stringWithFormat:@"bytes=%lld-", f.done] forHTTPHeaderField:@"Range"];
  [[session dataTaskWithRequest:rq] resume];
  dispatch_semaphore_wait(f.finished, DISPATCH_TIME_FOREVER);
  [session finishTasksAndInvalidate];
  [f.out closeFile];
  *retry = NO;
  if (f.status == 416) return YES;  // asked from its end: it is all here
  if (f.status != 200 && f.status != 206) {
    *why = f.status ? [NSString stringWithFormat:@"status %ld", (long)f.status] : (f.error.localizedDescription ?: @"failed");
    *retry = f.status == 0 || f.status >= 500;
    return NO;
  }
  if (f.error) {
    *why = f.error.localizedDescription;
    *retry = YES;
    return NO;
  }
  if (size > 0 && f.done < size) {
    *why = [NSString stringWithFormat:@"connection closed at %lld of %lld", f.done, size];
    *retry = YES;
    return NO;
  }
  return YES;
}

static NSString *update_sha256(NSString *path) {
  NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
  if (!h) return @"";
  CC_SHA256_CTX ctx;
  CC_SHA256_Init(&ctx);
  for (;;) {
    @autoreleasepool {
      NSData *d = [h readDataOfLength:1 << 20];
      if (d.length == 0) break;
      CC_SHA256_Update(&ctx, d.bytes, (CC_LONG)d.length);
    }
  }
  [h closeFile];
  unsigned char md[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(md, &ctx);
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", md[i]];
  return s;
}

// The release downloaded whole into `dir` (what is there from before kept only if it is the part of this one), checked
// against its SHA-256: its path, or nil and why not.
static NSString *update_download(NSString *dir, NSURL *url, NSString *sha256, long long size, NSString *name,
                                 NSString **why) {
  NSFileManager *fm = NSFileManager.defaultManager;
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *zip = [dir stringByAppendingPathComponent:name];
  NSString *part = [zip stringByAppendingString:@".part"];
  for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
    NSString *p = [dir stringByAppendingPathComponent:f];
    if (![p isEqualToString:zip] && ![p isEqualToString:part]) [fm removeItemAtPath:p error:NULL];
  }
  if ([fm fileExistsAtPath:zip]) {
    if ([update_sha256(zip) caseInsensitiveCompare:sha256] == NSOrderedSame) return zip;
    [fm removeItemAtPath:zip error:NULL];
  }
  long long have = (long long)[[fm attributesOfItemAtPath:part error:NULL] fileSize];
  if (size > 0 && have > size) [fm removeItemAtPath:part error:NULL];
  // tries in a row that got no further before it gives up (pauses of 1, 2, 4, 8, 16 s between them)
  const int retries = 6;
  int failures = 0;
  for (;;) {
    long long before = (long long)[[fm attributesOfItemAtPath:part error:NULL] fileSize];
    BOOL retry = NO;
    if (update_fetch(url, part, size, &retry, why)) break;
    if (!retry) return nil;
    if ((long long)[[fm attributesOfItemAtPath:part error:NULL] fileSize] > before) failures = 0;
    if (++failures >= retries) return nil;
    update_say(@"retrying", update_percent, nil);
    [NSThread sleepForTimeInterval:(double)(1 << (failures - 1))];
    update_say(@"downloading", update_percent, nil);
  }
  NSString *got = update_sha256(part);
  if ([got caseInsensitiveCompare:sha256] != NSOrderedSame) {
    [fm removeItemAtPath:part error:NULL];
    *why = @"incomplete";
    return nil;
  }
  if (![fm moveItemAtPath:part toPath:zip error:NULL]) {
    *why = @"incomplete";
    return nil;
  }
  update_log([NSString stringWithFormat:@"%@ downloaded, sha256 %@ as the feed says", name, got]);
  return zip;
}

// Whether the app at `app` is signed as this one must be: valid, all of it, and meeting this app's designated
// requirement (its id and its signer's team); why not otherwise. (Security's code signing calls found as they are
// first needed: an app of mbui's links what its own moon.pkg says, which need not name Security.)
static BOOL update_signed_as_this(NSURL *app, NSString **why) {
  static OSStatus (*copy_self)(SecCSFlags, SecCodeRef *);
  static OSStatus (*copy_designated)(SecStaticCodeRef, SecCSFlags, SecRequirementRef *);
  static OSStatus (*static_create)(CFURLRef, SecCSFlags, SecStaticCodeRef *);
  static OSStatus (*check_validity)(SecStaticCodeRef, SecCSFlags, SecRequirementRef);
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    void *sec = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
    if (!sec) return;
    copy_self = dlsym(sec, "SecCodeCopySelf");
    copy_designated = dlsym(sec, "SecCodeCopyDesignatedRequirement");
    static_create = dlsym(sec, "SecStaticCodeCreateWithPath");
    check_validity = dlsym(sec, "SecStaticCodeCheckValidity");
  });
  if (!copy_self || !copy_designated || !static_create || !check_validity) {
    *why = @"no code signing here";
    return NO;
  }
  SecCodeRef me = NULL;
  SecRequirementRef req = NULL;
  SecStaticCodeRef it = NULL;
  OSStatus st = copy_self(kSecCSDefaultFlags, &me);
  if (st == errSecSuccess) st = copy_designated((SecStaticCodeRef)me, kSecCSDefaultFlags, &req);
  if (st == errSecSuccess) st = static_create((__bridge CFURLRef)app, kSecCSDefaultFlags, &it);
  if (st == errSecSuccess)
    st = check_validity(it, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate, req);
  if (me) CFRelease(me);
  if (req) CFRelease(req);
  if (it) CFRelease(it);
  if (st != errSecSuccess) *why = [NSString stringWithFormat:@"not signed as this app (%d)", (int)st];
  return st == errSecSuccess;
}

// The zip unzipped beside this app (a folder the system gives for replacing it, on its volume), its app checked, and
// swapped into this one's place: nil, or why not.
static NSString *update_put(NSString *zip) {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSURL *here = NSBundle.mainBundle.bundleURL;
  NSError *e = nil;
  NSURL *stage = [fm URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:here
                              create:YES error:&e];
  if (!stage) return [NSString stringWithFormat:@"can't write beside %@: %@", here.path, e.localizedDescription];
  NSTask *unzip = [NSTask new];
  unzip.launchPath = @"/usr/bin/ditto";
  unzip.arguments = @[ @"-x", @"-k", zip, stage.path ];
  [unzip launch];
  [unzip waitUntilExit];
  NSURL *app = nil;
  for (NSURL *u in [fm contentsOfDirectoryAtURL:stage includingPropertiesForKeys:nil options:0 error:NULL])
    if ([u.pathExtension isEqualToString:@"app"]) app = u;
  NSString *why = nil;
  NSBundle *b = app ? [NSBundle bundleWithURL:app] : nil;
  if (unzip.terminationStatus != 0 || !b) why = @"incomplete";
  else if (![b.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier])
    why = [NSString stringWithFormat:@"another app (%@)", b.bundleIdentifier];
  else if ([[b objectForInfoDictionaryKey:@"CFBundleVersion"] intValue] <= mb_host_app_version())
    why = @"not newer";
  else update_signed_as_this(app, &why);
  if (!why && ![fm replaceItemAtURL:here withItemAtURL:app backupItemName:nil options:0 resultingItemURL:NULL error:&e])
    why = [NSString stringWithFormat:@"can't replace %@: %@", here.path, e.localizedDescription];
  [fm removeItemAtURL:stage error:NULL];
  return why;
}

void mb_host_update_install(moonbit_string_t url_s, moonbit_string_t sha256_s, double size, moonbit_string_t name_s) {
  if (update_working || mb_host_app_version() <= 0) return;
  NSURL *url = [NSURL URLWithString:mb_ns_from_string(url_s)];
  NSString *sha256 = mb_ns_from_string(sha256_s), *name = mb_ns_from_string(name_s).lastPathComponent;
  if (!url || !name.length) return;
  update_working = YES;
  update_phase = @"downloading";
  update_percent = -1;
  update_error = @"";
  mb_host_outside(MB_OUTSIDE_UPDATE, 1, 0);
  NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
  NSString *dir = [[caches stringByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier]
      stringByAppendingPathComponent:@"updates"];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSString *why = nil;
    NSString *zip = update_download(dir, url, sha256, (long long)size, name, &why);
    if (zip) {
      update_say(@"installing", -1, nil);
      why = update_put(zip);
    }
    if (why) {
      update_log([NSString stringWithFormat:@"failed: %@", why]);
      update_say(@"failed", -1, why);
      return;
    }
    [NSFileManager.defaultManager removeItemAtPath:zip error:NULL];
    update_log(@"in place; opened again as this one quits");
    dispatch_async(dispatch_get_main_queue(), ^{
      // opened again once this process has ended, said on the update's log (the app's path as $0, the log's as $1:
      // nothing in them read as the shell's)
      NSTask *again = [NSTask new];
      again.launchPath = @"/bin/sh";
      again.arguments = @[
        @"-c",
        [NSString stringWithFormat:@"while /bin/kill -0 %d 2>/dev/null; do /bin/sleep 0.2; done; "
                                   @"/usr/bin/open \"$0\" && echo \"$(/bin/date) opened $0\" >> \"$1\"",
                                   getpid()],
        NSBundle.mainBundle.bundlePath, update_log_path()
      ];
      [again launch];
      [NSApp terminate:nil];
    });
  });
}

moonbit_string_t mb_host_update_state(void) {
  if (mb_host_app_version() <= 0) return moonbit_make_string_raw(0);
  NSDictionary *st = @{@"phase" : update_phase, @"percent" : @(update_percent), @"error" : update_error};
  NSData *json = [NSJSONSerialization dataWithJSONObject:st options:0 error:NULL];
  return mb_string_from_ns([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"");
}

// Turned sideways for a film (@hostapi.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }

// The app drawn dark or light (@hostapi.set_dark): the window's title bar the same.
void mb_host_set_dark(int32_t dark) {
  NSWindow *w = the_view.window;
  if (w) w.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  ground_dark = dark != 0;
  set_ground();
}

// ---- notifications (notify.mbt) ----
// The system's (UNUserNotificationCenter) when the app is a bundle (an app's .app: still.fail mbui's): one request per
// tag (a newer one with the same tag replaces it), what it opens in its userInfo, a tap bringing the app to the front
// with that (the center's delegate, set before the app runs: a tap that launched it comes too); shown while the app is
// in front as well (the app decides what to show). A bare executable has no bundle for the center (it throws): what
// would be shown is only kept there. Either way it is kept (one per tag) and said on the log (NOTICE <tag>\t<title>\t
// <body>), and a scripted run taps one by its words (drive 6), which gives the app what it opens as a tap would.
// The framework is asked for by this object itself (its load command), so no app's link flags have to name it.
__asm__(".linker_option \"-framework\", \"UserNotifications\"");

static NSMutableArray<NSArray<NSString *> *> *notices;
static NSString *notice_opened = @"";
// what the system allows: 0 not known yet, 1 granted, 2 denied, 3 not asked; the answer to an ask: -1 none, 0, 1
static _Atomic int32_t notice_allowed = 0;
static _Atomic int32_t notice_answered = -1;

static BOOL notice_system(void) { return NSBundle.mainBundle.bundleIdentifier != nil; }

@interface MBNoticeDelegate : NSObject <UNUserNotificationCenterDelegate>
@end
@implementation MBNoticeDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))done {
  done(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))done {
  NSString *opens = response.notification.request.content.userInfo[@"opens"];
  NSString *tag = response.notification.request.identifier;
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([opens isKindOfClass:NSString.class]) notice_opened = opens;
    [notices filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray<NSString *> *n, NSDictionary *b) {
      return ![n[0] isEqualToString:tag];
    }]];
    fprintf(stdout, "NOTICE TAP %s\n", tag.UTF8String);
    fflush(stdout);
    bring_back();
    [the_view requestFrame];
  });
  done();
}
@end

// What the system allows, asked again (as the app comes to the front: it may have changed in the system's settings).
static void notice_refresh(void) {
  if (!notice_system()) return;
  [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s) {
    int32_t was = notice_allowed;
    switch (s.authorizationStatus) {
      case UNAuthorizationStatusNotDetermined: notice_allowed = 3; break;
      case UNAuthorizationStatusDenied: notice_allowed = 2; break;
      default: notice_allowed = 1; break;
    }
    if (was != notice_allowed) dispatch_async(dispatch_get_main_queue(), ^{ [the_view requestFrame]; });
  }];
}

// Before the app runs (mb_host_run): the center's delegate, and what it allows.
static void notice_start(void) {
  if (!notice_system()) return;
  static MBNoticeDelegate *delegate;
  delegate = [MBNoticeDelegate new];
  [UNUserNotificationCenter currentNotificationCenter].delegate = delegate;
  notice_refresh();
  [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { notice_refresh(); }];
}

static void notice_drop(NSString *tag) {
  NSIndexSet *at = [notices indexesOfObjectsPassingTest:^BOOL(NSArray<NSString *> *n, NSUInteger i, BOOL *stop) {
    return [n[0] isEqualToString:tag];
  }];
  [notices removeObjectsAtIndexes:at];
}

void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;  // one kind of notification here: the system's settings list the app's, not channels
  if (!notices) notices = [NSMutableArray array];
  NSString *t = mb_ns_from_string(tag);
  notice_drop(t);
  NSArray<NSString *> *n = @[ t, mb_ns_from_string(title), mb_ns_from_string(body), mb_ns_from_string(opens) ];
  [notices addObject:n];
  fprintf(stdout, "NOTICE %s\t%s\t%s\n", n[0].UTF8String, n[1].UTF8String, n[2].UTF8String);
  fflush(stdout);
  if (!notice_system()) return;
  UNMutableNotificationContent *c = [UNMutableNotificationContent new];
  c.title = n[1];
  c.body = n[2];
  c.sound = UNNotificationSound.defaultSound;
  c.userInfo = @{@"opens" : n[3]};
  // the same identifier: the system replaces the one shown
  UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:t content:c trigger:nil];
  [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:r withCompletionHandler:^(NSError *e) {
    if (e) {
      fprintf(stdout, "NOTICE NOT SHOWN %s: %s\n", t.UTF8String, e.localizedDescription.UTF8String);
      fflush(stdout);
    }
  }];
}

void mb_host_notice_cancel(moonbit_string_t tag) {
  NSString *t = mb_ns_from_string(tag);
  NSUInteger before = notices.count;
  notice_drop(t);
  if (notices.count < before) {
    fprintf(stdout, "NOTICE CANCEL %s\n", t.UTF8String);
    fflush(stdout);
  }
  if (!notice_system()) return;
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center removeDeliveredNotificationsWithIdentifiers:@[ t ]];
  [center removePendingNotificationRequestsWithIdentifiers:@[ t ]];
}

// 0: what the system allows (1 granted, 2 denied, 3 not asked, 0 not known: always so for a bare executable);
// 1: ask it (1 when asked: not asked before); 2: its answer to the ask, once (1, 0; -1 none yet).
int32_t mb_host_notice_state(int32_t what) {
  if (what == 0) return notice_allowed;
  if (what == 2) {
    int32_t a = notice_answered;
    if (a >= 0) notice_answered = -1;
    return a;
  }
  if (!notice_system() || notice_allowed != 3) return 0;
  UNAuthorizationOptions o = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
  [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:o
                                                                      completionHandler:^(BOOL granted, NSError *e) {
    notice_answered = granted ? 1 : 0;
    notice_allowed = granted ? 1 : 2;
    dispatch_async(dispatch_get_main_queue(), ^{ [the_view requestFrame]; });
  }];
  return 1;
}

// A notification tapped, once; no push token or push here.
moonbit_string_t mb_host_notice_text(int32_t what) {
  if (what != 0) return mb_string_from_ns(@"");
  NSString *o = notice_opened;
  notice_opened = @"";
  return mb_string_from_ns(o);
}

static int32_t notice_drive(int tap, NSString *words) {
  NSArray<NSString *> *found = nil;
  for (NSArray<NSString *> *n in notices) {
    if ([n[1] containsString:words] || [n[2] containsString:words]) {
      found = n;
      break;
    }
  }
  if (!found) return 0;
  if (!tap) return 1;
  notice_opened = found[3];
  fprintf(stdout, "NOTICE TAP %s\n", found[0].UTF8String);
  fflush(stdout);
  [notices removeObject:found];
  if (notice_system()) [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[ found[0] ]];
  [the_view requestFrame];
  return 1;
}

// A scripted run's input (src/ui/drive.mbt), sent as the system sends it: the input method's calls on the view
// (insertText, setMarkedText, insertNewline:, deleteBackward:), Cmd+V as a key event through keyDown (the
// pasteboard read there), the window's picture saved.
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  MBView *v = the_view;
  NSString *s = mb_ns_from_string(text);
  switch (kind) {
    case 0: [v insertText:s replacementRange:NSMakeRange(NSNotFound, 0)]; break;
    case 1: [v setMarkedText:s selectedRange:NSMakeRange(s.length, 0) replacementRange:NSMakeRange(NSNotFound, 0)]; break;
    case 2: [v doCommandBySelector:@selector(insertNewline:)]; break;
    case 3: {
      NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                   timestamp:0 windowNumber:v.window.windowNumber context:nil characters:@"v"
                 charactersIgnoringModifiers:@"v" isARepeat:NO keyCode:9];
      [v keyDown:e];
      break;
    }
    case 4: {
      int ok = mb_render_snapshot(s.fileSystemRepresentation);
      fprintf(stdout, "SHOT %s %s\n", s.UTF8String, ok ? "ok" : "failed");
      fflush(stdout);
      break;
    }
    case 5: [v doCommandBySelector:@selector(deleteBackward:)]; break;
    // the window resized to "<w>x<h>" (its content)
    case 8: {
      double w = 0, h = 0;
      if (sscanf(s.UTF8String, "%lfx%lf", &w, &h) != 2 || w <= 0 || h <= 0) return 0;
      [v.window setContentSize:NSMakeSize(w, h)];
      fprintf(stdout, "RESIZED %.0fx%.0f\n", w, h);
      fflush(stdout);
      break;
    }
    // a notification kept here (below), by its words: tapped (6) or looked for (7)
    case 6:
    case 7: return notice_drive(kind == 6, s);
    // the directory the run's runner says what it has done in, watched (done_watch.h)
    case 9: return mb_done_watch(text);
    default: return 0;
  }
  [v requestFrame];
  return 1;
}

// The system's Reduce Transparency (glass drawn solid).
int32_t mb_host_reduce_transparency(void) {
  return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceTransparency] ? 1 : 0;
}

double mb_host_mem_bytes(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return 0;
  return (double)info.phys_footprint;
}

// ---- files picked (pick.mbt): the open panel ----
// MBUI_PICK_FILES="<path>|<path>…" answers every ask with those files at once, no panel (scripted runs: the screen is
// often locked where they run).

static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *picks;
static int32_t next_pick = 1;

static void pick_told(int32_t pid, NSArray *names, NSArray *datas) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSMutableDictionary *p = picks[@(pid)];
    if (!p) return;
    p[@"names"] = names;
    p[@"datas"] = datas;
    p[@"state"] = @(names.count > 0 ? 1 : -1);
    mb_host_outside(MB_OUTSIDE_PICK, pid, names.count > 0 ? 1 : -1);
    [the_view requestFrame];
  });
}

static void pick_answer(int32_t pid, NSArray<NSURL *> *urls) {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray *names = [NSMutableArray new], *datas = [NSMutableArray new];
    for (NSURL *u in urls) {
      NSData *d = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:nil];
      if (!d || d.length > (1ull << 30)) continue;  // unreadable, or over 1 GB (as still.fail's composer refuses)
      [names addObject:u.lastPathComponent ?: @"file"];
      [datas addObject:d];
    }
    pick_told(pid, names, datas);
  });
}

// Files let go on the window (ui/drop.mbt): read as a pick's, a folder's files by their way down from where it was
// dropped ("照片/2026/a.jpg"), each folder itself named with a "/" at its end and no bytes (so an empty one is made
// too); Finder's .DS_Store left out.
static int32_t drop_pick(NSArray<NSURL *> *urls) {
  if (!picks) picks = [NSMutableDictionary new];
  int32_t pid = next_pick++;
  picks[@(pid)] = [@{@"state" : @0} mutableCopy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray *names = [NSMutableArray new], *datas = [NSMutableArray new];
    NSFileManager *fm = [NSFileManager defaultManager];
    void (^one)(NSURL *, NSString *) = ^(NSURL *u, NSString *name) {
      NSNumber *dir = nil;
      [u getResourceValue:&dir forKey:NSURLIsDirectoryKey error:nil];
      if (dir.boolValue) {
        [names addObject:[name stringByAppendingString:@"/"]];
        [datas addObject:[NSData data]];
        return;
      }
      if ([u.lastPathComponent isEqualToString:@".DS_Store"]) return;
      NSData *d = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:nil];
      if (!d || d.length > (1ull << 30)) return;
      [names addObject:name];
      [datas addObject:d];
    };
    for (NSURL *u in urls) {
      NSString *top = u.lastPathComponent ?: @"file";
      one(u, top);
      NSNumber *dir = nil;
      [u getResourceValue:&dir forKey:NSURLIsDirectoryKey error:nil];
      if (!dir.boolValue) continue;
      NSDirectoryEnumerator *walk = [fm enumeratorAtURL:u includingPropertiesForKeys:@[ NSURLIsDirectoryKey ] options:0 errorHandler:nil];
      NSString *base = u.URLByStandardizingPath.path;
      for (NSURL *v in walk) {
        NSString *path = v.URLByStandardizingPath.path;
        if (![path hasPrefix:base]) continue;
        one(v, [top stringByAppendingString:[path substringFromIndex:base.length]]);
      }
    }
    pick_told(pid, names, datas);
  });
  return pid;
}

int32_t mb_host_pick_start(int32_t kind) {
  kind &= 15;  // (16: a big file may be held: none is here, each read whole)
  if (kind != 1 && kind != 2) return 0;  // no camera here
  if (!picks) picks = [NSMutableDictionary new];
  int32_t pid = next_pick++;
  picks[@(pid)] = [@{@"state" : @0} mutableCopy];
  const char *canned = getenv("MBUI_PICK_FILES");
  if (canned && *canned) {
    NSMutableArray *urls = [NSMutableArray new];
    for (NSString *path in [@(canned) componentsSeparatedByString:@"|"])
      if (path.length) [urls addObject:[NSURL fileURLWithPath:path]];
    pick_answer(pid, urls);
    return pid;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (kind == 1) panel.allowedFileTypes = @[ @"public.image" ];
#pragma clang diagnostic pop
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
      if (r == NSModalResponseOK) pick_answer(pid, panel.URLs);
      else {
        picks[@(pid)][@"state"] = @(-1);
        mb_host_outside(MB_OUTSIDE_PICK, pid, -1);
        [the_view requestFrame];
      }
    };
    if (the_view.window) [panel beginSheetModalForWindow:the_view.window completionHandler:done];
    else [panel beginWithCompletionHandler:done];
  });
  return pid;
}

// The gallery (gallery.mbt): none on this host; no photo of it picked.
int32_t mb_host_gallery_access(void) { return -1; }
void mb_host_gallery_ask(void) {}
int32_t mb_host_gallery_answers(void) { return 0; }
int32_t mb_host_gallery_read(void) { return 0; }
int32_t mb_host_gallery_read_state(int32_t id) { (void)id; return -1; }
moonbit_string_t mb_host_gallery_read_rows(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_gallery_read_end(int32_t id) { (void)id; }
int32_t mb_host_pick_photo(moonbit_string_t src) { (void)src; return 0; }

int32_t mb_host_pick_state(int32_t pid) {
  NSMutableDictionary *p = picks[@(pid)];
  return p ? [p[@"state"] intValue] : -1;
}

int32_t mb_host_pick_count(int32_t pid) { return (int32_t)[picks[@(pid)][@"names"] count]; }

moonbit_string_t mb_host_pick_name(int32_t pid, int32_t i) {
  NSArray *names = picks[@(pid)][@"names"];
  return mb_string_from_ns(i >= 0 && i < (int32_t)names.count ? names[i] : @"");
}

// every file read whole here (none held: pick.mbt's Picked.held)
moonbit_string_t mb_host_pick_info(int32_t pid, int32_t i) { return moonbit_make_string_raw(0); }

moonbit_bytes_t mb_host_pick_bytes(int32_t pid, int32_t i) {
  NSArray<NSData *> *datas = picks[@(pid)][@"datas"];
  NSData *d = i >= 0 && i < (int32_t)datas.count ? datas[i] : nil;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)d.length, 0);
  if (d.length) memcpy(b, d.bytes, d.length);
  return b;
}

void mb_host_pick_end(int32_t pid) { [picks removeObjectForKey:@(pid)]; }
