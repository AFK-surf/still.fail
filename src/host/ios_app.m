// iOS host: a UIView whose layer is a CAMetalLayer, frames from a display
// link, touches as pointer events, and the system keyboard and input
// methods through UITextInput. Built by scripts/ios.sh, not by moon. Under
// it, as big, the native views' view (apple_views.m).
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <mach/mach.h>
#import <os/log.h>
#import "apple.h"
#include "post.h"

mb_callbacks mb_cb;

@interface MBPos : UITextPosition
@property(nonatomic) NSInteger i;
+ (instancetype)at:(NSInteger)i;
@end
@implementation MBPos
+ (instancetype)at:(NSInteger)i {
  MBPos *p = [MBPos new];
  p.i = i;
  return p;
}
@end

@interface MBRange : UITextRange
@property(nonatomic) NSInteger a, b;
+ (instancetype)from:(NSInteger)a to:(NSInteger)b;
@end
@implementation MBRange
+ (instancetype)from:(NSInteger)a to:(NSInteger)b {
  MBRange *r = [MBRange new];
  r.a = MIN(a, b);
  r.b = MAX(a, b);
  return r;
}
- (UITextPosition *)start { return [MBPos at:self.a]; }
- (UITextPosition *)end { return [MBPos at:self.b]; }
- (BOOL)isEmpty { return self.a == self.b; }
@end

@interface MBView : UIView <UITextInput>
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic) BOOL wantFrame;
@property(nonatomic) BOOL imeActive;
@property(nonatomic) CGRect caretRect;
// the field's text as the input method sees it, composition included
@property(nonatomic, copy) NSString *doc;
@property(nonatomic) NSRange sel;
@property(nonatomic) NSRange marked;
@property(nonatomic, weak) id<UITextInputDelegate> inputDelegate;
@property(nonatomic, strong) UITextInputStringTokenizer *tok;
@property(nonatomic, copy) NSDictionary *markedTextStyle;
@end

static MBView *the_view;
static const char *script;
static void say(NSString *s);
static int frames_drawn;

double mb_now_ms(void) { return CACurrentMediaTime() * 1000.0; }

CTFontRef mb_platform_font(double size, int weight, int mono) {
  UIFontWeight w = weight >= 700 ? UIFontWeightBold
                   : weight >= 600 ? UIFontWeightSemibold
                   : weight >= 500 ? UIFontWeightMedium
                                   : UIFontWeightRegular;
  UIFont *f = mono ? [UIFont monospacedSystemFontOfSize:size weight:w] : [UIFont systemFontOfSize:size weight:w];
  return (CTFontRef)CFBridgingRetain(f);
}

static void send_text(int kind, NSString *s, int a, int b) {
  mb_cb.text(kind, mb_string_from_ns(s ?: @""), a, b);
}

static void run_script_step(int step);

@implementation MBView

+ (Class)layerClass { return [CAMetalLayer class]; }

- (instancetype)initWithFrame:(CGRect)f {
  self = [super initWithFrame:f];
  mb_render_init((CAMetalLayer *)self.layer);
  self.doc = @"";
  self.marked = NSMakeRange(NSNotFound, 0);
  self.tok = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
  // a second finger told too (a pinch: 4 down, 5 moved, 6 up), as Android's MBView tells it
  self.multipleTouchEnabled = YES;
  self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  self.link.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
  [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  return self;
}

- (void)requestFrame {
  self.wantFrame = YES;
  self.link.paused = NO;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self requestFrame];
}

// a touch on a web view shown under the canvas goes to it
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
  if (mb_views_pass_through(p.x, p.y)) return nil;
  return [super hitTest:p withEvent:e];
}

- (void)tick:(CADisplayLink *)l {
  if (!self.wantFrame) {
    l.paused = YES;
    return;
  }
  CGSize s = self.bounds.size;
  double scale = self.window.screen.scale ?: 3.0;
  self.layer.contentsScale = scale;
  mb_text_scale = scale;
  mb_render_set_size(s.width, s.height, scale);
  self.wantFrame = NO;
  double t0 = frames_drawn == 0 ? mb_now_ms() : 0;
  // the frame's time is the display's: when this frame will be on screen (the display link's target, on
  // CACurrentMediaTime's clock as the touches' times are), as Android's is its vsync's, not when it happens to be built
  mb_cb.frame(s.width, s.height, scale, l.targetTimestamp * 1000.0);
  if (frames_drawn == 0)
    say([NSString stringWithFormat:@"ios: first frame %.0fx%.0f @%.0fx in %.0f ms", s.width, s.height, scale, mb_now_ms() - t0]);
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
  if (!self.wantFrame) l.paused = YES;
}

