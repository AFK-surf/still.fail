// iOS host: a UIView whose layer is a CAMetalLayer, frames from a display
// link, touches as pointer events, and the system keyboard and input
// methods through UITextInput. Built by scripts/ios.sh, not by moon. Under
// it, as big, the native views' view (apple_views.m).
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <GameController/GameController.h>
#import <Network/Network.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UserNotifications/UserNotifications.h>
#import <mach/mach.h>
#import <os/log.h>
#import "apple.h"
#include "post.h"

mb_callbacks mb_cb;

// The app laid out round the system's bars (its Info.plist's MBUIEdge, as Android's manifest dev.mbui.edge): its view
// from the screen's top to its foot, under the status bar and the home indicator, the bars said to it (the system's
// channel `bars`) and the soft keyboard over its foot told as Android's is (the view keeps its size; the frame ends where
// the keyboard starts plus the foot's bar). Without it the view is inside the safe area and ends at the keyboard.
static BOOL edge;
// What shows under the bars and round the view, light and dark (its Info.plist's MBUIGround, "#RRGGBB,#RRGGBB" as
// Android's dev.mbui.ground), else mbui's own.
static UIColor *ground_light, *ground_dark;

static UIColor *color_hex(NSString *s) {
  s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
  if (s.length != 6) return nil;
  unsigned v = 0;
  if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return nil;
  return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

static void read_info(void) {
  NSDictionary *info = NSBundle.mainBundle.infoDictionary;
  edge = [info[@"MBUIEdge"] boolValue];
  ground_light = [UIColor colorWithRed:0.961 green:0.961 blue:0.969 alpha:1];
  ground_dark = [UIColor colorWithRed:0x1B / 255.0 green:0x1C / 255.0 blue:0x1F / 255.0 alpha:1];
  NSArray<NSString *> *g = [info[@"MBUIGround"] isKindOfClass:NSString.class] ? [info[@"MBUIGround"] componentsSeparatedByString:@","] : nil;
  if (g.count == 2 && color_hex(g[0]) && color_hex(g[1])) {
    ground_light = color_hex(g[0]);
    ground_dark = color_hex(g[1]);
  }
}

// Something the system said, on the system's channel (src/hostapi/system.mbt), as JSON.
static void say_system(NSDictionary *said) {
  NSData *json = [NSJSONSerialization dataWithJSONObject:said options:0 error:NULL];
  if (json) mb_post("system", (const char *)json.bytes, json.length, NULL, 0);
}

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

@interface MBView : UIView <UITextInput, UIEditMenuInteractionDelegate>
@property(nonatomic, strong) CADisplayLink *link;
// the system's floating edit menu over a field's words (mb_host_text_menu), and where they are
@property(nonatomic, strong) UIEditMenuInteraction *editMenu;
@property(nonatomic) CGRect menuRect;
@property(nonatomic) BOOL menuShown;
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
// how much later than its time the frame before reached the screen (mb_host_frame_late), and that frame's time (the
// display link's target it was drawn for; -1: none drawn since the link was paused)
static double frame_late, last_target = -1;
// How far the soft keyboard reaches over the view's foot past the safe area's, in points, where it is on the screen
// now (its motion followed frame by frame: the controller's), and whether it is moving.
static double ime_over(void);
static BOOL ime_moving(void);
// whether the share extension's inbox is to be looked into (shared_in, below)
static BOOL share_look;

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

// the device beyond the window (device.mbt): a key catcher's keys, the soft keyboard, the clipboard, awake, haptics
#include "apple_device.h"

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
  self.editMenu = [[UIEditMenuInteraction alloc] initWithDelegate:self];
  [self addInteraction:self.editMenu];
  self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  // (past 60 on an iPhone only as its Info.plist allows: scripts/ios.sh sets CADisableMinimumFrameDurationOnPhone)
  self.link.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
  [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  return self;
}

- (void)requestFrame {
  self.wantFrame = YES;
  self.link.paused = NO;
}

// The floating edit menu over the words it is about (Android's ActionMode.TYPE_FLOATING's content rect), kept there
// as they move (scrolled, typed into); what it offers is canPerformAction's.
- (CGRect)editMenuInteraction:(UIEditMenuInteraction *)i targetRectForConfiguration:(UIEditMenuConfiguration *)c {
  return self.menuRect;
}
- (void)editMenuInteraction:(UIEditMenuInteraction *)i willDismissMenuForConfiguration:(UIEditMenuConfiguration *)c
                   animator:(id<UIEditMenuInteractionAnimating>)a {
  self.menuShown = NO;
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
    last_target = -1;
    return;
  }
  CGSize s = self.bounds.size;
  double scale = self.window.screen.scale ?: 3.0;
  self.layer.contentsScale = scale;
  mb_text_scale = scale;
  mb_render_set_size(s.width, s.height, scale);
  self.wantFrame = NO;
  double t0 = frames_drawn == 0 ? mb_now_ms() : 0;
  // edge to edge, the soft keyboard over the view's foot (where the system has it in this frame of its motion): the
  // app laid out above it, the drawable keeping its size (as Android's: resizing it each step would be far too slow);
  // while it moves, a frame each display frame
  double h = edge ? MAX(1, s.height - ime_over()) : s.height;
  if (edge && ime_moving()) self.wantFrame = YES;
  // the frame before on the screen since the display's last refresh (the link's timestamp): past the time it was drawn
  // for, it was late by as much (a frame that took longer than the display's frame to build)
  frame_late = last_target >= 0 ? MAX(0, l.timestamp * 1000.0 - last_target) : 0;
  // the frame's time is the display's: when this frame will be on screen (the display link's target, on
  // CACurrentMediaTime's clock as the touches' times are), as Android's is its vsync's, not when it happens to be built
  mb_cb.frame(s.width, h, scale, l.targetTimestamp * 1000.0);
  last_target = l.targetTimestamp * 1000.0;
  if (frames_drawn == 0)
    say([NSString stringWithFormat:@"ios: first frame %.0fx%.0f @%.0fx in %.0f ms", s.width, s.height, scale, mb_now_ms() - t0]);
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
  if (!self.wantFrame) {
    l.paused = YES;
    last_target = -1;
  }
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
    // a key catcher's focus (apple_device.h): its keys
    if (key_catching) {
      if (catch_press(p)) handled = YES;
      continue;
    }
    // what is held with it (ui's mod_*): ⌘← to the line's start, ⌥← by words, as an iPad's fields have them
    UIKeyModifierFlags m = p.key.modifierFlags;
    int mods = ((m & UIKeyModifierShift) ? 1 : 0) | ((m & UIKeyModifierControl) ? 2 : 0) |
               ((m & UIKeyModifierAlternate) ? 4 : 0) | ((m & UIKeyModifierCommand) ? 8 : 0);
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
// (a key catcher has none, but says it has: the keyboard's delete then deletes, as Backspace, on the screen it types into)
- (BOOL)hasText { return key_catching || self.doc.length > 0; }

// What the keyboard does is also done here to the field's text as the keyboard sees it (`doc`, `sel`), as the field
// will do it: the keyboard reads its words round the caret between keys (its suggestions, its corrections) before the
// field says them back (mb_host_set_ime), which tells the keyboard of a change only where the field's differ.
- (void)echo:(NSRange)r with:(NSString *)t {
  NSUInteger n = self.doc.length;
  NSUInteger a = MIN(r.location, n), b = MIN(r.location + r.length, n);
  self.doc = [self.doc stringByReplacingCharactersInRange:NSMakeRange(a, b - a) withString:t];
  self.sel = NSMakeRange(a + t.length, 0);
}

- (void)insertText:(NSString *)text {
  if ([text isEqualToString:@"\n"]) {
    if (self.marked.location != NSNotFound) send_text(2, @"", 0, 0);
    self.marked = NSMakeRange(NSNotFound, 0);
    mb_cb.key(7, 0);
    return;
  }
  [self echo:self.marked.location != NSNotFound ? self.marked : self.sel with:text];
  self.marked = NSMakeRange(NSNotFound, 0);
  send_text(0, text, 0, 0);
}

- (void)deleteBackward {
  if (self.marked.location != NSNotFound) {
    send_text(1, @"", 0, 0);
    [self echo:self.marked with:@""];
    self.marked = NSMakeRange(NSNotFound, 0);
    return;
  }
  if (!key_catching && self.sel.length > 0) [self echo:self.sel with:@""];
  else if (!key_catching && self.sel.location > 0 && self.sel.location <= self.doc.length)
    [self echo:[self.doc rangeOfComposedCharacterSequenceAtIndex:self.sel.location - 1] with:@""];
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
  [self echo:NSMakeRange(r.a, r.b - r.a) with:text];
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
// The system's edit actions (its floating edit menu: mb_host_text_menu; a hardware keyboard's ⌘X, ⌘C, ⌘V, ⌘A; a
// scripted run's paste): what the field's menu offers (cut and copy over words picked, paste, select all), done as
// Android's floating menu does them (MBView.textMenu): cut, copy and select all as the field's own keys, the
// clipboard's words pasted (text kind 8: put in as typed, a step of its own to undo; a long paste is the app's to take:
// the editor's paste_limit). Nothing else of the system's (look up, translate, share…), which Android's menu has none
// of either.
static int32_t menu_can;  // what the menu offers (hostapi text_menu_*: 1 cut, 2 copy, 4 paste, 8 select all)
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
  if (!self.imeActive || key_catching) return NO;
  if (action == @selector(paste:)) return UIPasteboard.generalPasteboard.hasStrings;
  if (action == @selector(cut:)) return (menu_can & 1) != 0;
  if (action == @selector(copy:)) return (menu_can & 2) != 0;
  if (action == @selector(selectAll:)) return (menu_can & 8) != 0;
  return NO;
}
- (void)paste:(id)sender {
  NSString *s = UIPasteboard.generalPasteboard.string;
  if (s.length) send_text(8, s, 0, 0);
}
- (void)cut:(id)sender { mb_cb.key(14, 0); [self requestFrame]; }
- (void)copy:(id)sender { mb_cb.key(13, 0); [self requestFrame]; }
- (void)selectAll:(id)sender { mb_cb.key(12, 0); [self requestFrame]; }
// The keyboard as Android's app asks for it (MBView.onCreateInputConnection: plain text, many lines, its suggestions,
// no action of its own): no capitals put in by itself, no quotes or dashes made curly, its return key a new line the
// field decides on; a search field's (hostapi ime_action, apple_device.h) its search key, an address's the keyboard
// for addresses and its go key, a number's digits and its done key.
- (UIKeyboardType)keyboardType {
  if (key_catching) return UIKeyboardTypeDefault;
  return ime_action_kind == 2 ? UIKeyboardTypeURL : ime_action_kind == 3 ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
}
- (UITextAutocorrectionType)autocorrectionType { return key_catching ? UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextSmartQuotesType)smartQuotesType { return UITextSmartQuotesTypeNo; }
- (UITextSmartDashesType)smartDashesType { return UITextSmartDashesTypeNo; }
- (UITextSmartInsertDeleteType)smartInsertDeleteType { return UITextSmartInsertDeleteTypeNo; }
- (UIReturnKeyType)returnKeyType {
  return ime_action_kind == 1 ? UIReturnKeySearch : ime_action_kind == 2 ? UIReturnKeyGo : ime_action_kind == 3 ? UIReturnKeyDone : UIReturnKeyDefault;
}

@end

// ---- a finger on a page under the canvas ----

// A finger that goes down on a page the app says gives up some of its touches (ui's Touch, mb_views_touch_at): the
// page's until it has gone further up or down than across past the slop ("vertical") or a second finger comes down
// ("pinch"); from then the canvas's, from where it went down (the page's touches called off: cancelsTouchesInView).
// The page's own gestures wait for this one to fail first.
@interface MBTakeTouch : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *canvas;
@property(nonatomic, weak) UITouch *one;
@property(nonatomic, weak) UITouch *two;
@property(nonatomic) CGPoint from;
@property(nonatomic) double slop;
@property(nonatomic, copy) NSString *mode;
@end

@implementation MBTakeTouch
- (void)canvasTouch:(int)kind at:(CGPoint)p time:(double)t {
  event_time = t * 1000.0;
  mb_cb.pointer(kind, p.x, p.y, 0);
  event_time = -1;
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  for (UITouch *u in t) {
    if (!self.one) {
      CGPoint p = [u locationInView:self.canvas];
      double slop = 0;
      const char *m = mb_views_touch_at(p.x, p.y, &slop);
      if (!m || (strcmp(m, "vertical") != 0 && strcmp(m, "pinch") != 0)) {
        self.state = UIGestureRecognizerStateFailed;
        return;
      }
      self.one = u;
      self.from = p;
      self.slop = slop;
      self.mode = [NSString stringWithUTF8String:m];
    } else if (!self.two) {
      self.two = u;
      if (self.state == UIGestureRecognizerStatePossible && [self.mode isEqualToString:@"pinch"]) {
        self.state = UIGestureRecognizerStateBegan;
        [self canvasTouch:0 at:self.from time:self.one.timestamp];
        [self canvasTouch:1 at:[self.one locationInView:self.canvas] time:self.one.timestamp];
        [self canvasTouch:4 at:[u locationInView:self.canvas] time:u.timestamp];
      } else if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        [self canvasTouch:4 at:[u locationInView:self.canvas] time:u.timestamp];
      }
    }
  }
}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  UITouch *u = self.one;
  if (!u) return;
  CGPoint p = [u locationInView:self.canvas];
  if (self.state == UIGestureRecognizerStatePossible) {
    double dx = p.x - self.from.x, dy = p.y - self.from.y;
    if ([self.mode isEqualToString:@"vertical"] && fabs(dy) > self.slop && fabs(dy) > fabs(dx)) {
      self.state = UIGestureRecognizerStateBegan;
      [self canvasTouch:0 at:self.from time:u.timestamp];
      [self canvasTouch:1 at:p time:u.timestamp];
    } else if ([self.mode isEqualToString:@"vertical"] && fabs(dx) > self.slop) {
      // sideways first: the page's
      self.state = UIGestureRecognizerStateFailed;
    }
    return;
  }
  self.state = UIGestureRecognizerStateChanged;
  if ([t containsObject:u]) [self canvasTouch:1 at:p time:u.timestamp];
  if (self.two && [t containsObject:self.two]) [self canvasTouch:5 at:[self.two locationInView:self.canvas] time:self.two.timestamp];
}
- (void)ended:(NSSet<UITouch *> *)t kind:(int)kind {
  BOOL taken = self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged;
  if (taken && self.two && [t containsObject:self.two]) {
    [self canvasTouch:6 at:[self.two locationInView:self.canvas] time:self.two.timestamp];
    self.two = nil;
  }
  if (self.one && [t containsObject:self.one]) {
    if (taken) [self canvasTouch:kind at:[self.one locationInView:self.canvas] time:self.one.timestamp];
    self.state = taken ? (kind == 2 ? UIGestureRecognizerStateEnded : UIGestureRecognizerStateCancelled)
                       : UIGestureRecognizerStateFailed;
  }
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  [self ended:t kind:2];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
  [self ended:t kind:3];
}
- (void)reset {
  [super reset];
  self.one = nil;
  self.two = nil;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)o {
  return YES;
}
@end


