// macOS host: an NSWindow whose view is a CAMetalLayer, frames from the
// view's display link, input from AppKit, and the system input method
// through NSTextInputClient.
#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import "apple.h"

mb_callbacks mb_cb;

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

CTFontRef mb_platform_font(double size, int weight) {
  NSFontWeight w = weight >= 700 ? NSFontWeightBold
                   : weight >= 600 ? NSFontWeightSemibold
                   : weight >= 500 ? NSFontWeightMedium
                                   : NSFontWeightRegular;
  NSFont *f = [NSFont systemFontOfSize:size weight:w];
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
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self pt:e];
  [self.window makeFirstResponder:self];
  mb_cb.pointer(0, p.x, p.y, 0);
}
- (void)mouseDragged:(NSEvent *)e {
  NSPoint p = [self pt:e];
  mb_cb.pointer(1, p.x, p.y, 0);
}
- (void)mouseMoved:(NSEvent *)e {
  NSPoint p = [self pt:e];
  mb_cb.pointer(1, p.x, p.y, 0);
}
- (void)mouseUp:(NSEvent *)e {
  NSPoint p = [self pt:e];
  mb_cb.pointer(2, p.x, p.y, 0);
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
    else if ([c isEqualToString:@"a"]) mb_cb.key(12, mods);
    else if ([c isEqualToString:@"c"]) mb_cb.key(13, mods);
    else if ([c isEqualToString:@"x"]) mb_cb.key(14, mods);
    else if ([c isEqualToString:@"v"]) {
      NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
      if (s.length) send_text(0, s, 0, 0);
    }
    return;
  }
  if (self.imeActive) [self interpretKeyEvents:@[ e ]];
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
  } else if (strcmp(script, "shot") == 0) {
    if (step == 30) shot("main");
    if (step == 31) exit(0);
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
    NSRect r = NSMakeRect(120, 120, 900, 720);
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

double mb_host_mem_bytes(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return 0;
  return (double)info.phys_footprint;
}