// ---- touch ----

// Each touch at its own time (UITouch.timestamp: seconds since startup, CACurrentMediaTime's clock), which MoonBit
// asks for while handling it; a move with the samples coalesced into it (120 Hz digitizers), each at its time.
static double event_time = -1;
static void touch(int kind, UITouch *t, UIView *v) {
  CGPoint p = [t locationInView:v];
  event_time = t.timestamp * 1000.0;
  mb_cb.pointer(kind, p.x, p.y, 0);
  event_time = -1;
}
// The first finger is the pointer (0 down, 1 moved, 2 up, 3 cancelled); a second one is told apart (4 down, 5 moved,
// 6 up) for a pinch, a third and on not at all. The first lifted while a second is down: the pinch ends (6, where the
// first was) and the one left becomes the first, its moves coming as the first's.
static __weak UITouch *first_touch, *second_touch;
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  for (UITouch *u in t) {
    if (!first_touch) {
      first_touch = u;
      touch(0, u, self);
    } else if (!second_touch) {
      second_touch = u;
      touch(4, u, self);
    }
  }
}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  UITouch *u = first_touch && [t containsObject:first_touch] ? first_touch : nil;
  if (u) {
    NSArray<UITouch *> *all = [e coalescedTouchesForTouch:u];
    if (all.count == 0) all = @[ u ];
    for (UITouch *c in all) touch(1, c, self);
  }
  if (second_touch && [t containsObject:second_touch]) touch(5, second_touch, self);
}
static void touch_gone(int end, NSSet<UITouch *> *t, UIView *v) {
  if (second_touch && [t containsObject:second_touch]) {
    touch(6, second_touch, v);
    second_touch = nil;
  }
  if (first_touch && [t containsObject:first_touch]) {
    if (second_touch) {
      touch(6, first_touch, v);
      first_touch = second_touch;
      second_touch = nil;
    } else {
      touch(end, first_touch, v);
      first_touch = nil;
    }
  }
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  touch_gone(2, t, self);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  touch_gone(3, t, self);
}

// ---- hardware keys ----

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  BOOL handled = NO;
  for (UIPress *p in presses) {
    if (!p.key || !self.imeActive || self.marked.location != NSNotFound) continue;
    int mods = (p.key.modifierFlags & UIKeyModifierShift) ? 1 : 0;
    int code = 0;
    switch (p.key.keyCode) {
      case UIKeyboardHIDUsageKeyboardLeftArrow: code = 3; break;
      case UIKeyboardHIDUsageKeyboardRightArrow: code = 4; break;
      case UIKeyboardHIDUsageKeyboardUpArrow: code = 5; break;
      case UIKeyboardHIDUsageKeyboardDownArrow: code = 6; break;
      default: break;
    }
    if (code) {
      mb_cb.key(code, mods);
      handled = YES;
    }
  }
  if (!handled) [super pressesBegan:presses withEvent:event];
}

// ---- UITextInput ----

- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return self.doc.length > 0; }

- (void)insertText:(NSString *)text {
  if ([text isEqualToString:@"\n"]) {
    if (self.marked.location != NSNotFound) send_text(2, @"", 0, 0);
    mb_cb.key(7, 0);
    return;
  }
  self.marked = NSMakeRange(NSNotFound, 0);
  send_text(0, text, 0, 0);
}

- (void)deleteBackward {
  if (self.marked.location != NSNotFound) {
    send_text(1, @"", 0, 0);
    self.marked = NSMakeRange(NSNotFound, 0);
    return;
  }
  mb_cb.key(1, 0);
}