// ---------------------------------------------------------------------------

// Which way the app is held while it has not turned itself: a phone upright only (an iPhone: its short side under 600
// points), a tablet as the person turns it.
static UIInterfaceOrientationMask mb_upright(void) {
  return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll
                                                                                 : UIInterfaceOrientationMaskPortrait;
}

@interface MBController : UIViewController
@property(nonatomic, strong) NSLayoutConstraint *bottom;
@property(nonatomic) BOOL dark;
// edge to edge: where the soft keyboard's top is (a mark the keyboard's layout guide moves with it: its presentation
// layer is where the keyboard is in each frame of its motion)
@property(nonatomic, strong) UIView *kbMark;
// the bars last said to the app (edge to edge), in points
@property(nonatomic) UIEdgeInsets saidBars;
@property(nonatomic) BOOL barsSaid;
// turned sideways for a film (@hostapi.set_sideways)
@property(nonatomic) BOOL sideways;
// the size classes last said to the app (`size_class`: its width's and its height's, a space between)
@property(nonatomic, copy) NSString *saidClasses;
// the hinge as the system last said it (a UIHingeStatus; -1 none: no hinge, or not said yet), and the fold last said to
// the app (`fold`)
@property(nonatomic) NSInteger hinge;
@property(nonatomic, copy) NSDictionary *saidFold;
@end

