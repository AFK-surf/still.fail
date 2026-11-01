// macOS host: an NSWindow whose view is a CAMetalLayer, frames from the
// view's display link, input from AppKit, and the system input method
// through NSTextInputClient. The window's content is a plain view holding
// the native views' (apple_views.m) and, over them, the canvas's.
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import <Network/Network.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <sys/resource.h>
#include <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#include <pwd.h>
#import "apple.h"
#include "post.h"
#include "done_watch.h"

// (Network's path monitor, below: the framework asked of the linker by this file, as an app of mbui's links what its
// own moon.pkg names, which need not be Network)
__asm__(".linker_option \"-framework\", \"Network\"");

mb_callbacks mb_cb;

// Back (host_native.mbt `set_back`): a mouse's back button, while the app takes it (⌘[ is the app's key: its keymap's
// nav.back, as Ctrl+[ elsewhere).
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
@property(nonatomic) CFTimeInterval drawnWithWindowAt;  // drawWithWindow's last frame (CACurrentMediaTime)
@end

static MBView *the_view;
// the app's widgets for VoiceOver (below: mb_host_a11y_tree): the view's children, the one under a point, the one
// focused
static NSArray *a11y_children_of_view(void);
static id a11y_hit(NSPoint screen);
static id a11y_focused_element(void);
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
// whether the press under way went to the window (@hostapi.window_drag), and the one before it: a double click is the
// window's only where its first press was the window's too (not a button's there, gone with that press)
static bool down_dragged, last_down_dragged;
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

// ⌘V (the key, or the menu bar's 粘贴): files on the clipboard (copied in Finder, or by an app that copies a picture as
// its file) or a picture are the app's ⌘V (1000 + v), which reads the clipboard for them (@hostapi.clip_read), as a
// page's paste takes the clipboard's files; else its words, pasted (text kind 8: put in as typed, a step of its own
// to undo)
static void paste_now(int mods) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  BOOL files = [pb canReadObjectForClasses:@[ NSURL.class ] options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
  if (files || [pb canReadItemWithDataConformingToTypes:@[ NSPasteboardTypePNG, NSPasteboardTypeTIFF, @"public.image" ]]) {
    mb_cb.key(1000 + 'v', mods);
  } else {
    NSString *s = [pb stringForType:NSPasteboardTypeString];
    if (s.length) send_text(8, s, 0, 0);
  }
}

static void run_script_step(int step);
static void window_shown_now(void);
static double window_content_zoom = 1.0;
static int32_t (*window_key)(int32_t, int32_t);

void mb_host_set_window_zoom(double zoom) {
  if (zoom > 0) window_content_zoom = zoom;
}

void mb_host_set_window_key(int32_t (*f)(int32_t, int32_t)) { window_key = f; }

// the device beyond the window (device.mbt): a key catcher's keys, the clipboard, awake, haptics
#include "apple_device.h"

static int32_t drop_pick(NSArray<NSURL *> *urls);

// Files dragged in from outside (Finder) and let go on the window (ui/drop.mbt): where they are held, posted on
// `mbui.drop` as they move ({"type":"over","x","y"}, {"type":"left"}), then let go, with where each is and the pick
// their reading is, read once the app takes them as files ({"type":"drop","x","y","pick","paths":[{"path","dir",
// "size"}]}: a field, or a chat as this station's files, takes them by their paths, unread). Words dragged in (another
// app's text, a browser page's) are said only as they are let go, with what they say ({"type":"words","x","y","text"}):
// a field there takes them. Either let go here, the window comes to the front and has the keys, as a click on it would
// give them: what was let go into a field is typed on at once.
static void drop_post(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  mb_post("mbui.drop", (const char *)d.bytes, d.length, NULL, 0);
}