- (NSString *)textInRange:(UITextRange *)range {
  MBRange *r = (MBRange *)range;
  NSInteger a = MAX(0, MIN(r.a, (NSInteger)self.doc.length));
  NSInteger b = MAX(a, MIN(r.b, (NSInteger)self.doc.length));
  return [self.doc substringWithRange:NSMakeRange(a, b - a)];
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
  MBRange *r = (MBRange *)range;
  send_text(3, @"", (int)r.a, (int)r.b);
  send_text(0, text, 0, 0);
}

- (UITextRange *)selectedTextRange {
  return [MBRange from:self.sel.location to:self.sel.location + self.sel.length];
}
- (void)setSelectedTextRange:(UITextRange *)range {
  MBRange *r = (MBRange *)range;
  if (self.marked.location != NSNotFound) return;
  self.sel = NSMakeRange(r.a, r.b - r.a);
  send_text(3, @"", (int)r.a, (int)r.b);
}

- (UITextRange *)markedTextRange {
  if (self.marked.location == NSNotFound) return nil;
  return [MBRange from:self.marked.location to:self.marked.location + self.marked.length];
}

- (void)setMarkedText:(NSString *)text selectedRange:(NSRange)sel {
  NSString *t = text ?: @"";
  NSUInteger start = self.marked.location != NSNotFound ? self.marked.location : self.sel.location;
  NSUInteger oldLen = self.marked.location != NSNotFound ? self.marked.length : self.sel.length;
  NSString *base = self.doc;
  if (start + oldLen <= base.length)
    self.doc = [base stringByReplacingCharactersInRange:NSMakeRange(start, oldLen) withString:t];
  self.marked = t.length ? NSMakeRange(start, t.length) : NSMakeRange(NSNotFound, 0);
  self.sel = NSMakeRange(start + sel.location, sel.length);
  send_text(1, t, (int)sel.location, (int)sel.length);
}

- (void)unmarkText {
  if (self.marked.location == NSNotFound) return;
  self.marked = NSMakeRange(NSNotFound, 0);
  send_text(2, @"", 0, 0);
}

- (UITextPosition *)beginningOfDocument { return [MBPos at:0]; }
- (UITextPosition *)endOfDocument { return [MBPos at:self.doc.length]; }

- (UITextRange *)textRangeFromPosition:(UITextPosition *)a toPosition:(UITextPosition *)b {
  return [MBRange from:((MBPos *)a).i to:((MBPos *)b).i];
}
- (UITextPosition *)positionFromPosition:(UITextPosition *)p offset:(NSInteger)o {
  NSInteger i = ((MBPos *)p).i + o;
  if (i < 0 || i > (NSInteger)self.doc.length) return nil;
  return [MBPos at:i];
}
- (UITextPosition *)positionFromPosition:(UITextPosition *)p
                             inDirection:(UITextLayoutDirection)d
                                  offset:(NSInteger)o {
  NSInteger s = (d == UITextLayoutDirectionLeft || d == UITextLayoutDirectionUp) ? -o : o;
  return [self positionFromPosition:p offset:s];
}
- (NSComparisonResult)comparePosition:(UITextPosition *)a toPosition:(UITextPosition *)b {
  NSInteger x = ((MBPos *)a).i, y = ((MBPos *)b).i;
  return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
}
- (NSInteger)offsetFromPosition:(UITextPosition *)a toPosition:(UITextPosition *)b {
  return ((MBPos *)b).i - ((MBPos *)a).i;
}
- (id<UITextInputTokenizer>)tokenizer { return self.tok; }
- (UITextPosition *)positionWithinRange:(UITextRange *)range farthestInDirection:(UITextLayoutDirection)d {
  MBRange *r = (MBRange *)range;
  return [MBPos at:(d == UITextLayoutDirectionLeft || d == UITextLayoutDirectionUp) ? r.a : r.b];
}
- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)p inDirection:(UITextLayoutDirection)d {
  NSInteger i = ((MBPos *)p).i;
  return [MBRange from:i to:i];
}
- (NSWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)p
                                          inDirection:(UITextStorageDirection)d {
  return NSWritingDirectionLeftToRight;
}
- (void)setBaseWritingDirection:(NSWritingDirection)w forRange:(UITextRange *)r {}
- (CGRect)firstRectForRange:(UITextRange *)r { return self.caretRect; }
- (CGRect)caretRectForPosition:(UITextPosition *)p { return self.caretRect; }
- (NSArray<UITextSelectionRect *> *)selectionRectsForRange:(UITextRange *)r { return @[]; }
- (UITextPosition *)closestPositionToPoint:(CGPoint)p { return [MBPos at:self.sel.location]; }
- (UITextPosition *)closestPositionToPoint:(CGPoint)p withinRange:(UITextRange *)r {
  return [MBPos at:((MBRange *)r).a];
}
- (UITextRange *)characterRangeAtPoint:(CGPoint)p { return nil; }
// The system's paste (the edit menu, a hardware keyboard's Cmd+V, a scripted run's): the clipboard's words put in as
// typed, as macOS's Cmd+V and Android's KEYCODE_PASTE do (a long paste is the app's to take: the editor's paste_limit).
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
  if (action == @selector(paste:)) return self.imeActive && UIPasteboard.generalPasteboard.hasStrings;
  return [super canPerformAction:action withSender:sender];
}
- (void)paste:(id)sender {
  NSString *s = UIPasteboard.generalPasteboard.string;
  if (s.length) send_text(0, s, 0, 0);
}
- (UIKeyboardType)keyboardType { return UIKeyboardTypeDefault; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UIReturnKeyType)returnKeyType { return UIReturnKeySend; }