static MBController *the_controller;

@implementation MBController
// the status bar's words light over the app drawn dark, dark over it drawn light (@hostapi.set_dark)
- (UIStatusBarStyle)preferredStatusBarStyle {
  return self.dark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
}
// on its side while a film asks (@hostapi.set_sideways), the status bar and the home indicator out of its way then (as
// Android's system bars: a swipe brings them for a while); else upright on an iPhone, as turned on an iPad (mb_upright)
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return self.sideways ? UIInterfaceOrientationMaskLandscape : mb_upright();
}
- (BOOL)prefersStatusBarHidden { return self.sideways; }
- (BOOL)prefersHomeIndicatorAutoHidden { return self.sideways; }
// the system's light or dark changed (@hostapi.system_dark, read as frames are built): a frame; the window's size
// classes changed (an iPhone Duo opened or closed, the app put beside another): said to the app; the hinge moved: said
- (void)viewDidLoad {
  [super viewDidLoad];
  [self registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                     withHandler:^(id<UITraitEnvironment> env, UITraitCollection *was) { [the_view requestFrame]; }];
  [self registerForTraitChanges:@[ UITraitHorizontalSizeClass.class, UITraitVerticalSizeClass.class ]
                     withHandler:^(id<UITraitEnvironment> env, UITraitCollection *was) { [(MBController *)env saySizeClasses]; }];
  self.hinge = -1;
#ifdef __IPHONE_27_1
  if (@available(iOS 27.1, *)) {
    // its first state at once, then each change (nil: no hinge where the view is)
    __weak MBController *weak = self;
    UIHingeInteraction *h = [[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *i, UIHingeInteractionUpdate *u) {
      MBController *c = weak;
      if (!c) return;
      c.hinge = u.hinge ? (NSInteger)u.hinge.status : -1;
      [c sayFold];
    }];
    [self.view addInteraction:h];
  }
#endif
}
// The window's size classes as its traits have them, said to the app as they change (src/hostapi/system.mbt
// `size_class`): what its layout is chosen by (regular both ways on an opened iPhone Duo, compact in width upright on a
// phone or beside another app). iOS splits a window's width in two where Android splits it in three: regular is said
// as Android's medium while the window is narrower than where Android's expanded starts (840 points: an iPad upright,
// beside another app), its expanded from there (an iPad on its side), so a window as wide is laid out alike on both.
- (void)saySizeClasses {
  UITraitCollection *t = self.traitCollection;
  UIUserInterfaceSizeClass w = t.horizontalSizeClass, h = t.verticalSizeClass;
  CGFloat across = self.view.bounds.size.width;
  if (w == UIUserInterfaceSizeClassUnspecified || h == UIUserInterfaceSizeClassUnspecified || across <= 0) return;
  NSString *wide = w != UIUserInterfaceSizeClassRegular ? @"compact" : across < 840 ? @"medium" : @"expanded";
  NSString *high = h == UIUserInterfaceSizeClassRegular ? @"regular" : @"compact";
  NSString *said = [NSString stringWithFormat:@"%@ %@", wide, high];
  if ([said isEqualToString:self.saidClasses]) return;
  self.saidClasses = said;
  say_system(@{@"size_class" : @{@"width" : wide, @"height" : high}});
  say([NSString stringWithFormat:@"ios: size classes %@ wide, %@ high", wide, high]);
  [the_view requestFrame];
}
// The hinge and where its fold divides the app's view, said to the app as they change (src/hostapi/system.mbt `fold`):
// UIHingeInteraction's status and the view's active division regions (UIView reservedRegionsOfKind:, read as the view is
// laid out and its safe area changes, as UIKit has them read), in the view's points. iOS 27.1 on, built with its SDK;
// before, or with no hinge, nothing is said.
- (void)sayFold {
#ifdef __IPHONE_27_1
  if (@available(iOS 27.1, *)) {
    if (self.hinge < 0 && !self.saidFold) return;
    NSString *hinge = @"none";
    switch (self.hinge) {
      case UIHingeStatusClosed: hinge = @"closed"; break;
      case UIHingeStatusPartiallyOpen: hinge = @"half"; break;
      case UIHingeStatusFullyOpen: hinge = @"open"; break;
      default: break;
    }
    NSMutableArray *divisions = [NSMutableArray array];
    if (the_view) {
      for (UIViewReservedRegion *r in [the_view reservedRegionsOfKind:UIViewReservedRegionKind.divisionRegionKind]) {
        if (!r.active) continue;
        CGRect f = r.frame;
        [divisions addObject:@{@"x" : @(f.origin.x), @"y" : @(f.origin.y), @"w" : @(f.size.width), @"h" : @(f.size.height)}];
      }
    }
    NSDictionary *fold = @{@"hinge" : hinge, @"divisions" : divisions};
    if ([fold isEqual:self.saidFold]) return;
    self.saidFold = fold;
    say_system(@{@"fold" : fold});
    say([NSString stringWithFormat:@"ios: hinge %@, %lu division(s)", hinge, (unsigned long)divisions.count]);
    [the_view requestFrame];
  }
#endif
}
- (void)loadView {
  UIView *root = [UIView new];
  root.backgroundColor = ground_light;
  self.view = root;
  the_view = [[MBView alloc] initWithFrame:CGRectZero];
  the_view.translatesAutoresizingMaskIntoConstraints = NO;
  the_view.opaque = NO;  // the native views under it show through its holes
  UIView *under = mb_views_root(CGRectZero);
  under.translatesAutoresizingMaskIntoConstraints = NO;
  MBTakeTouch *take = [[MBTakeTouch alloc] initWithTarget:nil action:nil];
  take.canvas = the_view;
  take.delegate = take;
  take.cancelsTouchesInView = YES;
  take.delaysTouchesBegan = NO;
  take.delaysTouchesEnded = NO;
  [under addGestureRecognizer:take];
  [root addSubview:under];
  [root addSubview:the_view];
  UILayoutGuide *g = root.safeAreaLayoutGuide;
  NSArray *under_view = @[
    [under.topAnchor constraintEqualToAnchor:the_view.topAnchor],
    [under.bottomAnchor constraintEqualToAnchor:the_view.bottomAnchor],
    [under.leadingAnchor constraintEqualToAnchor:the_view.leadingAnchor],
    [under.trailingAnchor constraintEqualToAnchor:the_view.trailingAnchor],
  ];
  if (edge) {
    // edge to edge, as Android's app is: from the screen's top to its foot and from side to side, under the status bar,
    // the home indicator and what is at a side (an iPhone Duo's outer screen has its status bar down its side, iOS
    // 27.1; a phone on its side its cutout): all said to the app (viewSafeAreaInsetsDidChange), which keeps clear of them.
    // The keyboard's guide reaches the screen's foot (not the safe area's) while it is down, its mark with it.
    root.keyboardLayoutGuide.usesBottomSafeArea = NO;
    self.kbMark = [UIView new];
    self.kbMark.translatesAutoresizingMaskIntoConstraints = NO;
    // (shown, though nothing to see: a hidden view's moves may not be animated)
    self.kbMark.userInteractionEnabled = NO;
    [root addSubview:self.kbMark];
    [NSLayoutConstraint activateConstraints:[@[
      [the_view.topAnchor constraintEqualToAnchor:root.topAnchor],
      [the_view.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
      [the_view.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
      [the_view.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
      [self.kbMark.topAnchor constraintEqualToAnchor:root.keyboardLayoutGuide.topAnchor],
      [self.kbMark.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
      [self.kbMark.widthAnchor constraintEqualToConstant:1],
      [self.kbMark.heightAnchor constraintEqualToConstant:1],
    ] arrayByAddingObjectsFromArray:under_view]];
    return;
  }
  // the view ends above the keyboard
  self.bottom = [the_view.bottomAnchor constraintEqualToAnchor:root.keyboardLayoutGuide.topAnchor];
  [NSLayoutConstraint activateConstraints:[@[
    [the_view.topAnchor constraintEqualToAnchor:g.topAnchor],
    [the_view.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
    [the_view.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
    self.bottom,
  ] arrayByAddingObjectsFromArray:under_view]];
}
// Edge to edge, the bars said to the app as they change (src/hostapi/system.mbt `bars`): the safe area's on each side
// (the status bar's over the view's top, or down its side on an iPhone Duo's outer screen; the home indicator's under
// its foot; a cutout at a side).
- (void)sayBars {
  if (!edge) return;
  UIEdgeInsets in = self.view.safeAreaInsets;
  UIEdgeInsets b = UIEdgeInsetsMake(in.top, in.left, in.bottom, in.right);
  if (self.barsSaid && UIEdgeInsetsEqualToEdgeInsets(b, self.saidBars)) return;
  self.barsSaid = YES;
  self.saidBars = b;
  say_system(@{@"bars" : @{@"top" : @(b.top), @"bottom" : @(b.bottom), @"left" : @(b.left), @"right" : @(b.right)}});
  [the_view requestFrame];
}
- (void)viewSafeAreaInsetsDidChange {
  [super viewSafeAreaInsetsDidChange];
  [self sayBars];
  [self sayFold];
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self sayBars];
  [self saySizeClasses];
  [self sayFold];
  // the keyboard's guide moved (it is coming or going): its motion drawn frame by frame (MBView's tick)
  [the_view requestFrame];
}
@end

// Edge to edge, the soft keyboard's top where it is on the screen now: its mark's presentation (mid-motion, where the
// system has drawn the keyboard in this frame), past the safe area's foot (which the bars' `bottom` pads).
static double ime_over(void) {
  MBController *c = the_controller;
  UIView *root = c.view;
  if (!root) return 0;
  if (!edge) {
    double over = root.bounds.size.height - root.safeAreaInsets.bottom - root.keyboardLayoutGuide.layoutFrame.origin.y;
    return over > 0 ? over : 0;
  }
  CALayer *mark = c.kbMark.layer.presentationLayer ?: c.kbMark.layer;
  double over = root.bounds.size.height - mark.frame.origin.y - root.safeAreaInsets.bottom;
  return over > 0 ? over : 0;
}

static BOOL ime_moving(void) { return the_controller.kbMark.layer.animationKeys.count > 0; }

// The app's one window, in the scene the system connects (the UIScene life cycle, which iOS 26 asks every app for:
// the Info.plist's UIApplicationSceneManifest names MBSceneDelegate).
@interface MBSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

// A link the system opened the app with (an https link of the app's own: a universal link; a URL of its scheme), said
// to the app on the system's channel (`link`), as Android's MainActivity says an ACTION_VIEW's.
static void say_link(NSURL *url) {
  if (!url.absoluteString.length) return;
  say([NSString stringWithFormat:@"ios: opened with a link (%@://%@)", url.scheme, url.host ?: @""]);
  say_system(@{@"link" : url.absoluteString});
}

static void say_activity(NSUserActivity *a) {
  if ([a.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && a.webpageURL) say_link(a.webpageURL);
}

@implementation MBSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)opts {
  if (![scene isKindOfClass:UIWindowScene.class]) return;
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  the_controller = [MBController new];
  self.window.rootViewController = the_controller;
  [self.window makeKeyAndVisible];
  [the_view requestFrame];
  for (UIOpenURLContext *u in opts.URLContexts) say_link(u.URL);
  for (NSUserActivity *a in opts.userActivities) say_activity(a);
  // (a runner waits on these lines: the app up, then its first frame drawn)
  say(@"ios: launched");
}
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
  for (UIOpenURLContext *u in contexts) say_link(u.URL);
}
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)a {
  say_activity(a);
}
@end

@interface MBAppDelegate : UIResponder <UIApplicationDelegate>
@end

// (below) the system's notifications, the default network, the app's time off the screen, the keyboard put away by
// the person: watched from the start
static void notice_start(void);
static void network_start(void);
static void watch_shown(void);
static void watch_keyboard(void);

@implementation MBAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
  notice_start();
  network_start();
  watch_shown();
  watch_keyboard();
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
  read_info();
  @autoreleasepool {
    char *argv[] = {"mbui", NULL};
    UIApplicationMain(1, argv, nil, NSStringFromClass([MBAppDelegate class]));
  }
}

double mb_host_now(void) { return mb_now_ms(); }

// The time of day (host_native.mbt's wall_ms).
double mb_host_wall_ms(void) { return [[NSDate date] timeIntervalSince1970] * 1000.0; }

// how far local time is ahead of UTC then, in minutes (@hostapi.utc_offset_min)
int32_t mb_host_utc_offset_min(double at_ms) {
  return (int32_t)([[NSTimeZone localTimeZone] secondsFromGMTForDate:[NSDate dateWithTimeIntervalSince1970:at_ms / 1000.0]] / 60);
}

double mb_host_event_time(void) { return event_time; }

double mb_host_frame_late(void) { return frame_late; }

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
  // the field's text and selection as it has them: the keyboard told only of what differs from what it did itself
  // (MBView's echo), a change of the field's own (a tap, a paste, a send)
  if (v.marked.location == NSNotFound) {
    NSString *t = mb_ns_from_string(text);
    NSRange sel = NSMakeRange(a, b - a);
    if (![t isEqualToString:v.doc]) {
      [v.inputDelegate textWillChange:v];
      v.doc = t;
      v.sel = sel;
      [v.inputDelegate textDidChange:v];
    } else if (!NSEqualRanges(sel, v.sel)) {
      [v.inputDelegate selectionWillChange:v];
      v.sel = sel;
      [v.inputDelegate selectionDidChange:v];
    }
  }
  if (v.imeActive && !was) [v becomeFirstResponder];
  if (!v.imeActive && was) [v resignFirstResponder];
}

// The system's floating edit menu over a field's words (@hostapi.text_menu, as Android's ActionMode.TYPE_FLOATING):
// over the rectangle given, offering what `can` says (MBView's canPerformAction), put away when not shown.
// (an iPad's menu bar asks canPerformAction:, which the floating menu's `can` answers)
void mb_host_edit_can(int32_t can) { (void)can; }

void mb_host_text_menu(int32_t shown, double x, double y, double w, double h, int32_t can) {
  MBView *v = the_view;
  menu_can = can;
  if (!shown) {
    if (v.menuShown) [v.editMenu dismissMenu];
    v.menuShown = NO;
    return;
  }
  v.menuRect = CGRectMake(x, y, MAX(w, 1), MAX(h, 1));
  if (v.menuShown) {
    [v.editMenu updateVisibleMenuPositionAnimated:NO];
    return;
  }
  v.menuShown = YES;
  UIEditMenuConfiguration *c = [UIEditMenuConfiguration configurationWithIdentifier:nil
                                                                        sourcePoint:CGPointMake(x + w / 2, y)];
  [v.editMenu presentEditMenuWithConfiguration:c];
}

void mb_host_clipboard_set(moonbit_string_t s) {
  UIPasteboard.generalPasteboard.string = mb_ns_from_string(s);
}

// A picture on the clipboard (@hostapi.clipboard_set_image): the image the bytes are, as other apps paste one.
void mb_host_clipboard_image(moonbit_bytes_t data) {
  UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:data length:Moonbit_array_length(data)]];
  if (img) UIPasteboard.generalPasteboard.image = img;
}