// Whether what is dragged has files (Finder's): else it is words, when it has any.
static BOOL drag_has_files(id<NSDraggingInfo> info) {
  return [info.draggingPasteboard canReadObjectForClasses:@[ NSURL.class ]
                                                  options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
}
static BOOL drag_has_words(id<NSDraggingInfo> info) {
  return [info.draggingPasteboard availableTypeFromArray:@[ NSPasteboardTypeString ]] != nil;
}

// What the menu bar's editing items can do (@hostapi.edit_can: text_menu_* bits), -1 till the app first says.
static int32_t edit_can_now = -1;

// how much later than its time the frame before reached the screen (mb_host_frame_late), and when the display link's
// last frame began (-1: none since the link was paused, or a frame drawn with the window's change between)
static double frame_late, last_tick = -1;
// The frame the app waits for (@hostapi.wake_after: a resident cycle's next step), by its time (ms, mb_now_ms's
// clock), or -1; the time of the frame being built (what wake_after counts from); the display's frame (ms).
static double wake_for = -1, building_for = -1, link_period = 1000.0 / 60.0;

@implementation MBView

- (instancetype)initWithFrame:(NSRect)f {
  self = [super initWithFrame:f];
  self.wantsLayer = YES;
  self.mirror = @"";
  [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL, NSPasteboardTypeString ]];
  return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
  return [self draggingUpdated:info];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
  // (words: nothing said till they are let go, no files held over the window)
  if (!drag_has_files(info)) return drag_has_words(info) ? NSDragOperationCopy : NSDragOperationNone;
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
  NSPoint p = [self convertPoint:info.draggingLocation fromView:nil];
  NSDictionary *m;
  if (urls.count == 0) {
    // words: what they say, where they were let go
    NSString *s = [info.draggingPasteboard stringForType:NSPasteboardTypeString];
    m = s.length ? @{@"type" : @"words", @"x" : @(p.x), @"y" : @(p.y), @"text" : s} : nil;
  } else {
    // files: where each is (a folder or not, its bytes), and the pick their reading is (begun as the app takes them as
    // files)
    NSMutableArray *paths = [NSMutableArray new];
    for (NSURL *u in urls) {
      if (!u.path.length) continue;
      NSNumber *dir = nil, *size = nil;
      [u getResourceValue:&dir forKey:NSURLIsDirectoryKey error:nil];
      if (!dir.boolValue) [u getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
      [paths addObject:@{@"path" : u.path, @"dir" : @(dir.boolValue), @"size" : @(size.longLongValue)}];
    }
    m = @{@"type" : @"drop", @"x" : @(p.x), @"y" : @(p.y), @"pick" : @(drop_pick(urls)), @"paths" : paths};
  }
  NSData *json = m ? [NSJSONSerialization dataWithJSONObject:m options:0 error:nil] : nil;
  if (!json) {
    drop_post(@"{\"type\":\"left\"}");
    return NO;
  }
  mb_post("mbui.drop", (const char *)json.bytes, json.length, NULL, 0);
  // (after the drag has ended in the app it came from: else that one takes the front back as it finishes)
  dispatch_async(dispatch_get_main_queue(), ^{ bring_back(); });
  return YES;
}

- (CALayer *)makeBackingLayer {
  CAMetalLayer *l = [CAMetalLayer layer];
  mb_render_init(l);
  return l;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

// The app's widgets for VoiceOver and whatever reads the screen: elements under the view (mb_host_a11y_tree), the
// view only what holds them
- (BOOL)isAccessibilityElement { return NO; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSArray *)accessibilityChildren { return a11y_children_of_view(); }
- (id)accessibilityHitTest:(NSPoint)p { return a11y_hit(p) ?: self; }
- (id)accessibilityFocusedUIElement { return a11y_focused_element() ?: self; }

// Every press on the canvas is the app's, in the system's title bar too (an inset window's: AppKit lays it out 44 high
// over the app's top row, MBWindow): the app says where its top row moves the window and what a double click there does
// (@hostapi.window_drag), its buttons there take theirs. Not window background (mouseDownCanMoveWindow), and opaque to
// window moves where it lies under the title bar (AppKit's own question of a view there, as WebKit's WKWebView answers
// it): else AppKit took each press in the bar before the app saw it, a drag of the window, a double click its zoom, on
// the app's buttons as well.
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar { return self.bounds; }

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
  [self drawWithWindow];
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
  mb_text_set_scale(scale * window_content_zoom);
  mb_render_set_size(s.width / window_content_zoom, s.height / window_content_zoom, scale * window_content_zoom);
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
  // one Core Animation transaction: the native views' moves (apple_views.m) and the drawable that shows their holes,
  // presented in it where a view moved (apple_render.m), committed together as the frame ends
  [CATransaction begin];
  // (what it waits for said again by the frame, if it still does)
  wake_for = -1;
  building_for = settle ? -1 : mb_now_ms();
  mb_cb.frame(s.width, s.height, scale, settle ? settle_clock : building_for);
  building_for = -1;
  [CATransaction commit];
  in_app_frame = NO;
  window_shown_now();
}

// A frame drawn now and shown with the change of the window's that called for it (its size: a resize, going in and out
// of full screen), in the same Core Animation transaction, not at the display link's next tick. The system's move of
// the window shows what the window has as it changes: drawn later, it showed the last frame (the full screen layout
// on the way out of it, stretched) and the window's own layout came once it was back, a jump after the move. Not in a
// settled or recorded run (their frames are their clock's), nor in the app's own frame (a size it set), nor before the
// window is shown: a frame asked for, as before.
- (void)drawWithWindow {
  if (settle || record_dir || in_app_frame || !self.window.visible) {
    [self requestFrame];
    return;
  }
  CAMetalLayer *l = (CAMetalLayer *)self.layer;
  l.presentsWithTransaction = YES;
  [self drawFrame];
  l.presentsWithTransaction = NO;
  self.drawnWithWindowAt = CACurrentMediaTime();
  last_tick = -1;
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

// One frame a refresh: none of the display link's in a refresh whose frame was drawn with the window's change of size
// (drawWithWindow); the frame asked for is drawn at the next. Drawn beside the change's, in a resize's run of changes
// each one's frame waited for a drawable the two held till the screen's next refresh (CAMetalLayer nextDrawable), and
// the resize with it.
- (void)tick:(CADisplayLink *)l {
  if (CACurrentMediaTime() - self.drawnWithWindowAt < l.targetTimestamp - l.timestamp) return;
  link_period = (l.targetTimestamp - l.timestamp) * 1000.0;
  // a frame waited for (wake_after): the first of the display's frames at or past its time (not when a timer happens
  // to fire and the link wakes after it, a step a frame or two late by as much as they fall, so a resident cycle's
  // steps unevenly apart); the ticks before it draw nothing (ios_app.m's the same)
  if (!self.wantFrame && wake_for >= 0) {
    if (mb_now_ms() < wake_for - 0.5) return;
    wake_for = -1;
    self.wantFrame = YES;
  }
  if (!self.wantFrame) {
    l.paused = YES;
    last_tick = -1;
    return;
  }
  // a frame's time is when it begins (drawFrame): one begun more than the display's frame after the one before, that
  // one was late by as much (it took longer than the display's frame to build); a settled or recorded run's never is
  double begins = mb_now_ms(), period = (l.targetTimestamp - l.timestamp) * 1000.0;
  frame_late = last_tick >= 0 && !settle && !record_dir ? MAX(0, begins - last_tick - period) : 0;
  last_tick = begins;
  [self drawFrame];
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
  if (!self.wantFrame) {
    l.paused = YES;
    last_tick = -1;
  }
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
  last_down_dragged = down_dragged;
  down_dragged = false;
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
    case 6: return NSCursor.closedHandCursor;
    case 7: return NSCursor.crosshairCursor;
    case 8: return NSCursor.operationNotAllowedCursor;
    default: return NSCursor.arrowCursor;
  }
}
- (void)cursorUpdate:(NSEvent *)e {
  [cursor_of(cursor_kind) set];
}
- (void)otherMouseUp:(NSEvent *)e {
  if (e.buttonNumber == 3) go_back();
  // the forward button: the app's key (key_forward), read as its forward
  else if (e.buttonNumber == 4) mb_cb.key(40, 0);
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

// The menu bar's editing items (the system's Edit menu, mb_host_menu_setup): each the key it names, pressed; greyed
// where the app says it can do nothing (mb_host_edit_can), as the system's fields have theirs.
- (BOOL)validateMenuItem:(NSMenuItem *)item {
  SEL a = item.action;
  int32_t bit = a == @selector(cut:)         ? 1
                : a == @selector(copy:)      ? 2
                : a == @selector(paste:)     ? 4
                : a == @selector(selectAll:) ? 8
                : a == @selector(undo:)      ? 16
                : a == @selector(redo:)      ? 32
                                             : 0;
  return bit == 0 || edit_can_now < 0 || (edit_can_now & bit) != 0;
}
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
  // the arrows and the deleting keys (with ⌘, ⌥ or none): what the text system makes of them while a field has the
  // keyboard (doCommandBySelector: ⌘← to the line's start, ⌘⌫ deleting to it); else the app's, as the keys they are
  int arrow = e.keyCode == 123 ? 3 : e.keyCode == 124 ? 4 : e.keyCode == 126 ? 5 : e.keyCode == 125 ? 6 : 0;
  int editing = arrow ? arrow : e.keyCode == 51 ? 1 : e.keyCode == 117 ? 2 : 0;
  if (m & NSEventModifierFlagCommand) {
    NSString *c = e.charactersIgnoringModifiers.lowercaseString;
    if (editing) {
      if (self.imeActive) [self interpretKeyEvents:@[ e ]];
      else mb_cb.key(editing, mods);
    } else if ([c isEqualToString:@"q"]) [NSApp terminate:nil];
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
    case 51: mb_cb.key(1, mods); break;    // Delete (Backspace)
    case 117: mb_cb.key(2, mods); break;   // forward Delete
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

// What the text system makes of a key (interpretKeyEvents: the system's key bindings, the person's own among them), as
// the framework's keys: the editing keys and, for the moves and deletions the arrows don't name, its edit keys
// (ui's key_code_word_back…); "…AndModifySelection" is the same with Shift. One the field does nothing with (a scroll,
// transpose:) is no key.
- (void)doCommandBySelector:(SEL)sel {
  static NSDictionary<NSString *, NSNumber *> *codes;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    codes = @{
      @"deleteBackward:" : @1, @"deleteBackwardByDecomposingPreviousCharacter:" : @1, @"deleteForward:" : @2,
      @"moveLeft:" : @3, @"moveBackward:" : @3, @"moveRight:" : @4, @"moveForward:" : @4,
      @"moveUp:" : @5, @"moveDown:" : @6, @"insertNewline:" : @7,
      @"scrollPageUp:" : @15, @"pageUp:" : @15, @"scrollPageDown:" : @16, @"pageDown:" : @16,
      @"moveWordLeft:" : @20, @"moveWordBackward:" : @20, @"moveWordRight:" : @21, @"moveWordForward:" : @21,
      @"moveToLeftEndOfLine:" : @22, @"moveToBeginningOfLine:" : @22,
      @"moveToRightEndOfLine:" : @23, @"moveToEndOfLine:" : @23,
      @"moveToBeginningOfParagraph:" : @24, @"moveToEndOfParagraph:" : @25,
      @"moveToBeginningOfDocument:" : @26, @"moveToEndOfDocument:" : @27,
      @"moveParagraphBackward:" : @28, @"moveParagraphForward:" : @29,
      @"deleteWordBackward:" : @30, @"deleteWordForward:" : @31,
      @"deleteToBeginningOfLine:" : @32, @"deleteToEndOfLine:" : @33,
      @"deleteToBeginningOfParagraph:" : @34, @"deleteToEndOfParagraph:" : @35,
    };
  });
  NSString *s = NSStringFromSelector(sel);
  int mods = 0;
  if ([s hasSuffix:@"AndModifySelection:"]) {
    s = [[s substringToIndex:s.length - @"AndModifySelection:".length] stringByAppendingString:@":"];
    mods = 1;
  }
  int code = codes[s].intValue;
  if ([s isEqualToString:@"insertLineBreak:"] || [s isEqualToString:@"insertNewlineIgnoringFieldEditor:"]) {
    code = 7;
    mods = 1;
  }
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

// Whether the window is full screen or on its way there: from as the system starts taking it there (WillEnter) till it
// starts bringing it back (WillExit), or it did not go (MBAppDelegate). What the app lays out by (its top row with the
// buttons or without: mb_host_window_inset; the window's corners), where the buttons are, follow it from the start of
// the system's move, so the move shows the window as it will be: told at the move's end, the app changed its layout
// once the window was back, a jump after it.
static bool full_screen_on;

// The window's buttons in the app's top row (an inset window): 16 from its left, centred on its 44, as still.fail's
// desktop app has them (Electron's trafficLightPosition {16, 15}), as far apart as the system has them. Put there by
// AppKit itself, each time it lays their title bar out (the window resized, its appearance set, in and out of full
// screen): the window's frame (NSThemeFrame) asks itself how high the bar is (_titlebarHeight), how far in from the
// left its buttons start (_minXTitlebarWidgetInset) and whether they are centred in it (_shouldCenterTrafficLights),
// and the window's is one of ours (MBWindow) that says 44, 16 and yes, as Chrome's has its buttons in its tab strip.
// Moved there after AppKit had put them in its own place, they were in that place for a frame each time: shaking as
// the window was resized, wrong as it came out of full screen. Not while the window is full screen or on its way
// there (full_screen_on: the system's own bar there): AppKit's own answers. Where AppKit's frame has none of these, the
// buttons stay in AppKit's own place.
static Class frame_base;

static bool buttons_inset(void) { return setup_inset && !full_screen_on; }

static double frame_bar_height(id self, SEL s) {
  return buttons_inset() ? 44 : ((double (*)(id, SEL))class_getMethodImplementation(frame_base, s))(self, s);
}

static double frame_buttons_left(id self, SEL s) {
  return buttons_inset() ? 16 : ((double (*)(id, SEL))class_getMethodImplementation(frame_base, s))(self, s);
}

static BOOL frame_buttons_centred(id self, SEL s) {
  return buttons_inset() || ((BOOL (*)(id, SEL))class_getMethodImplementation(frame_base, s))(self, s);
}

@interface NSWindow (MBFrameView)
+ (Class)frameViewClassForStyleMask:(NSWindowStyleMask)m;
@end

@interface MBWindow : NSWindow
@end
@implementation MBWindow
// A scripted run's window keeps the size it was given (MBUI_WIN) on a screen shorter than it (a virtual machine's):
// AppKit would shrink it to the screen, and the run's page would not be the one its test replays (a 390×844 phone's).
- (NSRect)constrainFrameRect:(NSRect)r toScreen:(NSScreen *)s {
  if (getenv("MBUI_WIN") && (getenv("MBUI_SCRIPT") || getenv("MBUI_DRIVE") || getenv("MBUI_DRIVE_B64")))
    return r;
  return [super constrainFrameRect:r toScreen:s];
}
+ (Class)frameViewClassForStyleMask:(NSWindowStyleMask)m {
  Class base = [super frameViewClassForStyleMask:m];
  static Class ours;
  if (!setup_inset) return base;
  if (!ours) {
    SEL h = NSSelectorFromString(@"_titlebarHeight"), x = NSSelectorFromString(@"_minXTitlebarWidgetInset"),
        c = NSSelectorFromString(@"_shouldCenterTrafficLights");
    if (![base instancesRespondToSelector:h] || ![base instancesRespondToSelector:x] ||
        ![base instancesRespondToSelector:c])
      return base;
    ours = objc_allocateClassPair(base, "MBWindowFrame", 0);
    class_addMethod(ours, h, (IMP)frame_bar_height, "d@:");
    class_addMethod(ours, x, (IMP)frame_buttons_left, "d@:");
    class_addMethod(ours, c, (IMP)frame_buttons_centred, "B@:");
    objc_registerClassPair(ours);
    frame_base = base;
  }
  return base == frame_base ? ours : base;
}
@end

// The window full screen or going there (on), or a window or on its way back: the app drawn again for it, its title
// bar laid out again for it (its height, where its buttons are: MBWindow) as AppKit lays it out itself
// (_tileTitlebarAndRedisplay:; a layout asked for, of the frame or of the bar, does not). Else where the system did
// not take the window there after all, the bar stayed as it was laid out for full screen.
static void full_screen_going(NSWindow *w, bool on) {
  full_screen_on = on;
  NSView *frame = w.contentView.superview;
  SEL tile = NSSelectorFromString(@"_tileTitlebarAndRedisplay:");
  if ([frame respondsToSelector:tile]) ((void (*)(id, SEL, BOOL))objc_msgSend)(frame, tile, YES);
  [the_view requestFrame];
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

// The window held out of sight as it opens (@hostapi.window_hold): put on the screen as the others are, so that its
// display link ticks and the app draws into it, but see-through and taking no clicks till the app shows it
// (mb_host_window_show): it comes up with the app's page drawn, not with its ground for the page's first moments.
// Asked in a frame, it is shown as that frame ends (drawFrame: window_shown_now), the frame on it.
static BOOL window_held, window_shown, window_to_show;

void mb_host_window_hold(void) { window_held = YES; }

void mb_host_window_show(void) {
  if (window_held && !window_shown) window_to_show = YES;
}

static void window_shown_now(void) {
  NSWindow *w = the_view.window;
  if (!window_to_show || window_shown || !w) return;
  window_shown = YES;
  w.ignoresMouseEvents = NO;
  w.alphaValue = 1;
}

// Whether the window's buttons are in the app's top row now (an inset window, not full screen nor going there).
int32_t mb_host_window_inset(void) {
  NSWindow *w = the_view.window;
  return setup_inset && w && !full_screen_on ? 1 : 0;
}

// Whether the window fills the screen now or is going to (@hostapi.full_screen), and made to or back (as its green
// button does).
int32_t mb_host_full_screen(void) {
  return the_view.window && full_screen_on ? 1 : 0;
}

void mb_host_set_full_screen(int32_t on) {
  NSWindow *w = the_view.window;
  if (w && (on != 0) != full_screen_on) [w toggleFullScreen:nil];
}

// How round the system draws the window's corners (@hostapi.window_corner), in points: what AppKit's own frame of it
// says (16 on macOS 27, for a window with a title bar, one see-through over its content, one with a toolbar alike);
// where it says nothing, by the system's version (16 since macOS 26, 10 before). None filling the screen.
double mb_host_window_corner(void) {
  NSWindow *w = the_view.window;
  if (!w || full_screen_on) return 0;
  SEL s = NSSelectorFromString(@"_cornerRadius");
  if ([w respondsToSelector:s]) {
    NSMethodSignature *sig = [w methodSignatureForSelector:s];
    if (strcmp(sig.methodReturnType, @encode(CGFloat)) == 0) {
      NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
      inv.selector = s;
      inv.target = w;
      [inv invoke];
      CGFloat r = 0;
      [inv getReturnValue:&r];
      if (r >= 0 && r < 64) return r;
    }
  }
  return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16 : 10;
}

// Each corner (@hostapi.window_corner_at): all alike.
double mb_host_window_corner_at(int k) {
  (void)k;
  return mb_host_window_corner();
}

// The press under way drags the window (the app's top row: @hostapi.window_drag); the second of a double click there
// (the first the window's too), what the system's title bar does on a double click, as AppKit's frame does it for its
// own (fill, zoom, minimize or nothing, as set in the system's settings; the press's modifiers as there); where the
// frame has no such answer, by that setting read here.
void mb_host_window_drag(void) {
  NSWindow *w = the_view.window;
  NSEvent *e = down_event;
  if (!w || !e) return;
  down_dragged = true;
  if (e.clickCount >= 2 && last_down_dragged) {
    NSView *frame = w.contentView.superview;
    SEL own = NSSelectorFromString(@"_handlePossibleDoubleClickWithModifiers:");
    if ([frame respondsToSelector:own]) {
      ((BOOL (*)(id, SEL, NSUInteger))objc_msgSend)(frame, own,
                                                     e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
      return;
    }
    NSString *act = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleActionOnDoubleClick"];
    if ([act isEqualToString:@"Minimize"]) [w performMiniaturize:nil];
    else if (![act isEqualToString:@"None"]) [w performZoom:nil];
    return;
  }
  [w performWindowDragWithEvent:e];
}

// The window's own buttons, the app's to draw where the system draws none (@hostapi.window_act, window_zoomed,
// window_snap, window_snap_state): Windows' alone; the system's here.
void mb_host_window_act(int32_t what) { (void)what; }
int32_t mb_host_window_zoomed(void) { return 0; }
void mb_host_window_snap(double x, double y, double w, double h) { (void)x, (void)y, (void)w, (void)h; }
int32_t mb_host_window_snap_state(void) { return 0; }

// The keys held now (@hostapi.mods_held), as a key's are told: shift 1, control 2, option 4, command 8.
int32_t mb_host_mods_held(void) {
  NSEventModifierFlags m = [NSEvent modifierFlags];
  return ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
         ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
}

// This machine's station (@hostapi.local_station; apps/desktop/src/main.ts localStation, installed.ts): its data
// (~/.stillfail), whether it runs (run/station.json's pid alive) and by what (a launchd service the installer made, or a
// process started by hand), its release, whether the installer put one there, the workspace its data is in; what is
// being done to it and what went wrong last. "" where there is neither data nor a service. Its acts (@hostapi.local_station_act) run off the main thread:
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
  // a release of its own (<data>/app: the installer's); a station still.fail's desktop app ran from its bundle has none
  if ([NSFileManager.defaultManager fileExistsAtPath:[data stringByAppendingPathComponent:@"app"]]) o[@"installed"] = @YES;
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
// down, 5 an open hand, 6 a closed one, 7 a crosshair, 8 what cannot be done.
void mb_host_set_cursor(int32_t kind) {
  cursor_kind = kind;
  [cursor_of(kind) set];
}

// ---- The app's life on the Mac, and what the system says of it ----
// As still.fail's desktop app is on macOS (Electron's): closing the window puts it away and the app goes on (its core,
// its notifications, the Dock's badge); the Dock's icon clicked, the app opened again or a notification brings it back;
// ⌘Q (the menu bar's 退出) quits. A program run bare
// (not an app's bundle: a developer's run, a script's, a test's) ends as its window closes, as before, and so does a
// window of the app's own (@hostapi.window_open: the program run again, beside this one). Said to the app
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

// a window of the app's own (@hostapi.window_open): MBUI_WINDOW said by whoever started it
static BOOL window_run(void) {
  const char *w = getenv("MBUI_WINDOW");
  return w && *w;
}

// Another window of the app's (@hostapi.window_open): the program run again (the bundle's executable, or this
// program's own path run bare), its environment this one's with MBUI_WINDOW=<what>. It is an app of its own beside
// this one (its own tile in the Dock, the same bundle's), ending as its window closes (windowShouldClose).
int32_t mb_host_window_opens(void) { return 1; }
int32_t mb_host_window_open(moonbit_string_t what_s) {
  NSString *what = mb_ns_from_string(what_s);
  NSString *exe = NSBundle.mainBundle.executablePath;
  if (!what.length || !exe) return 0;
  NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
  env[@"MBUI_WINDOW"] = what;
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:exe];
  t.environment = env;
  NSError *e = nil;
  if (![t launchAndReturnError:&e]) {
    fprintf(stdout, "mac: no window of its own (%s)\n", e.localizedDescription.UTF8String ?: "");
    fflush(stdout);
    return 0;
  }
  return 1;
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
  if (!in_bundle() || window_run()) return YES;
  [w orderOut:nil];
  if (!put_away_at) put_away_at = clock_gettime_nsec_np(CLOCK_MONOTONIC);
  return NO;
}
- (void)windowDidFailToEnterFullScreen:(NSWindow *)w {
  full_screen_going(w, false);
}
- (void)windowDidFailToExitFullScreen:(NSWindow *)w {
  full_screen_going(w, true);
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
// first seen; the path's interfaces compared whole, a VPN's tunnel first whatever carries it (ios_app.m's network_start)
static nw_path_monitor_t network_monitor;
static void network_start(void) {
  network_monitor = nw_path_monitor_create();
  nw_path_monitor_set_queue(network_monitor, dispatch_get_main_queue());
  static NSString *was;
  nw_path_monitor_set_update_handler(network_monitor, ^(nw_path_t path) {
    NSMutableString *now = [NSMutableString string];
    if (nw_path_get_status(path) == nw_path_status_satisfied) {
      nw_path_enumerate_interfaces(path, ^bool(nw_interface_t i) {
        [now appendFormat:@"%s/%d,", nw_interface_get_name(i), (int)nw_interface_get_type(i)];
        return true;
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
  // its keys as the app has them ("Mod+Shift+H", "Alt+Up", "Mod+\\"): shown; the view takes them before the menu does
  // (an app's menu is MBShownKeysMenu, below), so the app does what they say once
  if ([it[@"keys"] isKindOfClass:NSString.class]) {
    NSArray<NSString *> *parts = [it[@"keys"] componentsSeparatedByString:@"+"];
    NSEventModifierFlags mods = 0;
    for (NSUInteger i = 0; i + 1 < parts.count; i++) {
      NSString *p = parts[i];
      if ([p isEqualToString:@"Mod"]) mods |= NSEventModifierFlagCommand;
      else if ([p isEqualToString:@"Alt"]) mods |= NSEventModifierFlagOption;
      else if ([p isEqualToString:@"Shift"]) mods |= NSEventModifierFlagShift;
      else if ([p isEqualToString:@"Ctrl"]) mods |= NSEventModifierFlagControl;
    }
    NSDictionary *named = @{
      @"Up" : [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey],
      @"Down" : [NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey],
      @"Left" : [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey],
      @"Right" : [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey],
      @"Space" : @" ",
      @"Escape" : @"\e",
      @"Enter" : @"\r",
      @"Plus" : @"+",
    };
    NSString *key = parts.lastObject;
    NSString *k = named[key] ?: key.lowercaseString;
    if (k.length) {
      item.keyEquivalent = k;
      item.keyEquivalentModifierMask = mods;
    }
  }
  // (what cannot be done now, greyed: the app says)
  if ([it[@"enabled"] isEqual:@NO]) item.enabled = NO;
  return item;
}

// The canvas takes its own keys first. If a native page has focus, offer window-wide keys to the app before the page.
@interface MBShownKeysMenu : NSMenu
@end
@implementation MBShownKeysMenu
- (BOOL)performKeyEquivalent:(NSEvent *)e {
  if (!window_key || e.type != NSEventTypeKeyDown || !the_view.window.isKeyWindow ||
      the_view.window.firstResponder == the_view)
    return NO;
  NSEventModifierFlags m = e.modifierFlags;
  int mods = ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
             ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
  int code = e.keyCode == 123 ? 3 : e.keyCode == 124 ? 4 : e.keyCode == 126 ? 5 : e.keyCode == 125 ? 6 :
             e.keyCode == 36 || e.keyCode == 76 ? 7 : e.keyCode == 53 ? 17 : 0;
  if (!code) {
    NSString *key = e.charactersIgnoringModifiers.lowercaseString;
    if (key.length == 1) code = 1000 + [key characterAtIndex:0];
  }
  return code && window_key(code, mods);
}
@end

void mb_host_menu_setup(moonbit_string_t json_s) {
  [NSApplication sharedApplication];
  NSData *d = [mb_ns_from_string(json_s) dataUsingEncoding:NSUTF8StringEncoding];
  NSArray *menus = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
  if (![menus isKindOfClass:NSArray.class]) return;
  NSMenu *bar = [NSMenu new];
  for (NSDictionary *m in menus) {
    if (![m isKindOfClass:NSDictionary.class]) continue;
    // (the notification area's icon's, Windows': the Dock has the app's own)
    if ([m[@"role"] isEqual:@"tray"]) continue;
    NSString *title = [m[@"title"] isKindOfClass:NSString.class] ? m[@"title"] : @"";
    // (`"role": "actions"`: one of the app's actions only, MBShownKeysMenu; what is enabled the app says, not AppKit)
    NSMenu *menu = [m[@"role"] isEqual:@"actions"] ? [[MBShownKeysMenu alloc] initWithTitle:title]
                                                   : [[NSMenu alloc] initWithTitle:title];
    menu.autoenablesItems = NO;
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
  // this machine's name (MBUI_MACHINE, @ui.env): what a station added from here is called (sfbase local_machine_name)
  char machine[256];
  if (!getenv("MBUI_MACHINE") && gethostname(machine, sizeof machine) == 0) setenv("MBUI_MACHINE", machine, 0);
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
    NSWindow *w = [[MBWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
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
    // (held: out of sight till the app shows it, mb_host_window_show)
    if (window_held && !window_shown) {
      w.alphaValue = 0;
      w.ignoresMouseEvents = YES;
    }
    [w makeKeyAndOrderFront:nil];
    [w makeFirstResponder:the_view];
    // full screen from as the system starts taking the window there, a window from as it starts bringing it back
    // (full_screen_on)
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillEnterFullScreenNotification object:w queue:nil
                                                  usingBlock:^(NSNotification *n) { full_screen_going(w, true); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillExitFullScreenNotification object:w queue:nil
                                                  usingBlock:^(NSNotification *n) { full_screen_going(w, false); }];
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

// What a pointer's event came from (@hostapi.event_finger): not said (a Mac's pointer).
int32_t mb_host_event_finger(void) { return -1; }

double mb_host_frame_late(void) { return frame_late; }

int32_t mb_host_platform(void) { return 0; }

void mb_host_request_frame(void) { [the_view requestFrame]; }

// A message posted from outside the frames (post.h), on whatever thread: its frame asked for on the main thread.
static void mb_post_wake(void) {
  // the app told what came (ui's messages_between): it takes what changes only signals now, and asks for a frame only
  // where something is left for one
  dispatch_async(dispatch_get_main_queue(), ^{
    if (outside_cb) outside_cb(MB_OUTSIDE_POSTED, 0, 0);
    else mb_host_request_frame();
  });
}

void mb_host_wake_after(double ms) {
  if (settle) {
    double at = settle_clock + ms;
    if (settle_wake < 0 || at < settle_wake) settle_wake = at;
    pump_soon();
    return;
  }
  // `ms` after the frame being built's time, else after now: the frame for that time drawn (tick), the link woken a
  // little before it (two display frames) and drawing nothing until then
  double at = (building_for >= 0 ? building_for : mb_now_ms()) + ms;
  if (wake_for >= 0 && wake_for <= at) return;
  wake_for = at;
  double lead = at - mb_now_ms() - 2.0 * link_period;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(lead, 0) * 1e6)), dispatch_get_main_queue(), ^{
    // (a wake asked later since, or met already: not this one's)
    if (wake_for == at) the_view.link.paused = NO;
  });
}

// Whether the window can be seen now (tell_state's `shown`: not hidden, minimized or covered).
static int window_seen = 1;

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  // (a window nobody can see draws nothing: what drawing holds was given back as it went (mb_render_trim), and a
  // frame drawn now would take it again, the GPU drawing it for nobody, a frame for each answer the core gives; shown
  // again, tell_state asks a frame, which draws what it shows then, whole)
  // (a scripted or recorded run stands for someone looking at it, wherever its window is: drawn all the same)
  if (!window_seen && !script && !settle && !record_dir && !getenv("MBUI_DRIVE") && !getenv("MBUI_DRIVE_B64")) return;
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

void mb_host_edit_can(int32_t can) { edit_can_now = can; }

void mb_host_clipboard_set(moonbit_string_t s) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb clearContents];
  [pb setString:mb_ns_from_string(s) forType:NSPasteboardTypeString];
}

// The pasteboard's change count once a secret was put there, to be taken off (another copy since changes it), -1 none
static NSInteger secret_count = -1;

// A secret on the clipboard (@hostapi.clipboard_set_secret): marked concealed, as clipboard managers read it
// (nspasteboard.org: not shown, not kept in their history).
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb clearContents];
  [pb setString:mb_ns_from_string(s) forType:NSPasteboardTypeString];
  [pb setString:@"" forType:@"org.nspasteboard.ConcealedType"];
  secret_count = clear_ms > 0 ? pb.changeCount : -1;
}

// The last secret copied taken off (@hostapi.clipboard_secret_off), unless something else was copied since.
void mb_host_clipboard_secret_off(void) {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  if (secret_count >= 0 && pb.changeCount == secret_count) [pb clearContents];
  secret_count = -1;
}

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
  window_seen = shown;
  int front = shown && NSApp.isActive && w.isKeyWindow;
  // (not in front: what drawing holds given back, the frame shown kept; a frame after makes what it needs again)
  if (!front) mb_render_trim();
  state_cb((shown ? 1 : 0) | (front ? 2 : 0));
  [the_view requestFrame];
}

// Whether the system's appearance is dark (@hostapi.system_dark): the app's own (NSApp.appearance is never set, so this is
// the system's even while the window is made to look otherwise below).
// Words as the app sizes them (@hostapi.font_scale): the system's own size of words not followed here yet.
double mb_host_font_scale(void) { return 1.0; }
// What the app was started to be used with (@hostapi.native_pointing): a Mac's keyboard and mouse.
int32_t mb_host_native_pointing(void) { return 2; }
// Whether a keyboard is at hand (@hostapi.keyboard): a Mac's, always.
int32_t mb_host_keyboard(void) { return 1; }
// ---- the app's widgets for VoiceOver ----
// As Android's A11y.java and Windows' win_a11y.cpp give them: an element of each node the app last said (a11y.mbt's
// lines, @hostapi.a11y_tree), kept by its number from frame to frame (one whose node is gone is no element), under the
// view; its role by the node's, its label, value, help, state and frame on the screen. What is asked of it (press, a
// step up or down, words put in a field, focus, cancel) goes to the app on @hostapi.a11y_channel for its next frame.
// The app tells its widgets once something asked the view for them (VoiceOver, Voice Control, Accessibility
// Inspector); that first ask asks for a frame. As they change, the layout, the focus, a title or a value is said
// changed. MBUI_A11Y_SELFCHECK=1 (host_contract.sh mac a11y): the view's elements walked as VoiceOver walks them once
// told, each said ("A11Y node <role> <label>"), words put in the field named "A11YCHECK field" and the button named
// "A11YCHECK press" pressed through them.

@interface MBA11yNode : NSObject
@property(nonatomic) int nid, parent, widget;
@property(nonatomic, copy) NSString *role, *flags, *label, *value, *help, *actions;
@property(nonatomic) NSRect rect;
@property(nonatomic) BOOL range;
@property(nonatomic) double low, at, high;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *kids;
@end
@implementation MBA11yNode
@end

@interface MBA11yElement : NSAccessibilityElement
@property(nonatomic) int nid;
@end

static NSMutableDictionary<NSNumber *, MBA11yNode *> *a11y_nodes;
static NSArray<NSNumber *> *a11y_tops;
static NSMutableDictionary<NSNumber *, MBA11yElement *> *a11y_elements;
static int a11y_focus;
static BOOL a11y_asked, a11y_selfcheck_done;

static MBA11yElement *a11y_element(int nid) {
  if (!a11y_nodes[@(nid)]) return nil;
  if (!a11y_elements) a11y_elements = [NSMutableDictionary dictionary];
  MBA11yElement *e = a11y_elements[@(nid)];
  if (!e) {
    e = [MBA11yElement new];
    e.nid = nid;
    a11y_elements[@(nid)] = e;
  }
  return e;
}

static NSArray *a11y_elements_of(NSArray<NSNumber *> *ids) {
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:ids.count];
  for (NSNumber *n in ids) {
    MBA11yElement *e = a11y_element(n.intValue);
    if (e) [out addObject:e];
  }
  return out;
}

static NSArray *a11y_children_of_view(void) {
  if (!a11y_asked) {
    a11y_asked = YES;
    [the_view requestFrame];
  }
  return a11y_elements_of(a11y_tops ?: @[]);
}

static id a11y_hit(NSPoint screen) {
  if (!the_view.window) return nil;
  NSPoint p = [the_view convertPoint:[the_view.window convertPointFromScreen:screen] fromView:nil];
  int best = 0;
  double area = -1;
  for (MBA11yNode *n in a11y_nodes.allValues) {
    if (!NSPointInRect(p, n.rect)) continue;
    double a = n.rect.size.width * n.rect.size.height;
    if (area < 0 || a < area) area = a, best = n.nid;
  }
  return best ? a11y_element(best) : nil;
}

static id a11y_focused_element(void) { return a11y_focus ? a11y_element(a11y_focus) : nil; }

// what is asked of the node's widget, posted to the app (`text`: the words a set_text puts in it)
static void a11y_ask(MBA11yNode *n, NSString *action, NSString *text) {
  if (!n || !n.widget) return;
  NSMutableDictionary *m = [@{@"id" : @(n.widget), @"action" : action} mutableCopy];
  if (text) m[@"text"] = text;
  NSData *json = [NSJSONSerialization dataWithJSONObject:m options:0 error:nil];
  if (json) mb_post("a11y", (const char *)json.bytes, json.length, NULL, 0);
}

static BOOL a11y_has(NSString *letters, unichar c) {
  return [letters rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound;
}

@implementation MBA11yElement
- (MBA11yNode *)node {
  return a11y_nodes[@(self.nid)];
}
- (BOOL)isAccessibilityElement {
  return self.node != nil;
}
- (NSAccessibilityRole)accessibilityRole {
  static NSDictionary<NSString *, NSString *> *roles;
  if (!roles)
    roles = @{
      @"Text" : NSAccessibilityStaticTextRole, @"Status" : NSAccessibilityStaticTextRole,
      @"Option" : NSAccessibilityStaticTextRole, @"Heading" : @"AXHeading",
      @"Button" : NSAccessibilityButtonRole, @"Link" : NSAccessibilityLinkRole,
      @"Checkbox" : NSAccessibilityCheckBoxRole, @"Switch" : NSAccessibilityCheckBoxRole,
      @"Radio" : NSAccessibilityRadioButtonRole, @"Tab" : NSAccessibilityRadioButtonRole,
      @"Slider" : NSAccessibilitySliderRole, @"ProgressBar" : NSAccessibilityProgressIndicatorRole,
      @"TabList" : NSAccessibilityTabGroupRole, @"Tooltip" : NSAccessibilityHelpTagRole,
      @"Menu" : NSAccessibilityMenuRole, @"MenuBar" : NSAccessibilityMenuBarRole,
      @"MenuItem" : NSAccessibilityMenuItemRole, @"MenuItemCheckbox" : NSAccessibilityMenuItemRole,
      @"MenuItemRadio" : NSAccessibilityMenuItemRole, @"Listbox" : NSAccessibilityListRole,
      @"Combobox" : NSAccessibilityComboBoxRole, @"Toolbar" : NSAccessibilityToolbarRole,
      @"Image" : NSAccessibilityImageRole, @"TextField" : NSAccessibilityTextFieldRole,
      @"ScrollArea" : NSAccessibilityScrollAreaRole,
    };
  return roles[self.node.role] ?: NSAccessibilityGroupRole;
}
- (NSAccessibilitySubrole)accessibilitySubrole {
  NSString *r = self.node.role;
  if ([r isEqualToString:@"Switch"]) return NSAccessibilitySwitchSubrole;
  if ([r isEqualToString:@"Tab"]) return NSAccessibilityTabButtonSubrole;
  if ([r isEqualToString:@"Dialog"] || [r isEqualToString:@"AlertDialog"]) return NSAccessibilityDialogSubrole;
  return nil;
}
- (NSString *)accessibilityLabel {
  MBA11yNode *n = self.node;
  // (static text says its words as its value)
  if (!n || [self.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole]) return nil;
  return n.label.length ? n.label : nil;
}
- (id)accessibilityValue {
  MBA11yNode *n = self.node;
  if (!n) return nil;
  if (a11y_has(n.flags, 'c')) return @(a11y_has(n.flags, 'C') ? 1 : a11y_has(n.flags, 'M') ? 2 : 0);
  if ([n.role isEqualToString:@"Radio"] || [n.role isEqualToString:@"Tab"]) return @(a11y_has(n.flags, 's') ? 1 : 0);
  if (n.range) return @(n.at);
  if ([self.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole]) return n.label.length ? n.label : n.value;
  return n.value.length ? n.value : nil;
}
- (id)accessibilityMinValue {
  return self.node.range ? @(self.node.low) : nil;
}
- (id)accessibilityMaxValue {
  return self.node.range ? @(self.node.high) : nil;
}
- (NSString *)accessibilityHelp {
  NSString *h = self.node.help;
  return h.length ? h : nil;
}
- (BOOL)isAccessibilityEnabled {
  return !a11y_has(self.node.flags, 'd');
}
- (BOOL)isAccessibilityFocused {
  return a11y_has(self.node.flags, 'f');
}
- (BOOL)isAccessibilitySelected {
  return a11y_has(self.node.flags, 's');
}
- (BOOL)isAccessibilityExpanded {
  return a11y_has(self.node.flags, 'E');
}
- (NSRect)accessibilityFrame {
  MBA11yNode *n = self.node;
  if (!n || !the_view.window) return NSZeroRect;
  return [the_view.window convertRectToScreen:[the_view convertRect:n.rect toView:nil]];
}
- (id)accessibilityParent {
  MBA11yNode *n = self.node;
  return n && n.parent ? (a11y_element(n.parent) ?: (id)the_view) : (id)the_view;
}
- (NSArray *)accessibilityChildren {
  return a11y_elements_of(self.node.kids ?: @[]);
}
// what may be asked of it: what its node takes
- (BOOL)isAccessibilitySelectorAllowed:(SEL)sel {
  MBA11yNode *n = self.node;
  if (!n) return NO;
  if (sel == @selector(accessibilityPerformPress)) return a11y_has(n.actions, 'a');
  if (sel == @selector(accessibilityPerformIncrement)) return a11y_has(n.actions, 'i');
  if (sel == @selector(accessibilityPerformDecrement)) return a11y_has(n.actions, 'd');
  if (sel == @selector(accessibilityPerformCancel)) return a11y_has(n.actions, 'x');
  if (sel == @selector(setAccessibilityValue:)) return a11y_has(n.actions, 't');
  if (sel == @selector(setAccessibilityFocused:)) return a11y_has(n.actions, 'f');
  if (sel == @selector(setAccessibilityExpanded:)) return a11y_has(n.actions, 'e') || a11y_has(n.actions, 'c');
  return [super isAccessibilitySelectorAllowed:sel];
}
- (BOOL)accessibilityPerformPress {
  if (!a11y_has(self.node.actions, 'a')) return NO;
  a11y_ask(self.node, @"activate", nil);
  return YES;
}
- (BOOL)accessibilityPerformIncrement {
  if (!a11y_has(self.node.actions, 'i')) return NO;
  a11y_ask(self.node, @"increment", nil);
  return YES;
}
- (BOOL)accessibilityPerformDecrement {
  if (!a11y_has(self.node.actions, 'd')) return NO;
  a11y_ask(self.node, @"decrement", nil);
  return YES;
}
- (BOOL)accessibilityPerformCancel {
  if (!a11y_has(self.node.actions, 'x')) return NO;
  a11y_ask(self.node, @"dismiss", nil);
  return YES;
}
- (void)setAccessibilityValue:(id)v {
  if (a11y_has(self.node.actions, 't') && [v isKindOfClass:NSString.class]) a11y_ask(self.node, @"set_text", v);
}
- (void)setAccessibilityFocused:(BOOL)f {
  if (f && a11y_has(self.node.actions, 'f')) a11y_ask(self.node, @"focus", nil);
}
- (void)setAccessibilityExpanded:(BOOL)e {
  MBA11yNode *n = self.node;
  if (e == a11y_has(n.flags, 'E')) return;
  a11y_ask(n, e ? (a11y_has(n.actions, 'e') ? @"expand" : @"activate") : (a11y_has(n.actions, 'c') ? @"collapse" : @"activate"), nil);
}
@end

// MBUI_A11Y_SELFCHECK (see above): the elements as VoiceOver walks them, and the field and the button used through them
static void a11y_walk(NSArray *els, int depth, MBA11yElement **field, MBA11yElement **button) {
  for (MBA11yElement *e in els) {
    NSString *name = e.accessibilityLabel ?: ([e.accessibilityValue isKindOfClass:NSString.class] ? e.accessibilityValue : @"");
    printf("A11Y node %s %s\n", e.accessibilityRole.UTF8String, name.UTF8String);
    if ([e.node.label isEqualToString:@"A11YCHECK field"]) *field = e;
    if ([e.node.label isEqualToString:@"A11YCHECK press"]) *button = e;
    a11y_walk(e.accessibilityChildren, depth + 1, field, button);
  }
}
static void a11y_selfcheck(void) {
  MBA11yElement *field = nil, *button = nil;
  a11y_walk(the_view.accessibilityChildren, 0, &field, &button);
  if (!field || !button) return;
  a11y_selfcheck_done = YES;
  printf("A11Y field %s settable %d\n", field.accessibilityRole.UTF8String,
         [field isAccessibilitySelectorAllowed:@selector(setAccessibilityValue:)]);
  fflush(stdout);
  [field setAccessibilityValue:@"written by a reader"];
  [button accessibilityPerformPress];
}

// Whether something reads the widgets out (@hostapi.a11y_on): something asked the view for them (a self-check's run:
// asked from the start, as VoiceOver asks the view)
int32_t mb_host_a11y_on(void) {
  if (!a11y_asked && getenv("MBUI_A11Y_SELFCHECK")) (void)a11y_children_of_view();
  return a11y_asked ? 1 : 0;
}

// What the widgets are now (@hostapi.a11y_tree): the nodes made anew, what reads them told what changed
void mb_host_a11y_tree(moonbit_string_t s) {
  NSString *all = mb_ns_from_string(s);
  NSMutableDictionary<NSNumber *, MBA11yNode *> *next = [NSMutableDictionary dictionary];
  NSMutableArray<NSNumber *> *order = [NSMutableArray array], *tops = [NSMutableArray array];
  for (NSString *line in [all componentsSeparatedByString:@"\n"]) {
    NSArray<NSString *> *f = [line componentsSeparatedByString:@"\x1f"];
    if (f.count < 16) continue;
    MBA11yNode *n = [MBA11yNode new];
    n.nid = f[0].intValue, n.parent = f[1].intValue, n.widget = f[2].intValue;
    n.role = f[3], n.flags = f[4];
    n.rect = NSMakeRect(f[5].doubleValue, f[6].doubleValue, f[7].doubleValue, f[8].doubleValue);
    n.label = f[9], n.value = f[10], n.help = f[11];
    n.range = f[13].length > 0;
    n.low = f[12].doubleValue, n.at = f[13].doubleValue, n.high = f[14].doubleValue;
    n.actions = f[15];
    n.kids = [NSMutableArray array];
    if (!n.nid || next[@(n.nid)]) continue;
    next[@(n.nid)] = n;
    [order addObject:@(n.nid)];
  }
  int focus = 0;
  for (NSNumber *k in order) {
    MBA11yNode *n = next[k];
    MBA11yNode *p = n.parent ? next[@(n.parent)] : nil;
    if (p) [p.kids addObject:k];
    else n.parent = 0, [tops addObject:k];
    if (a11y_has(n.flags, 'f')) focus = n.nid;
  }
  NSDictionary<NSNumber *, MBA11yNode *> *old = a11y_nodes;
  BOOL shape = ![tops isEqualToArray:a11y_tops ?: @[]] || next.count != old.count;
  for (NSNumber *k in order) {
    MBA11yNode *n = next[k], *o = old[k];
    if (!o || o.parent != n.parent || ![o.kids isEqualToArray:n.kids]) shape = YES;
  }
  a11y_nodes = next;
  a11y_tops = tops;
  for (NSNumber *k in a11y_elements.allKeys)
    if (!next[k]) [a11y_elements removeObjectForKey:k];
  if (a11y_asked) {
    for (NSNumber *k in a11y_elements) {
      MBA11yNode *n = next[k], *o = old[k];
      if (!o) continue;
      if (![o.label isEqualToString:n.label]) NSAccessibilityPostNotification(a11y_elements[k], NSAccessibilityTitleChangedNotification);
      if (![o.value isEqualToString:n.value] || ![o.flags isEqualToString:n.flags] || o.at != n.at)
        NSAccessibilityPostNotification(a11y_elements[k], NSAccessibilityValueChangedNotification);
    }
    if (shape) NSAccessibilityPostNotification(the_view, NSAccessibilityLayoutChangedNotification);
    if (focus != a11y_focus && focus) NSAccessibilityPostNotification(a11y_element(focus), NSAccessibilityFocusedUIElementChangedNotification);
  }
  a11y_focus = focus;
  if (getenv("MBUI_A11Y_SELFCHECK") && !a11y_selfcheck_done) dispatch_async(dispatch_get_main_queue(), ^{
      a11y_selfcheck();
    });
}

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

// ---- Updates (@hostapi.app_version, update_fetch, update_apply, update_state) ----
// The app keeping itself current, as still.fail's desktop app does (Electron's autoUpdater; on macOS Squirrel's
// ShipIt): a newer build the core found (`app.update`: the release's zip) downloaded by itself into the app's caches
// (update_fetch), picking up where a cut connection left off (the bytes so far kept in `<name>.part`, the rest asked
// for as a range, a few times over with a growing pause while each try gets further: Android's Updates.java), checked
// against its size and SHA-256, unzipped beside the app (on its volume), and taken only when it is this app, newer,
// and signed as this one is (its signature valid and meeting this app's designated requirement: still.fail's team and
// this app's id; a build signed ad hoc, a developer's, takes none): ready. Asked to (update_apply), it is put in this
// app's place (the bundles swapped, this one's thrown away), and opened as this one quits (a shell waits for this
// process to end first: two cores never share the data); the app quit with one ready, it is put in place as it goes
// (update_at_quit), not opened. How it goes the app reads (`update_state`: the phase, how
// far, what went wrong, the build), told each time it changes (MB_OUTSIDE_UPDATE, id 1: 0 while the host works at it,
// 1 once it is ready, -1 failed). Only an app's bundle has a version here (a build run as a bare program, 0, never
// asks).

static NSString *update_phase = @"idle";  // idle | downloading | retrying | ready | installing | failed
static int update_percent = -1;
static NSString *update_error = @"";
static BOOL update_working;
// the build asked for (its file's name), and once ready, its app unzipped and checked beside this one
static NSString *update_file = @"";
static NSURL *update_staged;

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
    if ([phase isEqualToString:@"failed"] || [phase isEqualToString:@"ready"]) update_working = NO;
    if (changed) {
      mb_host_outside(MB_OUTSIDE_UPDATE, 1, [phase isEqualToString:@"failed"] ? -1 : [phase isEqualToString:@"ready"] ? 1 : 0);
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
  if (size > 0 && have > size) [fm removeItemAtPath:part error:NULL], have = 0;
  // how far from the first: what an earlier try kept (0 none), not "not known" till the first bytes come
  if (size > 0) update_say(@"downloading", (int)(have * 100 / size), nil);
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

// The zip unzipped beside this app (a folder the system gives for replacing it, on its volume) and its app checked:
// the app, or nil and why not.
static NSURL *update_stage(NSString *zip, NSString **why) {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSURL *here = NSBundle.mainBundle.bundleURL;
  NSError *e = nil;
  NSURL *stage = [fm URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:here
                              create:YES error:&e];
  if (!stage) {
    *why = [NSString stringWithFormat:@"can't write beside %@: %@", here.path, e.localizedDescription];
    return nil;
  }
  NSTask *unzip = [NSTask new];
  unzip.launchPath = @"/usr/bin/ditto";
  unzip.arguments = @[ @"-x", @"-k", zip, stage.path ];
  [unzip launch];
  [unzip waitUntilExit];
  NSURL *app = nil;
  for (NSURL *u in [fm contentsOfDirectoryAtURL:stage includingPropertiesForKeys:nil options:0 error:NULL])
    if ([u.pathExtension isEqualToString:@"app"]) app = u;
  NSBundle *b = app ? [NSBundle bundleWithURL:app] : nil;
  if (unzip.terminationStatus != 0 || !b) *why = @"incomplete";
  else if (![b.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier])
    *why = [NSString stringWithFormat:@"another app (%@)", b.bundleIdentifier];
  else if ([[b objectForInfoDictionaryKey:@"CFBundleVersion"] intValue] <= mb_host_app_version())
    *why = @"not newer";
  else update_signed_as_this(app, why);
  if (*why) {
    [fm removeItemAtURL:stage error:NULL];
    return nil;
  }
  return app;
}

// The app quitting with a build ready (the person never said 重启更新): put in its place as it goes, not opened (the
// next time the person opens the app, it is the newer build).
static void update_at_quit(void) {
  NSURL *app = update_staged;
  if (!app || ![update_phase isEqualToString:@"ready"]) return;
  update_staged = nil;
  NSFileManager *fm = NSFileManager.defaultManager;
  NSError *e = nil;
  if ([fm replaceItemAtURL:NSBundle.mainBundle.bundleURL withItemAtURL:app backupItemName:nil options:0
          resultingItemURL:NULL error:&e])
    update_log(@"in place as this one quits");
  else
    update_log([NSString stringWithFormat:@"not put in place as this one quits: %@", e.localizedDescription]);
  [fm removeItemAtURL:app.URLByDeletingLastPathComponent error:NULL];
}

void mb_host_update_fetch(moonbit_string_t url_s, moonbit_string_t sha256_s, double size, moonbit_string_t name_s,
                          int32_t now) {
  (void)now;  // (no network here costs more than another)
  if (update_working || mb_host_app_version() <= 0) return;
  NSURL *url = [NSURL URLWithString:mb_ns_from_string(url_s)];
  NSString *sha256 = mb_ns_from_string(sha256_s), *name = mb_ns_from_string(name_s).lastPathComponent;
  if (!url || !name.length) return;
  // (ready already, or being put in place)
  if ([name isEqualToString:update_file] && ([update_phase isEqualToString:@"ready"] || [update_phase isEqualToString:@"installing"]))
    return;
  if (update_staged) [NSFileManager.defaultManager removeItemAtURL:update_staged.URLByDeletingLastPathComponent error:NULL];
  update_staged = nil;
  update_working = YES;
  update_file = name;
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
    NSURL *app = zip ? update_stage(zip, &why) : nil;
    if (!app) {
      update_log([NSString stringWithFormat:@"failed: %@", why]);
      update_say(@"failed", -1, why);
      return;
    }
    update_log([NSString stringWithFormat:@"%@ ready", app.path]);
    dispatch_async(dispatch_get_main_queue(), ^{
      update_staged = app;
      static dispatch_once_t once;
      dispatch_once(&once, ^{
        atexit(update_at_quit);
      });
    });
    update_say(@"ready", -1, nil);
  });
}

void mb_host_update_apply(moonbit_string_t said) {
  (void)said;  // (opened again here: nothing to say)
  NSURL *app = update_staged;
  if (!app || ![update_phase isEqualToString:@"ready"]) return;
  update_staged = nil;
  update_phase = @"installing";
  update_percent = -1;
  mb_host_outside(MB_OUTSIDE_UPDATE, 1, 0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *here = NSBundle.mainBundle.bundleURL;
    NSError *e = nil;
    NSString *why = nil;
    if (![fm replaceItemAtURL:here withItemAtURL:app backupItemName:nil options:0 resultingItemURL:NULL error:&e])
      why = [NSString stringWithFormat:@"can't replace %@: %@", here.path, e.localizedDescription];
    [fm removeItemAtURL:app.URLByDeletingLastPathComponent error:NULL];
    if (why) {
      update_log([NSString stringWithFormat:@"failed: %@", why]);
      update_say(@"failed", -1, why);
      return;
    }
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    [fm removeItemAtPath:[[[caches stringByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier]
                             stringByAppendingPathComponent:@"updates"] stringByAppendingPathComponent:update_file]
                   error:NULL];
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
  NSDictionary *st =
      @{@"phase" : update_phase, @"percent" : @(update_percent), @"error" : update_error, @"file" : update_file};
  NSData *json = [NSJSONSerialization dataWithJSONObject:st options:0 error:NULL];
  return mb_string_from_ns([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"");
}

// Turned sideways for a film (@hostapi.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }
// Let turn as held (@hostapi.set_turnable): a window does not turn, and is not held upright.
int32_t mb_host_set_turnable(int32_t on) { (void)on; return 0; }

// The performance record (@hostapi.perf_state): none kept here (iOS keeps one, ios_app.m).
int32_t mb_host_perf_state(void) { return -1; }
void mb_host_set_perf(int32_t on) { (void)on; }
void mb_host_perf_line(moonbit_string_t line) { (void)line; }
moonbit_string_t mb_host_perf_where(void) { return moonbit_make_string_raw(0); }
double mb_host_perf_size(void) { return 0; }
moonbit_bytes_t mb_host_perf_read(void) { return moonbit_make_bytes(0, 0); }

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

// The system's own bars (@hostapi.nav_bar): none here, the app draws its own.
int32_t mb_host_nav_bar(moonbit_string_t spec) {
  (void)spec;
  return 0;
}

int32_t mb_host_nav_able(void) { return 0; }

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
// 1: ask it (1 when asked: not asked before); 2: its answer to the ask, once (1, 0; -1 none yet); 3: System Settings'
// Notifications opened (1); 4: the app's number shown on its icon (1: the Dock's tile, mb_host_set_badge).
int32_t mb_host_notice_state(int32_t what) {
  if (what == 0) return notice_allowed;
  if (what == 4) return 1;
  if (what == 2) {
    int32_t a = notice_answered;
    if (a >= 0) notice_answered = -1;
    return a;
  }
  if (what == 3) {
    NSURL *u = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"];
    return [NSWorkspace.sharedWorkspace openURL:u] ? 1 : 0;
  }
  if (what != 1) return 0;
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

// The CPU's time the whole process has had, every thread's (@hostapi.cpu_ms: MBUI_PROBE's share of a CPU), in ms.
double mb_host_cpu_ms(void) {
  struct rusage u;
  if (getrusage(RUSAGE_SELF, &u) != 0) return -1;
  return (u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1000.0 + (u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1000.0;
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
// A drop's files: read once the app first asks how its pick goes (mb_host_pick_state: ui/drop.mbt take_drop, as a
// view takes them as files); taken as their paths, or by nothing, never (mb_host_pick_end).
static void drop_pick_read(int32_t pid, NSArray<NSURL *> *urls);

static int32_t drop_pick(NSArray<NSURL *> *urls) {
  if (!picks) picks = [NSMutableDictionary new];
  int32_t pid = next_pick++;
  picks[@(pid)] = [@{@"state" : @0, @"urls" : urls} mutableCopy];
  return pid;
}

static void drop_pick_read(int32_t pid, NSArray<NSURL *> *urls) {
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
  if (!p) return -1;
  // (a drop's files, asked for: read from now, drop_pick)
  NSArray<NSURL *> *urls = p[@"urls"];
  if (urls) {
    [p removeObjectForKey:@"urls"];
    drop_pick_read(pid, urls);
  }
  return [p[@"state"] intValue];
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