@end

// ---------------------------------------------------------------------------

@interface MBController : UIViewController
@property(nonatomic, strong) NSLayoutConstraint *bottom;
@property(nonatomic) BOOL dark;
@end

static MBController *the_controller;

@implementation MBController
// the status bar's words light over the app drawn dark, dark over it drawn light (@host.set_dark)
- (UIStatusBarStyle)preferredStatusBarStyle {
  return self.dark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
}
- (void)loadView {
  UIView *root = [UIView new];
  root.backgroundColor = [UIColor colorWithRed:0.961 green:0.961 blue:0.969 alpha:1];
  self.view = root;
  the_view = [[MBView alloc] initWithFrame:CGRectZero];
  the_view.translatesAutoresizingMaskIntoConstraints = NO;
  the_view.opaque = NO;  // the native views under it show through its holes
  UIView *under = mb_views_root(CGRectZero);
  under.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:under];
  [root addSubview:the_view];
  UILayoutGuide *g = root.safeAreaLayoutGuide;
  // the view ends above the keyboard
  self.bottom = [the_view.bottomAnchor constraintEqualToAnchor:root.keyboardLayoutGuide.topAnchor];
  [NSLayoutConstraint activateConstraints:@[
    [the_view.topAnchor constraintEqualToAnchor:g.topAnchor],
    [the_view.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
    [the_view.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
    self.bottom,
    [under.topAnchor constraintEqualToAnchor:the_view.topAnchor],
    [under.bottomAnchor constraintEqualToAnchor:the_view.bottomAnchor],
    [under.leadingAnchor constraintEqualToAnchor:the_view.leadingAnchor],
    [under.trailingAnchor constraintEqualToAnchor:the_view.trailingAnchor],
  ]];
}
@end

// The app's one window, in the scene the system connects (the UIScene life cycle, which iOS 26 asks every app for:
// the Info.plist's UIApplicationSceneManifest names MBSceneDelegate).
@interface MBSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation MBSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)opts {
  if (![scene isKindOfClass:UIWindowScene.class]) return;
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  the_controller = [MBController new];
  self.window.rootViewController = the_controller;
  [self.window makeKeyAndVisible];
  [the_view requestFrame];
  // (a runner waits on these lines: the app up, then its first frame drawn)
  say(@"ios: launched");
}
@end

@interface MBAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation MBAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
  return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)app
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)opts {
  UISceneConfiguration *c = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
  c.delegateClass = MBSceneDelegate.class;
  return c;
}
@end

// ---------------------------------------------------------------------------
// Scripted runs (MBUI_SCRIPT=ime), as on macOS; snapshots go to MBUI_SHOT_DIR
// or the app's tmp directory.