// A secret on the clipboard (@hostapi.clipboard_set_secret, as Android's sensitive clip cleared later): kept to this
// device (not handed to the person's other devices' universal clipboard), and gone from it `clear_ms` later.
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  NSMutableDictionary *opts = [@{UIPasteboardOptionLocalOnly : @YES} mutableCopy];
  if (clear_ms > 0) opts[UIPasteboardOptionExpirationDate] = [NSDate dateWithTimeIntervalSinceNow:clear_ms / 1000.0];
  [UIPasteboard.generalPasteboard setItems:@[ @{UTTypeUTF8PlainText.identifier : mb_ns_from_string(s)} ] options:opts];
}


// The app's log: the system's (os_log, `log stream`) and stderr as it is (unbuffered: `simctl launch --stderr`, which a
// scripted run reads line by line as the app goes: scripts/ios.sh run, still.fail's e2e).
static void say(NSString *s) {
  const char *c = s.UTF8String ?: "";
  os_log(OS_LOG_DEFAULT, "%{public}s", c);
  fprintf(stderr, "%s\n", c);
}

void mb_host_log(moonbit_string_t s) { say(mb_ns_from_string(s)); }

// The app over another app done (@hostapi.over_done): it never is here.
void mb_host_over_done(int32_t open_app) {}

