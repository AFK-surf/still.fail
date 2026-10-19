// macOS host: an NSWindow whose view is a CAMetalLayer, frames from the
// view's display link, input from AppKit, and the system input method
// through NSTextInputClient.
#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import "apple.h"

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
static int bench_mode;
static const char *shot_path;
static const char *script;

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
- (BOOL)wantsUpdateLayer { return YES; }

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window) return;
  self.link = [self displayLinkWithTarget:self selector:@selector(tick:)];
  [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  [self addTrackingArea:[[NSTrackingArea alloc]
                            initWithRect:NSZeroRect
                                 options:NSTrackingMouseMoved | NSTrackingActiveAlways |
                                         NSTrackingInVisibleRect
                                   owner:self
                                userInfo:nil]];
  [self requestFrame];
}

- (void)requestFrame {
  self.wantFrame = YES;
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

- (void)drawFrame {
  NSSize s = self.bounds.size;
  double scale = self.window.backingScaleFactor ?: 2.0;
  ((CAMetalLayer *)self.layer).contentsScale = scale;
  mb_text_scale = scale;
  mb_render_set_size(s.width, s.height, scale);
  self.wantFrame = NO;
  mb_cb.frame(s.width, s.height, scale, mb_now_ms());
}

static int frames_drawn;

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
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self pt:e];
  [self.window makeFirstResponder:self];
  mouse(0, p, e);
}
- (void)mouseDragged:(NSEvent *)e {
  mouse(1, [self pt:e], e);
}
- (void)mouseMoved:(NSEvent *)e {
  mouse(1, [self pt:e], e);
}
- (void)mouseUp:(NSEvent *)e {
  mouse(2, [self pt:e], e);
}
- (void)otherMouseUp:(NSEvent *)e {
  if (e.buttonNumber == 3) go_back();
}
- (void)scrollWheel:(NSEvent *)e {
  NSPoint p = [self pt:e];
  double dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 12.0;
  double dx = e.hasPreciseScrollingDeltas ? e.scrollingDeltaX : e.scrollingDeltaX * 12.0;
  int phase = e.momentumPhase != NSEventPhaseNone ? 3 : (e.phase != NSEventPhaseNone ? 1 : 0);
  mb_cb.wheel(p.x, p.y, -dx, -dy, phase);
}

// ---- keys ----

- (void)keyDown:(NSEvent *)e {
  NSEventModifierFlags m = e.modifierFlags;
  int mods = ((m & NSEventModifierFlagShift) ? 1 : 0) | ((m & NSEventModifierFlagControl) ? 2 : 0) |
             ((m & NSEventModifierFlagOption) ? 4 : 0) | ((m & NSEventModifierFlagCommand) ? 8 : 0);
  if (m & NSEventModifierFlagCommand) {
    NSString *c = e.charactersIgnoringModifiers.lowercaseString;
    if ([c isEqualToString:@"q"]) [NSApp terminate:nil];
    else if ([c isEqualToString:@"["]) go_back();
    else if ([c isEqualToString:@"a"]) mb_cb.key(12, mods);
    else if ([c isEqualToString:@"c"]) mb_cb.key(13, mods);
    else if ([c isEqualToString:@"x"]) mb_cb.key(14, mods);
    else if ([c isEqualToString:@"v"]) {
      NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
      if (s.length) send_text(0, s, 0, 0);
    }
    return;
  }
  if (self.imeActive) {
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
    [v requestFrame];
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
    [v requestFrame];
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
    [v requestFrame];
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
    [v requestFrame];
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
    [v requestFrame];
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
    [v requestFrame];
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
    [v requestFrame];
  } else if (strcmp(script, "shot") == 0) {
    // MBUI_SHOT_AT: the frame to take it at (later for what waits on something, as the core's first answers)
    static int at;
    if (!at) at = getenv("MBUI_SHOT_AT") ? atoi(getenv("MBUI_SHOT_AT")) : 30;
    if (step == at) shot(getenv("MBUI_SHOT_NAME") ?: "main");
    if (step == at + 1) exit(0);
    [v requestFrame];
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer,
                 mb_wheel_fn wheel, mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer, wheel, key, text};
  shot_path = getenv("MBUI_SHOT_DIR");
  script = getenv("MBUI_SCRIPT");
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    // MBUI_WIN=<w>x<h>: the window's size (a phone's, for the narrow layouts)
    double ww = 900, wh = 720;
    const char *win = getenv("MBUI_WIN");
    if (win) sscanf(win, "%lfx%lf", &ww, &wh);
    NSRect r = NSMakeRect(120, 120, ww, wh);
    NSWindow *w = [[NSWindow alloc]
        initWithContentRect:r
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    w.title = mb_ns_from_string(title);
    the_view = [[MBView alloc] initWithFrame:r];
    w.contentView = the_view;
    [w makeKeyAndOrderFront:nil];
    [w makeFirstResponder:the_view];
    [NSApp activateIgnoringOtherApps:YES];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                      object:w
                                                       queue:nil
                                                  usingBlock:^(NSNotification *n) { exit(0); }];
    [NSApp run];
  }
}

double mb_host_now(void) { return mb_now_ms(); }

double mb_host_event_time(void) { return event_time; }

int32_t mb_host_platform(void) { return 0; }

void mb_host_request_frame(void) { [the_view requestFrame]; }

void mb_host_wake_after(double ms) {
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

void mb_host_log(moonbit_string_t s) {
  fprintf(stdout, "%s\n", mb_ns_from_string(s).UTF8String);
  fflush(stdout);
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
        [the_view requestFrame];
      }
    };
    if (the_view.window) [panel beginSheetModalForWindow:the_view.window completionHandler:done];
    else [panel beginWithCompletionHandler:done];
  });
  return pid;
}

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