static void shot(const char *name) {
  const char *dir = getenv("MBUI_SHOT_DIR");
  NSString *d = dir ? @(dir) : NSTemporaryDirectory();
  NSString *p = [d stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png", name]];
  int ok = mb_render_snapshot(p.UTF8String);
  say([NSString stringWithFormat:@"SHOT %@ %s", p, ok ? "ok" : "failed"]);
}

static void run_script_step(int step) {
  MBView *v = the_view;
  CGSize s = v.bounds.size;
  if (strcmp(script, "ime") == 0) {
    switch (step) {
      case 20: shot("01-start"); break;
      case 21:
        mb_cb.pointer(0, 100, s.height - 30, 0);
        mb_cb.pointer(2, 100, s.height - 30, 0);
        break;
      case 60: [v setMarkedText:@"ni'hao" selectedRange:NSMakeRange(6, 0)]; break;
      case 80: shot("02-composing"); break;
      // the keyboard commits a candidate by inserting it over the composition
      case 81: [v insertText:@"你好"]; break;
      case 82: [v setMarkedText:@"shi'jie" selectedRange:NSMakeRange(7, 0)]; break;
      case 83: [v insertText:@"世界，MoonBit 👋"]; break;
      case 100: shot("03-typed"); break;
      case 101: [v insertText:@"\n"]; break;
      case 160: shot("04-sent"); break;
      case 161:  // focus again so the system keyboard shows for the screenshot
        mb_cb.pointer(0, 100, s.height - 30, 0);
        mb_cb.pointer(2, 100, s.height - 30, 0);
        break;
      default: break;
    }
    [v requestFrame];
  } else if (strcmp(script, "shot") == 0) {
    if (step == 30) shot("main");
    [v requestFrame];
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer,
                 mb_wheel_fn wheel, mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer, wheel, key, text};
  script = getenv("MBUI_SCRIPT");
  @autoreleasepool {
    char *argv[] = {"mbui", NULL};
    UIApplicationMain(1, argv, nil, NSStringFromClass([MBAppDelegate class]));
  }
}

double mb_host_now(void) { return mb_now_ms(); }

// The time of day (host_native.mbt's wall_ms).
double mb_host_wall_ms(void) { return [[NSDate date] timeIntervalSince1970] * 1000.0; }

double mb_host_event_time(void) { return event_time; }

int32_t mb_host_platform(void) { return 1; }

void mb_host_request_frame(void) { [the_view requestFrame]; }

// A message posted from outside the frames (post.h), on whatever thread: its frame asked for on the main thread.
static void mb_post_wake(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    mb_host_request_frame();
  });
}

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
  BOOL was = v.imeActive;
  v.imeActive = active != 0;
  v.caretRect = CGRectMake(x, y, w, h);
  if (v.marked.location == NSNotFound) {
    [v.inputDelegate textWillChange:v];
    v.doc = mb_ns_from_string(text);
    v.sel = NSMakeRange(a, b - a);
    [v.inputDelegate textDidChange:v];
  }
  if (v.imeActive && !was) [v becomeFirstResponder];
  if (!v.imeActive && was) [v resignFirstResponder];
}

void mb_host_clipboard_set(moonbit_string_t s) {
  UIPasteboard.generalPasteboard.string = mb_ns_from_string(s);
}

// The app's log: the system's (os_log, `log stream`) and stderr as it is (unbuffered: `simctl launch --stderr`, which a
// scripted run reads line by line as the app goes: scripts/ios.sh run, still.fail's e2e).
static void say(NSString *s) {
  const char *c = s.UTF8String ?: "";
  os_log(OS_LOG_DEFAULT, "%{public}s", c);
  fprintf(stderr, "%s\n", c);
}

void mb_host_log(moonbit_string_t s) { say(mb_ns_from_string(s)); }

// A URL handed to the system (@host.open_url): UIApplication, Safari or the app that takes it.
int32_t mb_host_open_url(moonbit_string_t s) {
  NSString *u = mb_ns_from_string(s);
  NSURL *url = [NSURL URLWithString:u];
  NSLog(@"open-url: %@", u);
  if (!url || !url.scheme) return 0;
  [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
  return 1;
}

int32_t mb_host_reduce_motion(void) { return UIAccessibilityIsReduceMotionEnabled() ? 1 : 0; }

// What the host did for the app, told as it is done (apple.h's mb_host_outside: images, native views).
static mb_outside_fn outside_cb;
int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}
// How many of the app's asks are not answered yet, as the frame just built left it (host_native.mbt's
// frame_awaiting): nothing here waits on it yet.
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) {
  (void)awaiting;
  (void)what;
}
void mb_host_outside(int32_t kind, int32_t id, int32_t state) {
  if (outside_cb) outside_cb(kind, id, state);
}