// A page in a browser's tab over the app (@hostapi.open_tab, Android's Custom Tab): Safari's view over it
// (SFSafariViewController), the app staying in front under it (a login's loopback listener answering the page), back
// with its Done. Not a web page (another scheme): handed to the system, as open_url.
int32_t mb_host_open_url(moonbit_string_t s);
int32_t mb_host_open_tab(moonbit_string_t s) {
  NSURL *url = [NSURL URLWithString:mb_ns_from_string(s)];
  NSString *scheme = url.scheme.lowercaseString;
  if (!url || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) return mb_host_open_url(s);
  MBController *c = the_controller;
  if (!c) return 0;
  SFSafariViewController *tab = [[SFSafariViewController alloc] initWithURL:url];
  UIViewController *top = c;
  while (top.presentedViewController) top = top.presentedViewController;
  [top presentViewController:tab animated:YES completion:nil];
  say([NSString stringWithFormat:@"open-tab: %@://%@", url.scheme, url.host ?: @""]);
  return 1;
}

// What holds the app up while it listens for a browser (@hostapi.hold_words): iOS keeps no such notice.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {}

// A URL handed to the system (@hostapi.open_url): UIApplication, Safari or the app that takes it.
int32_t mb_host_open_url(moonbit_string_t s) {
  NSString *u = mb_ns_from_string(s);
  NSURL *url = [NSURL URLWithString:u];
  NSLog(@"open-url: %@", u);
  if (!url || !url.scheme) return 0;
  [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
  return 1;
}

// Whether the run is on its own clock (host_native.mbt's own_clock): no run here is yet.
int32_t mb_host_own_clock(void) { return 0; }
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

// The app in front or not (@hostapi.set_app_state): 1 while its scene is on screen (in front, or behind the app switcher or
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
// Off the screen (in the background) and back: how long it was away said to the app (the system's `shown`, as
// Android's after onStop: a clock that counts the device's sleep), not as it first starts.
static uint64_t hidden_at;
static void watch_shown(void) {
  NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
  [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *n) {
    if (!hidden_at) hidden_at = clock_gettime_nsec_np(CLOCK_MONOTONIC);
  }];
  [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *n) {
    // (what was shared meanwhile: the inbox looked into again, shared_in)
    share_look = YES;
    [the_view requestFrame];
    if (!hidden_at) return;
    double away = (clock_gettime_nsec_np(CLOCK_MONOTONIC) - hidden_at) / 1e6;
    hidden_at = 0;
    say_system(@{@"shown" : @{@"away" : @(away)}});
  }];
}

// The soft keyboard put away by the person (an iPad's key, a hardware keyboard come, dragged down), not by the app:
// what was typed into lets go of the focus, as Android's (MainActivity: Native.text 7); the app's own hiding comes
// after its focus went (imeActive off by then), and one as the app leaves the front, or as something of the system's
// comes over it (a picker, Safari's view, the share sheet: Android's window losing its focus), is the system's.
static void watch_keyboard(void) {
  [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillHideNotification object:nil
                                                   queue:NSOperationQueue.mainQueue
                                              usingBlock:^(NSNotification *n) {
    MBView *v = the_view;
    if (!v.imeActive || key_catching || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (the_controller.presentedViewController || !v.isFirstResponder) return;
    send_text(7, @"", 0, 0);
    [v requestFrame];
  }];
}

// The device's default network as it changes (Network's path monitor, as Android's NetworkWatch): another one than
// before (Wi-Fi to mobile data, back online after none) said to the app (the system's `network`); not the first seen.
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
      say([NSString stringWithFormat:@"ios: network now %@", now]);
      say_system(@{@"network" : @YES});
    }
  });
  nw_path_monitor_start(network_monitor);
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

