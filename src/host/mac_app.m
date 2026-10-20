// macOS host: an NSWindow whose view is a CAMetalLayer, frames from the
// view's display link, input from AppKit, and the system input method
// through NSTextInputClient. The window's content is a plain view holding
// the native views' (apple_views.m) and, over them, the canvas's.
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import <mach/mach.h>
#import "apple.h"
#include "post.h"
#include "done_watch.h"

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
// The desktop window as the app asks for it (@host.window_setup): its first size and its least, and whether its
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
// the pointer's shape (@host.set_cursor), and the press under way (what @host.window_drag drags the window with)
static int cursor_kind;
static NSEvent *down_event;
static int down_secondary;
static const char *shot_path;
static void tell_state(void);
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
static int frame_rest;             // its last frame left nothing that ends to come (@ui's Ctx::at_rest)
static char unrest_what[2048];     // else what kept it from it, as its last frame said
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

static void run_script_step(int step);

@implementation MBView

- (instancetype)initWithFrame:(NSRect)f {
  self = [super initWithFrame:f];
  self.wantsLayer = YES;
  self.mirror = @"";
  return self;
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
  mb_cb.wheel(p.x, p.y, -dx, -dy, phase);
}

// ---- keys ----

- (void)keyDown:(NSEvent *)e {
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
    else if ([c isEqualToString:@"v"]) {
      NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
      if (s.length) send_text(0, s, 0, 0);
    } else if (c.length == 1) {
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
    // SHOT_AT; MBUI_SHOT_MS=rest, the first frame that left nothing that ends to come (no motion short of its end, no
    // wake owed, nothing of the app's runtime running: @ui's Ctx::at_rest; nothing posted that no frame took: post.h;
    // a spinner turns on, at its clock's turn), a failure saying what kept it when none has by a minute on its clock;
    // or at frame MBUI_SHOT_AT where a script says a frame. Not stable: at frame MBUI_SHOT_AT (30)
    static int at;
    static double at_ms = -1;
    static int at_rest = -1;
    if (!at) at = getenv("MBUI_SHOT_AT") ? atoi(getenv("MBUI_SHOT_AT")) : settle ? -1 : 30;
    if (at_rest < 0) at_rest = getenv("MBUI_SHOT_MS") && strcmp(getenv("MBUI_SHOT_MS"), "rest") == 0;
    if (at_ms < 0) at_ms = getenv("MBUI_SHOT_MS") && !at_rest ? atof(getenv("MBUI_SHOT_MS")) : 1000;
    int rested = frame_rest && !mb_post_pending();
    int never = strncmp(unrest_what, "never: ", 7) == 0;
    if (settle && at <= 0 && at_rest && (never || (!rested && settle_clock >= 60000))) {
      char why[2200];
      if (never) snprintf(why, sizeof why, "at rest, but %s", unrest_what + 7);
      else snprintf(why, sizeof why, "not at rest after 60 s on its clock: %s",
                    frame_rest ? "a message posted that no frame took" : unrest_what);
      fprintf(stdout, "SHOT FAIL: %s\n", why);
      fprintf(stderr, "SHOT FAIL: %s\n", why);
      exit(3);
    }
    if (settle) {
      if (at > 0 ? step >= at : at_rest ? rested : settle_clock >= at_ms) {
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

// The window as the app wants it, asked before `run` (@host.window_setup).
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

// The press under way drags the window (the app's top row: @host.window_drag); twice, what the system's title bar
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

// The pointer's shape (@host.set_cursor): 0 the arrow, 1 a hand, 2 the I-beam, 3 and 4 resizing sideways and up and
// down, 5 an open hand.
void mb_host_set_cursor(int32_t kind) {
  cursor_kind = kind;
  [cursor_of(kind) set];
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
    notice_start();
    // MBUI_WIN=<w>x<h>: the window's size (a phone's, for the narrow layouts)
    // (else the app's own, @host.window_setup; else 900×720)
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
      // no title bar of the system's: the app's top row is it (the buttons in it, its drag: @host.window_drag)
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
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                      object:w
                                                       queue:nil
                                                  usingBlock:^(NSNotification *n) { exit(0); }];
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

int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}

void mb_host_frame_awaiting(int32_t n, moonbit_string_t what, moonbit_string_t unrest) {
  awaiting = n;
  frame_rest = Moonbit_array_length(unrest) == 0;
  snprintf(unrest_what, sizeof unrest_what, "%s", mb_ns_from_string(unrest).UTF8String ?: "");
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

void mb_host_clipboard_set(moonbit_string_t s) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb clearContents];
  [pb setString:mb_ns_from_string(s) forType:NSPasteboardTypeString];
}

// A secret on the clipboard (@host.clipboard_set_secret): as any words here (no sensitive mark, nothing cleared yet).
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) { mb_host_clipboard_set(s); }


void mb_host_log(moonbit_string_t s) {
  fprintf(stdout, "%s\n", mb_ns_from_string(s).UTF8String);
  fflush(stdout);
}

// The app over another app done (@host.over_done): it never is here.
void mb_host_over_done(int32_t open_app) {}

// A page in a browser's tab over the app (@host.open_tab): macOS has none of its own, so the browser, as open_url.
int32_t mb_host_open_url(moonbit_string_t s);
int32_t mb_host_open_tab(moonbit_string_t s) { return mb_host_open_url(s); }

// What holds the app up while it listens for a browser (@host.hold_words): nothing to say here, the app runs on.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {}

// A URL handed to the system (@host.open_url): NSWorkspace, the browser or the app that takes it. A scripted run
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

// The app in front or not (@host.set_app_state): 1 while the window is shown (not hidden, minimized or covered), | 2
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

// Whether the system's appearance is dark (@host.system_dark): the app's own (NSApp.appearance is never set, so this is
// the system's even while the window is made to look otherwise below).
int32_t mb_host_system_dark(void) {
  NSAppearanceName n = [NSApp.effectiveAppearance
      bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
  return [n isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

// Sharing out (@host.share): the system's sharing picker over the window, the words or the file (kept in a folder
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

// Updates (@host.app_version, update_install, update_state): this app does not update itself here.
int32_t mb_host_app_version(void) { return 0; }
// A package for the system's installer (@host.install_package): none here, said on the system channel (system.mbt).
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  NSDictionary *said = @{@"install" : @{@"name" : mb_ns_from_string(name), @"error" : @"unsupported"}};
  NSData *json = [NSJSONSerialization dataWithJSONObject:said options:0 error:NULL];
  if (json) mb_post("system", (const char *)json.bytes, json.length, NULL, 0);
}

void mb_host_update_install(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name) {
  (void)url; (void)sha256; (void)size; (void)name;
}
moonbit_string_t mb_host_update_state(void) { return moonbit_make_string_raw(0); }

// Turned sideways for a film (@host.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }

// The app drawn dark or light (@host.set_dark): the window's title bar the same.
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
    [NSApp activateIgnoringOtherApps:YES];
    [the_view.window makeKeyAndOrderFront:nil];
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

static void pick_answer(int32_t pid, NSArray<NSURL *> *urls) {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray *names = [NSMutableArray new], *datas = [NSMutableArray new];
    for (NSURL *u in urls) {
      NSData *d = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:nil];
      if (!d || d.length > (1ull << 30)) continue;  // unreadable, or over 1 GB (as still.fail's composer refuses)
      [names addObject:u.lastPathComponent ?: @"file"];
      [datas addObject:d];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      NSMutableDictionary *p = picks[@(pid)];
      if (!p) return;
      p[@"names"] = names;
      p[@"datas"] = datas;
      p[@"state"] = @(names.count > 0 ? 1 : -1);
      mb_host_outside(MB_OUTSIDE_PICK, pid, names.count > 0 ? 1 : -1);
      [the_view requestFrame];
    });
  });
}

int32_t mb_host_pick_start(int32_t kind) {
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

moonbit_bytes_t mb_host_pick_bytes(int32_t pid, int32_t i) {
  NSArray<NSData *> *datas = picks[@(pid)][@"datas"];
  NSData *d = i >= 0 && i < (int32_t)datas.count ? datas[i] : nil;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)d.length, 0);
  if (d.length) memcpy(b, d.bytes, d.length);
  return b;
}

void mb_host_pick_end(int32_t pid) { [picks removeObjectForKey:@(pid)]; }