int32_t mb_host_bench_mode(void) {
  const char *b = getenv("MBUI_BENCH");
  return b ? atoi(b) : 0;
}

void mb_host_exit(int32_t code) { exit(code); }

// The system's Reduce Transparency (glass drawn solid).
int32_t mb_host_reduce_transparency(void) { return UIAccessibilityIsReduceTransparencyEnabled() ? 1 : 0; }

double mb_host_mem_bytes(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return 0;
  return (double)info.phys_footprint;
}

// Back (host_native.mbt `set_back`): iOS has no system back of its own; the left edge's swipe back is the app's, a
// page's own (src/ui/nav.mbt: from the touches, within 20 points of the edge, as UINavigationController's), so nothing
// is told from here. Kept for a hardware keyboard's later.
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);
static mb_back_fn back_cb;
static int back_on;
void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

// The app in front or not (@host.set_app_state): 1 while its scene is on screen (in front, or behind the app switcher or
// a system sheet), | 2 while it is also active; told as that changes.
static void (*state_cb)(int32_t);
static void tell_state(void) {
  UIApplicationState a = UIApplication.sharedApplication.applicationState;
  int shown = a != UIApplicationStateBackground;
  int front = a == UIApplicationStateActive;
  static int told = -1;
  if (((shown ? 1 : 0) | (front ? 2 : 0)) != told) {
    told = (shown ? 1 : 0) | (front ? 2 : 0);
    say([NSString stringWithFormat:@"ios: %s", front ? "active" : shown ? "inactive" : "in the background"]);
  }
  if (!state_cb) return;
  state_cb((shown ? 1 : 0) | (front ? 2 : 0));
  [the_view requestFrame];
}
void mb_host_set_app_state(void (*f)(int32_t)) {
  state_cb = f;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSNotificationName n in @[ UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                    UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification ]) {
      [nc addObserverForName:n object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        // (WillEnterForeground comes before the state changes: told again once it has)
        dispatch_async(dispatch_get_main_queue(), ^{ tell_state(); });
      }];
    }
  });
  dispatch_async(dispatch_get_main_queue(), ^{ tell_state(); });
}

// Whether the system is set to dark (@host.system_dark): the screen's interface style.
int32_t mb_host_system_dark(void) {
  return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0;
}

// Sharing out (@host.share): the system's share sheet over the app, the words or the file (kept in a folder of the app's
// own in its temporary directory). Nothing comes in (shared_in ""): that is a share extension's, not made yet.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)mime;
  if (!the_controller) return 0;
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
  UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[ item ] applicationActivities:nil];
  sheet.popoverPresentationController.sourceView = the_view;
  sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(the_view.bounds), CGRectGetMidY(the_view.bounds), 1, 1);
  [the_controller presentViewController:sheet animated:YES completion:nil];
  say([NSString stringWithFormat:@"share: %s to the system's share sheet", n > 0 ? "a file" : "words"]);
  return 1;
}
moonbit_string_t mb_host_shared_in(void) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_shared_in_file(int32_t i) { (void)i; return moonbit_make_bytes(0, 0); }

// Updates (@host.app_version, update_install, update_state): this app does not update itself here.
int32_t mb_host_app_version(void) { return 0; }
void mb_host_update_install(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name) {
  (void)url; (void)sha256; (void)size; (void)name;
}
moonbit_string_t mb_host_update_state(void) { return moonbit_make_string_raw(0); }

// Turned sideways for a film (@host.set_sideways): the iPhone app does not turn yet.
void mb_host_set_sideways(int32_t on) { (void)on; }