// Whether the system is set to dark (@hostapi.system_dark): the screen's interface style.
// Words as the app sizes them (@hostapi.font_scale): the system's own size of words not followed here yet.
double mb_host_font_scale(void) { return 1.0; }
// What the app was started to be used with (@hostapi.native_pointing): keyboard and mouse where a mouse or a trackpad is
// connected as it starts (GCMouse: an iPad's Magic Keyboard, a mouse), else touch.
int32_t mb_host_native_pointing(void) {
  if (@available(iOS 14.0, *)) {
    return GCMouse.mice.count > 0 ? 2 : 1;
  }
  return 1;
}
// The app's widgets for the system's accessibility (@hostapi.a11y_on, a11y_tree): not told here yet.
int32_t mb_host_a11y_on(void) { return 0; }
void mb_host_a11y_tree(moonbit_string_t s) { (void)s; }

int32_t mb_host_system_dark(void) {
  return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0;
}

// Sharing out (@hostapi.share): the system's share sheet over the app, the words or the file (kept in a folder of the app's
// own in its temporary directory). What comes in is the share extension's (shared_in, below).
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

// What another app shared (@hostapi.shared_in): what the app's share extension kept for it (ios_share.m: the inbox in
// the app group's container its Info.plist names, MBUIAppGroup; share-inbox/<when>/share.json and its files), the
// oldest first, looked for as the app starts and each time it comes to the front, taken whole and let go from the
// inbox; MBUI_SHARE_FILES (paths split by |, MBUI_SHARE_TEXT its words) for scripted runs, as on macOS.
static NSMutableArray<NSData *> *shared_files;
static BOOL share_look = YES;

static NSURL *share_inbox(void) {
  NSString *group = NSBundle.mainBundle.infoDictionary[@"MBUIAppGroup"];
  if (![group isKindOfClass:NSString.class] || !group.length) return nil;
  NSURL *box = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
  return [box URLByAppendingPathComponent:@"share-inbox" isDirectory:YES];
}

static moonbit_string_t shared_said(NSDictionary *said) {
  NSData *j = [NSJSONSerialization dataWithJSONObject:said options:0 error:nil];
  return j ? mb_string_from_ns([[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding]) : moonbit_make_string_raw(0);
}

moonbit_string_t mb_host_shared_in(void) {
  static int env_taken;
  const char *given = getenv("MBUI_SHARE_FILES");
  if (!env_taken && given && *given) {
    env_taken = 1;
    shared_files = [NSMutableArray new];
    NSMutableArray *files = [NSMutableArray new];
    for (NSString *p in [@(given) componentsSeparatedByString:@"|"]) {
      NSData *d = p.length ? [NSData dataWithContentsOfFile:p] : nil;
      if (!d) continue;
      [shared_files addObject:d];
      [files addObject:@{@"name" : p.lastPathComponent, @"type" : @"", @"size" : @(d.length)}];
    }
    const char *words = getenv("MBUI_SHARE_TEXT");
    if (files.count) {
      say([NSString stringWithFormat:@"shared in: %lu files", (unsigned long)files.count]);
      return shared_said(@{@"text" : words ? @(words) : @"", @"files" : files});
    }
  }
  if (!share_look) return moonbit_make_string_raw(0);
  NSURL *inbox = share_inbox();
  NSArray<NSURL *> *kept = inbox ? [NSFileManager.defaultManager contentsOfDirectoryAtURL:inbox includingPropertiesForKeys:nil options:0 error:nil] : nil;
  kept = [kept sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent compare:b.lastPathComponent options:NSNumericSearch]; }];
  for (NSURL *dir in kept) {
    NSData *j = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"share.json"]];
    // (one being written still: share.json comes last)
    if (!j) continue;
    NSDictionary *said = [NSJSONSerialization JSONObjectWithData:j options:0 error:nil];
    shared_files = [NSMutableArray new];
    NSMutableArray *files = [NSMutableArray new];
    for (NSDictionary *f in [said isKindOfClass:NSDictionary.class] ? said[@"files"] : nil) {
      if (![f isKindOfClass:NSDictionary.class] || ![f[@"path"] isKindOfClass:NSString.class]) continue;
      NSData *d = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:f[@"path"]]];
      if (!d) continue;
      [shared_files addObject:d];
      [files addObject:@{@"name" : f[@"name"] ?: @"file", @"type" : f[@"type"] ?: @"", @"size" : @(d.length)}];
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    NSString *text = [said[@"text"] isKindOfClass:NSString.class] ? said[@"text"] : @"";
    if (!text.length && !files.count) continue;
    NSMutableDictionary *out = [@{@"text" : text} mutableCopy];
    if (files.count) out[@"files"] = files;
    if ([said[@"title"] isKindOfClass:NSString.class]) out[@"title"] = said[@"title"];
    say([NSString stringWithFormat:@"shared in: %lu characters, %lu files", (unsigned long)text.length, (unsigned long)files.count]);
    return shared_said(out);
  }
  share_look = NO;
  return moonbit_make_string_raw(0);
}

moonbit_bytes_t mb_host_shared_in_file(int32_t i) {
  if (i < 0 || i >= (int32_t)shared_files.count) return moonbit_make_bytes(0, 0);
  NSData *d = shared_files[i];
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)d.length, 0);
  if (d.length) memcpy(out, d.bytes, d.length);
  shared_files[i] = [NSData data];
  return out;
}

// Updates (@hostapi.app_version, update_install, update_state): the build (its Info.plist's CFBundleVersion, the
// build's number as Android's versionCode is: scripts/ios.sh), which the app shows and tells; it does not update
// itself here (the App Store's, TestFlight's).
int32_t mb_host_app_version(void) {
  return (int32_t)[NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] integerValue];
}
// A package for the system's installer (@hostapi.install_package): none here, said on the system channel (system.mbt).
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  NSDictionary *said = @{@"install" : @{@"name" : mb_ns_from_string(name), @"error" : @"unsupported"}};
  NSData *json = [NSJSONSerialization dataWithJSONObject:said options:0 error:NULL];
  if (json) mb_post("system", (const char *)json.bytes, json.length, NULL, 0);
}

void mb_host_update_install(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name) {
  (void)url; (void)sha256; (void)size; (void)name;
}
moonbit_string_t mb_host_update_state(void) { return moonbit_make_string_raw(0); }

// Turned sideways for a film (@hostapi.set_sideways, as Android's requested orientation): the scene asked to turn on
// its side (either way the phone is held), and back upright.
void mb_host_set_sideways(int32_t on) {
  MBController *c = the_controller;
  if (!c || c.sideways == (on != 0)) return;
  c.sideways = on != 0;
  [c setNeedsUpdateOfSupportedInterfaceOrientations];
  [c setNeedsStatusBarAppearanceUpdate];
  [c setNeedsUpdateOfHomeIndicatorAutoHidden];
  UIWindowScene *scene = c.view.window.windowScene;
  UIWindowSceneGeometryPreferencesIOS *g = [[UIWindowSceneGeometryPreferencesIOS alloc]
      initWithInterfaceOrientations:on ? UIInterfaceOrientationMaskLandscape : mb_upright()];
  [scene requestGeometryUpdateWithPreferences:g errorHandler:^(NSError *e) { say([NSString stringWithFormat:@"sideways: %@", e]); }];
}

// The app drawn dark or light (@hostapi.set_dark): what shows under the status bar and the home indicator (the app's view
// is inside the safe area) the dark page's ground or the light one's, the status bar's words over it to match.
void mb_host_set_dark(int32_t dark) {
  MBController *c = the_controller;
  if (!c || c.dark == (dark != 0)) return;
  c.dark = dark != 0;
  c.view.backgroundColor = dark ? ground_dark : ground_light;
  [c setNeedsStatusBarAppearanceUpdate];
}

