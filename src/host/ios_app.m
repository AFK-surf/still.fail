// iOS host: a UIView whose layer is a CAMetalLayer, frames from a display
// link, touches as pointer events, and the system keyboard and input
// methods through UITextInput. Built by scripts/ios.sh, not by moon. Under
// it, as big, the native views' view (apple_views.m).
#import <UIKit/UIKit.h>
#import <mach/mach.h>
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
  mb_cb.frame(s.width, s.height, scale, mb_now_ms());
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
- (UIKeyboardType)keyboardType { return UIKeyboardTypeDefault; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UIReturnKeyType)returnKeyType { return UIReturnKeySend; }

@end

// ---------------------------------------------------------------------------

@interface MBController : UIViewController
@property(nonatomic, strong) NSLayoutConstraint *bottom;
@end

@implementation MBController
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

@interface MBAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation MBAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [MBController new];
  [self.window makeKeyAndVisible];
  [the_view requestFrame];
  return YES;
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
  NSLog(@"SHOT %@ %s", p, ok ? "ok" : "failed");
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

void mb_host_log(moonbit_string_t s) { NSLog(@"%@", mb_ns_from_string(s)); }

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
void mb_host_frame_settled(int32_t settled, int32_t awaiting, moonbit_string_t what) {
  (void)settled;
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

// Back (host_native.mbt `set_back`): iOS has no system back; a page's own swipe from the left edge is MoonBit's,
// from the touches. Kept for a hardware keyboard's later.
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);
static mb_back_fn back_cb;
static int back_on;
void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

// The app in front or not (@host.set_app_state): not told here yet (the app counts itself shown and in front).
void mb_host_set_app_state(void (*f)(int32_t)) { (void)f; }

// Whether the system is set to dark (@host.system_dark): the screen's interface style.
int32_t mb_host_system_dark(void) {
  return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0;
}

// Sharing (@host.share, @host.shared_in): no share sheet here yet; nothing comes in.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)text; (void)name; (void)mime; (void)data;
  return 0;
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

// The app drawn dark (@host.set_dark): nothing of the host's own follows it here yet.
void mb_host_set_dark(int32_t dark) { (void)dark; }

// Notifications (notify.mbt): none shown here yet (UNUserNotificationCenter and APNs are a later slice's): nothing kept, nothing tapped, no push; what the
// system allows unknown.
void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;
  (void)tag;
  (void)title;
  (void)body;
  (void)opens;
}

void mb_host_notice_cancel(moonbit_string_t tag) { (void)tag; }

int32_t mb_host_notice_state(int32_t what) { return what == 2 ? -1 : 0; }

moonbit_string_t mb_host_notice_text(int32_t what) {
  (void)what;
  return mb_string_from_ns(@"");
}

// Scripted runs' input given to the host (src/ui/drive.mbt): none of its paths here yet (the app is sent it itself).
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  (void)kind;
  (void)text;
  return 0;
}

moonbit_string_t mb_host_env(moonbit_string_t name) {
  const char *v = getenv(mb_ns_from_string(name).UTF8String);
  return mb_string_from_ns(v ? [NSString stringWithUTF8String:v] ?: @"" : @"");
}

// Files picked (pick.mbt): not on iOS yet (PHPickerViewController, UIDocumentPicker to come).
int32_t mb_host_pick_start(int32_t kind) { return 0; }
int32_t mb_host_pick_state(int32_t pid) { return -1; }
int32_t mb_host_pick_count(int32_t pid) { return 0; }
moonbit_string_t mb_host_pick_name(int32_t pid, int32_t i) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_pick_bytes(int32_t pid, int32_t i) { return moonbit_make_bytes(0, 0); }
void mb_host_pick_end(int32_t pid) {}

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