// The app drawn dark or light (@host.set_dark): what shows under the status bar and the home indicator (the app's view
// is inside the safe area) the dark page's ground or the light one's, the status bar's words over it to match.
void mb_host_set_dark(int32_t dark) {
  MBController *c = the_controller;
  if (!c || c.dark == (dark != 0)) return;
  c.dark = dark != 0;
  c.view.backgroundColor = dark ? [UIColor colorWithRed:0x1B / 255.0 green:0x1C / 255.0 blue:0x1F / 255.0 alpha:1]
                                : [UIColor colorWithRed:0.961 green:0.961 blue:0.969 alpha:1];
  [c setNeedsStatusBarAppearanceUpdate];
}

// Notifications (notify.mbt): not the system's yet (UNUserNotificationCenter, and APNs for pushes, are a later
// slice's: they want the person's leave, asked in a system alert, and APNs a signed app). What would be shown is kept
// (one per tag, as the system's would be) and said on the log (NOTICE <tag>\t<title>\t<body>), as on macOS; a scripted
// run taps one by its words (drive 6), which gives the app what it opens as a tap would.
static NSMutableArray<NSArray<NSString *> *> *notices;
static NSString *notice_opened = @"";

static void notice_drop(NSString *tag) {
  NSIndexSet *at = [notices indexesOfObjectsPassingTest:^BOOL(NSArray<NSString *> *n, NSUInteger i, BOOL *stop) {
    return [n[0] isEqualToString:tag];
  }];
  [notices removeObjectsAtIndexes:at];
}

void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;
  if (!notices) notices = [NSMutableArray array];
  NSString *t = mb_ns_from_string(tag);
  notice_drop(t);
  NSArray<NSString *> *n = @[ t, mb_ns_from_string(title), mb_ns_from_string(body), mb_ns_from_string(opens) ];
  [notices addObject:n];
  say([NSString stringWithFormat:@"NOTICE %@\t%@\t%@", n[0], n[1], n[2]]);
}

void mb_host_notice_cancel(moonbit_string_t tag) {
  NSString *t = mb_ns_from_string(tag);
  NSUInteger before = notices.count;
  notice_drop(t);
  if (notices.count < before) say([NSString stringWithFormat:@"NOTICE CANCEL %@", t]);
}

// What the system allows (unknown here), asking it (no way here), its answer (none).
int32_t mb_host_notice_state(int32_t what) { return what == 2 ? -1 : 0; }

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
  say([NSString stringWithFormat:@"NOTICE TAP %@", found[0]]);
  [notices removeObject:found];
  [the_view requestFrame];
  return 1;
}

// A scripted run's input (src/ui/drive.mbt), sent as the system sends it: the keyboard's calls on the view (insertText,
// setMarkedText, its return key, deleteBackward), the edit menu's paste (the clipboard read there), the app's picture
// saved, a notification kept here tapped or looked for.
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  MBView *v = the_view;
  NSString *s = mb_ns_from_string(text);
  switch (kind) {
    case 0: [v insertText:s]; break;
    case 1: [v setMarkedText:s selectedRange:NSMakeRange(s.length, 0)]; break;
    case 2: [v insertText:@"\n"]; break;
    case 3: [v paste:nil]; break;
    case 4: {
      int ok = mb_render_snapshot(s.fileSystemRepresentation);
      say([NSString stringWithFormat:@"SHOT %@ %s", s, ok ? "ok" : "failed"]);
      break;
    }
    case 5: [v deleteBackward]; break;
    case 6:
    case 7: return notice_drive(kind == 6, s);
    default: return 0;
  }
  [v requestFrame];
  return 1;
}

moonbit_string_t mb_host_env(moonbit_string_t name) {
  const char *v = getenv(mb_ns_from_string(name).UTF8String);
  return mb_string_from_ns(v ? [NSString stringWithUTF8String:v] ?: @"" : @"");
}

// The desktop's window and pointer (@host.window_setup, window_inset, window_drag, set_cursor): no window to size
// or move here, no pointer to shape.
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  (void)min_w; (void)min_h; (void)w; (void)h; (void)inset;
}
int32_t mb_host_window_inset(void) { return 0; }
void mb_host_window_drag(void) {}
void mb_host_set_cursor(int32_t kind) { (void)kind; }