// Notifications (notify.mbt), as still.fail's Android app shows them: the system's (UNUserNotificationCenter), one
// request per tag (a newer one with the same tag replaces it), what it opens in its userInfo, a tap bringing the app to
// the front with that (the center's delegate, set as the app starts: a tap that launched it comes too); shown while the
// app is in front as well (the app decides what to show). Each is also kept (one per tag) and said on the log (NOTICE
// <tag>\t<title>\t<body>), and a scripted run taps one by its words (drive 6), which gives the app what it opens as a
// tap would. No pushes (APNs wants a signed app's entitlement; Android's FCM is not done either).
static NSMutableArray<NSArray<NSString *> *> *notices;
static NSString *notice_opened = @"";
// what the system allows: 0 not known yet, 1 granted, 2 denied, 3 not asked; the answer to an ask: -1 none, 0, 1
static _Atomic int32_t notice_allowed = 0;
static _Atomic int32_t notice_answered = -1;

static void notice_drop(NSString *tag) {
  NSIndexSet *at = [notices indexesOfObjectsPassingTest:^BOOL(NSArray<NSString *> *n, NSUInteger i, BOOL *stop) {
    return [n[0] isEqualToString:tag];
  }];
  [notices removeObjectsAtIndexes:at];
}

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
    notice_drop(tag);
    say([NSString stringWithFormat:@"NOTICE TAP %@", tag]);
    [the_view requestFrame];
  });
  done();
}
@end

// What the system allows, asked again (as the app comes to the front: it may have changed in the system's settings).
static void notice_refresh(void) {
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

// As the app starts (MBAppDelegate): the center's delegate, and what it allows.
static void notice_start(void) {
  static MBNoticeDelegate *delegate;
  delegate = [MBNoticeDelegate new];
  [UNUserNotificationCenter currentNotificationCenter].delegate = delegate;
  notice_refresh();
  [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { notice_refresh(); }];
}

void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;  // one kind of notification here: the system's settings list the app's, not channels
  if (!notices) notices = [NSMutableArray array];
  NSString *t = mb_ns_from_string(tag);
  notice_drop(t);
  NSArray<NSString *> *n = @[ t, mb_ns_from_string(title), mb_ns_from_string(body), mb_ns_from_string(opens) ];
  [notices addObject:n];
  say([NSString stringWithFormat:@"NOTICE %@\t%@\t%@", n[0], n[1], n[2]]);
  UNMutableNotificationContent *c = [UNMutableNotificationContent new];
  c.title = n[1];
  c.body = n[2];
  c.sound = UNNotificationSound.defaultSound;
  c.userInfo = @{@"opens" : n[3]};
  // the same identifier: the system replaces the one shown
  UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:t content:c trigger:nil];
  [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:r withCompletionHandler:^(NSError *e) {
    if (e) say([NSString stringWithFormat:@"NOTICE NOT SHOWN %@: %@", t, e.localizedDescription]);
  }];
}

void mb_host_notice_cancel(moonbit_string_t tag) {
  NSString *t = mb_ns_from_string(tag);
  NSUInteger before = notices.count;
  notice_drop(t);
  if (notices.count < before) say([NSString stringWithFormat:@"NOTICE CANCEL %@", t]);
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center removeDeliveredNotificationsWithIdentifiers:@[ t ]];
  [center removePendingNotificationRequestsWithIdentifiers:@[ t ]];
}

// 0: what the system allows (1 granted, 2 denied, 3 not asked, 0 not known yet); 1: asked (the system's alert), when
// it was never asked: 1, else 0; 2: its answer, once (1 allowed, 0 refused, -1 none); 3: the Settings app's page of the
// app's notifications opened (1; before iOS 15.4 the app's page).
int32_t mb_host_notice_state(int32_t what) {
  if (what == 0) return notice_allowed;
  if (what == 2) {
    int32_t a = notice_answered;
    if (a >= 0) notice_answered = -1;
    return a;
  }
  if (what == 3) {
    NSString *where = UIApplicationOpenSettingsURLString;
    if (@available(iOS 15.4, *)) where = UIApplicationOpenNotificationSettingsURLString;
    dispatch_async(dispatch_get_main_queue(), ^{
      [UIApplication.sharedApplication openURL:[NSURL URLWithString:where] options:@{} completionHandler:nil];
    });
    return 1;
  }
  if (what != 1) return 0;
  if (notice_allowed != 3) return 0;
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
  say([NSString stringWithFormat:@"NOTICE TAP %@", found[0]]);
  [notices removeObject:found];
  [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[ found[0] ]];
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

// The desktop's window and pointer (@hostapi.window_setup, window_inset, window_drag, set_cursor): no window to size
// or move here, no pointer to shape.
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  (void)min_w; (void)min_h; (void)w; (void)h; (void)inset;
}
int32_t mb_host_window_inset(void) { return 0; }
// A window filling the screen (@hostapi.full_screen): not one of this host's.
int32_t mb_host_full_screen(void) { return 0; }
void mb_host_set_full_screen(int32_t on) { (void)on; }
// How round the window's corners are (@hostapi.window_corner): the app fills the screen, whose own corners (40 and
// more) are rounder than anything by them could follow within the corner rule's ranges: said as none.
double mb_host_window_corner(void) { return 0; }
void mb_host_window_drag(void) {}
void mb_host_set_cursor(int32_t kind) { (void)kind; }
void mb_host_set_badge(int32_t n) { (void)n; }
// The menu bar (@hostapi.menu_setup): none here.
void mb_host_menu_setup(moonbit_string_t json) { (void)json; }
moonbit_string_t mb_host_local_station(void) { return mb_string_from_ns(@""); }
void mb_host_local_station_act(moonbit_string_t a) { (void)a; }
// The keys held now (@hostapi.mods_held): none read here.
int32_t mb_host_mods_held(void) { return 0; }

// ---- files picked (pick.mbt) ----
// Pictures (kind 1) from the system's photo picker (PHPickerViewController: no leave to ask for), any file (kind 2) from
// its document picker (UIDocumentPickerViewController, copies of them), a photo taken now (kind 0: the camera's,
// UIImagePickerController, as Android's TakePicturePreview; none on a device without one, the simulator's). Photos as
// the other apps read them (JPEG where the library keeps HEIC, as Android's are). The files are read off the main
// thread; a pick ends with them, or with none (cancelled, unreadable: state -1).
// MBUI_PICK_FILES="<path>|<path>…" answers every ask with those files at once, no picker (scripted runs; the
// simulator's app reads the Mac's paths).

@interface MBPicker : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIImagePickerControllerDelegate,
                                UINavigationControllerDelegate>
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
- (void)imagePickerController:(UIImagePickerController *)c didFinishPickingMediaWithInfo:(NSDictionary *)info {
  [c dismissViewControllerAnimated:YES completion:nil];
  UIImage *im = info[UIImagePickerControllerOriginalImage];
  NSData *d = im ? UIImageJPEGRepresentation(im, 0.9) : nil;
  NSString *name = [NSString stringWithFormat:@"photo-%.0f.jpg", NSDate.date.timeIntervalSince1970 * 1000];
  pick_done(self.pid, d ? @[ name ] : @[], d ? @[ d ] : @[]);
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)c {
  [c dismissViewControllerAnimated:YES completion:nil];
  pick_done(self.pid, @[], @[]);
}
@end