// The gallery (gallery.mbt): none on this host; no photo of it picked.
int32_t mb_host_gallery_access(void) { return -1; }
void mb_host_gallery_ask(void) {}
int32_t mb_host_gallery_answers(void) { return 0; }
int32_t mb_host_gallery_read(void) { return 0; }
int32_t mb_host_gallery_read_state(int32_t id) { (void)id; return -1; }
moonbit_string_t mb_host_gallery_read_rows(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_gallery_read_end(int32_t id) { (void)id; }
int32_t mb_host_pick_photo(moonbit_string_t src) { (void)src; return 0; }

// ---- files picked (pick.mbt) ----
// Pictures (kind 1) from the system's photo picker (PHPickerViewController: no leave to ask for), any file (kind 2) from
// its document picker (UIDocumentPickerViewController, copies of them); no camera here yet (kind 0). The files are read
// off the main thread; a pick ends with them, or with none (cancelled, unreadable: state -1).
// MBUI_PICK_FILES="<path>|<path>…" answers every ask with those files at once, no picker (scripted runs; the
// simulator's app reads the Mac's paths).

@interface MBPicker : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property(nonatomic) int32_t pid;
@end

static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *picks;
static NSMutableDictionary<NSNumber *, MBPicker *> *pickers;
static int32_t next_pick = 1;

static void pick_done(int32_t pid, NSArray<NSString *> *names, NSArray<NSData *> *datas) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [pickers removeObjectForKey:@(pid)];
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
      BOOL scoped = [u startAccessingSecurityScopedResource];
      NSData *d = [NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:nil];
      if (scoped) [u stopAccessingSecurityScopedResource];
      if (!d || d.length > (1ull << 30)) continue;  // unreadable, or over 1 GB (as still.fail's composer refuses)
      [names addObject:u.lastPathComponent ?: @"file"];
      [datas addObject:d];
    }
    pick_done(pid, names, datas);
  });
}

@implementation MBPicker
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  [picker dismissViewControllerAnimated:YES completion:nil];
  int32_t pid = self.pid;
  if (!results.count) {
    pick_done(pid, @[], @[]);
    return;
  }
  // each picture as its own file (the photo library's original: HEIC, JPEG, PNG…), in the order picked
  NSUInteger n = results.count;
  NSMutableArray *names = [NSMutableArray arrayWithCapacity:n], *datas = [NSMutableArray arrayWithCapacity:n];
  for (NSUInteger i = 0; i < n; i++) {
    [names addObject:[NSNull null]];
    [datas addObject:[NSNull null]];
  }
  dispatch_group_t g = dispatch_group_create();
  [results enumerateObjectsUsingBlock:^(PHPickerResult *r, NSUInteger i, BOOL *stop) {
    dispatch_group_enter(g);
    [r.itemProvider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier
                                          completionHandler:^(NSURL *url, NSError *error) {
      NSData *d = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil] : nil;
      @synchronized(names) {
        if (d) {
          names[i] = url.lastPathComponent ?: @"photo";
          datas[i] = d;
        }
      }
      dispatch_group_leave(g);
    }];
  }];
  dispatch_group_notify(g, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray *nn = [NSMutableArray new], *dd = [NSMutableArray new];
    for (NSUInteger i = 0; i < n; i++) {
      if (datas[i] == [NSNull null]) continue;
      [nn addObject:names[i]];
      [dd addObject:datas[i]];
    }
    pick_done(pid, nn, dd);
  });
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  pick_answer(self.pid, urls);
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {
  pick_done(self.pid, @[], @[]);
}
@end

int32_t mb_host_pick_start(int32_t kind) {
  if (kind != 1 && kind != 2) return 0;  // no camera here yet
  if (!picks) picks = [NSMutableDictionary new];
  if (!pickers) pickers = [NSMutableDictionary new];
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
  MBPicker *d = [MBPicker new];
  d.pid = pid;
  pickers[@(pid)] = d;
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *vc;
    if (kind == 1) {
      PHPickerConfiguration *cfg = [PHPickerConfiguration new];
      cfg.filter = PHPickerFilter.imagesFilter;
      cfg.selectionLimit = 0;
      cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
      PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
      p.delegate = d;
      vc = p;
    } else {
      UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeItem ] asCopy:YES];
      p.allowsMultipleSelection = YES;
      p.delegate = d;
      vc = p;
    }
    [the_controller presentViewController:vc animated:YES completion:nil];
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