int32_t mb_host_pick_start(int32_t kind) {
  kind &= 15;  // (16: a big file may be held: none is here, each read whole)
  if (kind < 0 || kind > 2) return 0;
  // (no camera: the simulator's, an iPod's)
  if (kind == 0 && !getenv("MBUI_PICK_FILES") && ![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) return 0;
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
    if (kind == 0) {
      UIImagePickerController *p = [UIImagePickerController new];
      p.sourceType = UIImagePickerControllerSourceTypeCamera;
      p.delegate = d;
      vc = p;
    } else if (kind == 1) {
      PHPickerConfiguration *cfg = [PHPickerConfiguration new];
      cfg.filter = PHPickerFilter.imagesFilter;
      cfg.selectionLimit = 0;
      // (as the other apps read them: JPEG for a HEIC the library keeps)
      cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCompatible;
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

// ---- the gallery (gallery.mbt): the photo library, for ＋'s recent photos, as Android's Gallery.java ----
// How much of it the app may read (Photos' leave: all of it, or the photos the person chose: Android 14's
// READ_MEDIA_VISUAL_USER_SELECTED's), asking for it (the system's alert; with some chosen, its picker of more; turned
// down, the app's page of the system's settings), its photos with their times read off the main thread (the view
// ranks them). A photo's source is ph://<its local identifier>: drawn as the library's thumbnail at the size it is
// shown (apple_image.m), read whole by pick_photo.
static int gallery_answers_n;

int32_t mb_host_gallery_access(void) {
  PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
  int32_t a = st == PHAuthorizationStatusAuthorized ? 1 : st == PHAuthorizationStatusLimited ? 2 : 0;
  // (said as it changes: 1 all, 2 chosen, 0 none; the system's own status beside it)
  static int32_t said = -1;
  if (a != said) {
    said = a;
    say([NSString stringWithFormat:@"gallery: access %d (status %ld)", a, (long)st]);
  }
  return a;
}

static void gallery_answered(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    gallery_answers_n++;
    say([NSString stringWithFormat:@"gallery: answered, access %d", mb_host_gallery_access()]);
    [the_view requestFrame];
  });
}

void mb_host_gallery_ask(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (st == PHAuthorizationStatusNotDetermined) {
      [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite
                                                 handler:^(PHAuthorizationStatus s) { gallery_answered(); }];
    } else if (st == PHAuthorizationStatusLimited && the_controller) {
      [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:the_controller
                                                                     completionHandler:^(NSArray<NSString *> *ids) {
        gallery_answered();
      }];
    } else if (st != PHAuthorizationStatusAuthorized) {
      say(@"gallery: refused, the app's settings");
      [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                       options:@{}
                             completionHandler:nil];
    }
  });
}

int32_t mb_host_gallery_answers(void) { return gallery_answers_n; }

// A read: 0 reading, 1 read, -1 failed; its rows (id, src, added, modified, taken: a tab between, a line each). The
// id is the photo's place in the library oldest first (a newer one's higher, as Android's MediaStore ids are).
static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *gallery_reads;
static int32_t gallery_next = 1;

int32_t mb_host_gallery_read(void) {
  if (!gallery_reads) gallery_reads = [NSMutableDictionary new];
  int32_t id = gallery_next++;
  gallery_reads[@(id)] = [@{@"state" : @0} mutableCopy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableString *rows = [NSMutableString string];
    if (mb_host_gallery_access() != 0) {
      PHFetchOptions *o = [PHFetchOptions new];
      o.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES] ];
      PHFetchResult<PHAsset *> *all = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:o];
      [all enumerateObjectsUsingBlock:^(PHAsset *a, NSUInteger i, BOOL *stop) {
        long long made = a.creationDate ? (long long)a.creationDate.timeIntervalSince1970 : -1;
        long long changed = a.modificationDate ? (long long)a.modificationDate.timeIntervalSince1970 : -1;
        [rows appendFormat:@"%lu\tph://%@\t%lld\t%lld\t%lld\n", (unsigned long)i + 1, a.localIdentifier, made, changed, made];
      }];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      NSMutableDictionary *r = gallery_reads[@(id)];
      if (!r) return;
      r[@"rows"] = rows;
      r[@"state"] = @1;
      mb_host_outside(MB_OUTSIDE_GALLERY, id, 1);
      [the_view requestFrame];
    });
  });
  return id;
}

int32_t mb_host_gallery_read_state(int32_t id) {
  NSMutableDictionary *r = gallery_reads[@(id)];
  return r ? [r[@"state"] intValue] : -1;
}

moonbit_string_t mb_host_gallery_read_rows(int32_t id) { return mb_string_from_ns(gallery_reads[@(id)][@"rows"] ?: @""); }

void mb_host_gallery_read_end(int32_t id) { [gallery_reads removeObjectForKey:@(id)]; }

// A HEIC photo as JPEG (its orientation and what else it says kept), as the other apps read the library's (the
// photo picker's Compatible); others as they are.
static NSData *photo_compatible(NSData *d, NSString **name) {
  CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)d, NULL);
  if (!src) return d;
  NSString *type = (__bridge NSString *)CGImageSourceGetType(src);
  UTType *t = type ? [UTType typeWithIdentifier:type] : nil;
  if (!t || !([t conformsToType:UTTypeHEIC] || [t conformsToType:UTTypeHEIF])) {
    CFRelease(src);
    return d;
  }
  NSMutableData *out = [NSMutableData data];
  CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)out, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
  BOOL ok = NO;
  if (dst) {
    CGImageDestinationAddImageFromSource(dst, src, 0, (__bridge CFDictionaryRef) @{(id)kCGImageDestinationLossyCompressionQuality : @0.9});
    ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
  }
  CFRelease(src);
  if (!ok) return d;
  *name = [(*name).stringByDeletingPathExtension stringByAppendingPathExtension:@"jpg"];
  return out;
}

// A photo of the gallery (its ph:// source) read whole, as a pick of it: its original, the library's name for it (from
// iCloud when it is kept there).
int32_t mb_host_pick_photo(moonbit_string_t s) {
  NSString *src = mb_ns_from_string(s);
  if (![src hasPrefix:@"ph://"]) return 0;
  if (!picks) picks = [NSMutableDictionary new];
  int32_t pid = next_pick++;
  picks[@(pid)] = [@{@"state" : @0} mutableCopy];
  PHAsset *a = [PHAsset fetchAssetsWithLocalIdentifiers:@[ [src substringFromIndex:5] ] options:nil].firstObject;
  if (!a) {
    pick_done(pid, @[], @[]);
    return pid;
  }
  PHImageRequestOptions *o = [PHImageRequestOptions new];
  o.networkAccessAllowed = YES;
  o.version = PHImageRequestOptionsVersionCurrent;
  NSString *named = [PHAssetResource assetResourcesForAsset:a].firstObject.originalFilename ?: @"photo.jpg";
  [PHImageManager.defaultManager requestImageDataAndOrientationForAsset:a options:o
                                                          resultHandler:^(NSData *d, NSString *uti, CGImagePropertyOrientation orient, NSDictionary *info) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSString *name = named;
      NSData *data = d ? photo_compatible(d, &name) : nil;
      pick_done(pid, data ? @[ name ] : @[], data ? @[ data ] : @[]);
    });
  }];
  return pid;
}
