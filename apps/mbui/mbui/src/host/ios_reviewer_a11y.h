#pragma once
#import <UIKit/UIKit.h>
#include <math.h>

// Included after MBView's implementation; kept separate so a native contract harness can exercise
// these exact classes/parser with an MBView editor fixture and captured mb_post/mb_cb callbacks.
// This is deliberately a reviewer-form bridge, not an all-app semantic renderer. A semantic ancestor's
// description must be "still.fail.reviewer" (two fields, email then password), or
// "still.fail.reviewer.welcome" (no fields). Nothing outside those subtrees is reconstructed.
// Real UITextFields supply iOS 17's native accessibility text editing (no private traits or 18.1 API).
@class MBReviewField;
static NSMutableDictionary<NSString *, id> *review_nodes;
static NSArray *review_order;
static UIAccessibilityElement *review_error;
static NSString *review_error_words;
static NSString *review_error_status_node;
static BOOL review_error_pending;
static BOOL review_syncing;
static NSInteger review_scope_kind;
// Force the core's last-sent tree to reset even when off/on notifications arrive between paints.
static BOOL review_a11y_reset_pending;
// Harnesses can replace this predicate without changing the system VoiceOver setting.
static BOOL (*review_voiceover_running)(void) = UIAccessibilityIsVoiceOverRunning;
static void (*review_post_notification)(UIAccessibilityNotifications, id) = UIAccessibilityPostNotification;
static MBReviewField *review_editing;
static void mb_review_sync_editor(void);
static void mb_review_merge(void);

@protocol MBReviewActionTarget <NSObject>
@property(nonatomic, copy) NSString *node;
@property(nonatomic) NSInteger widget;
@property(nonatomic, copy) NSString *actions;
@property(nonatomic) BOOL disabled;
@end

@interface MBReviewElement : UIAccessibilityElement <MBReviewActionTarget>
@property(nonatomic, copy) NSString *node;
@property(nonatomic) NSInteger widget;
@property(nonatomic, copy) NSString *actions;
@property(nonatomic) BOOL disabled;
@end

static BOOL mb_review_action(id<MBReviewActionTarget> element, NSString *action) {
  if (!review_voiceover_running() || !review_nodes) return NO;
  NSString *node = [element node];
  if (review_nodes[node] != element || [element disabled] || [element widget] == 0) return NO;
  NSString *letter = [action isEqualToString:@"focus"] ? @"f" : @"a";
  if (![[element actions] containsString:letter]) return NO;
  NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"id": @([element widget]), @"action": action}
                                                options:0 error:NULL];
  if (!json) return NO;
  mb_post("a11y", json.bytes, json.length, NULL, 0);
  [the_view requestFrame];
  return YES;
}

static void mb_review_reveal(id<MBReviewActionTarget> element) {
  // Passive VoiceOver traversal reveals the current scoped widget, never asks it to take editing focus.
  // Disabled controls still need to be discoverable, so only identity/scope/reader/widget are validated.
  if (!review_voiceover_running() || !review_nodes ||
      review_nodes[element.node] != element || element.widget == 0) return;
  NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"id": @(element.widget)} options:0 error:NULL];
  if (!json) return;
  mb_post("still.fail.reviewer.reveal", json.bytes, json.length, NULL, 0);
  [the_view requestFrame];
}

@implementation MBReviewElement
- (void)accessibilityElementDidBecomeFocused {
  [super accessibilityElementDidBecomeFocused];
  mb_review_reveal(self);
}
- (BOOL)accessibilityActivate { return mb_review_action(self, @"activate"); }
@end

@interface MBReviewField : UITextField <UITextFieldDelegate, MBReviewActionTarget>
@property(nonatomic, copy) NSString *node;
@property(nonatomic) NSInteger widget;
@property(nonatomic, copy) NSString *actions;
@property(nonatomic) BOOL disabled;
@property(nonatomic) BOOL coreFocused;
@property(nonatomic) BOOL password;
@end

static BOOL mb_review_can_edit(MBReviewField *field) {
  return field && review_nodes[field.node] == field && !field.disabled && field.coreFocused &&
         the_view.imeActive && ime_action_kind == (field.password ? 5 : 4) && review_voiceover_running();
}

@implementation MBReviewField
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.delegate = self;
    self.borderStyle = UITextBorderStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.textColor = UIColor.clearColor;
    self.tintColor = UIColor.clearColor;
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.autocorrectionType = UITextAutocorrectionTypeNo;
    self.spellCheckingType = UITextSpellCheckingTypeNo;
    self.smartQuotesType = UITextSmartQuotesTypeNo;
    self.smartDashesType = UITextSmartDashesTypeNo;
    self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    [self addTarget:self action:@selector(reviewChanged:) forControlEvents:UIControlEventEditingChanged];
  }
  return self;
}
// Never export credentials as a semantic value, including while Show changes the painted password.
// UITextField itself supplies native secure text-entry behavior; its transient editing storage is not a cache.
- (NSString *)accessibilityValue { return nil; }
- (void)accessibilityElementDidBecomeFocused {
  [super accessibilityElementDidBecomeFocused];
  mb_review_reveal(self);
}
- (BOOL)accessibilityActivate { return mb_review_action(self, @"focus"); }
- (BOOL)textFieldShouldBeginEditing:(UITextField *)field {
  if (mb_review_can_edit(self)) return YES;
  mb_review_action(self, @"focus");
  return NO; // wait for the core's focus acknowledgement before accepting keyboard input
}
- (void)reviewChanged:(id)sender {
  if (review_syncing || !mb_review_can_edit(self)) return;
  review_syncing = YES;
  MBView *v = the_view;
  NSString *text = self.text ?: @"";
  // One authoritative core editor. Native storage is only the active UIKit/IME working copy;
  // every text/selection change is immediately delivered through the existing editor protocol.
  if (![text isEqualToString:v.doc])
    [v replaceRange:[MBRange from:0 to:v.doc.length] withText:text];
  UITextRange *selection = self.selectedTextRange;
  if (selection) {
    NSInteger a = [self offsetFromPosition:self.beginningOfDocument toPosition:selection.start];
    NSInteger b = [self offsetFromPosition:self.beginningOfDocument toPosition:selection.end];
    a = MAX(0, MIN(a, (NSInteger)text.length));
    b = MAX(a, MIN(b, (NSInteger)text.length));
    if (!NSEqualRanges(v.sel, NSMakeRange(a, b - a)))
      [v setSelectedTextRange:[MBRange from:a to:b]];
  }
  review_syncing = NO;
  [v requestFrame];
}
- (void)textFieldDidChangeSelection:(UITextField *)field { [self reviewChanged:field]; }
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)text {
  return mb_review_can_edit(self);
}
- (BOOL)textFieldShouldClear:(UITextField *)field { return mb_review_can_edit(self); }
- (BOOL)textFieldShouldReturn:(UITextField *)field {
  if (mb_review_can_edit(self)) {
    [self reviewChanged:self];
    mb_cb.key(7, 0);
    [the_view requestFrame];
  }
  return NO;
}
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
  if (!mb_review_can_edit(self)) return NO;
  if (self.password && (action == @selector(copy:) || action == @selector(cut:))) return NO;
  return [super canPerformAction:action withSender:sender];
}
@end

static void mb_review_clear_field(MBReviewField *field) {
  if (!field) return;
  BOOL syncing = review_syncing;
  review_syncing = YES;
  [field resignFirstResponder];
  field.text = @"";
  review_syncing = syncing;
}

static void mb_review_sync_editor(void) {
  MBReviewField *focused = nil;
  for (id element in review_order) {
    if ([element isKindOfClass:MBReviewField.class] && mb_review_can_edit(element)) {
      focused = element;
      break;
    }
  }
  if (review_editing != focused) {
    mb_review_clear_field(review_editing);
    review_editing = focused;
  }
  for (id element in review_order)
    if ([element isKindOfClass:MBReviewField.class] && element != focused) mb_review_clear_field(element);
  if (!focused) return;
  review_syncing = YES;
  // Becoming first responder can reset UIKit's selection; acknowledge core text first, then acquire
  // the responder and finally restore core selection while delegate feedback is suppressed.
  BOOL composing = focused.markedTextRange != nil;
  if (!composing && ![focused.text isEqualToString:the_view.doc]) focused.text = the_view.doc;
  if (!focused.isFirstResponder) {
    [the_view resignFirstResponder];
    [focused becomeFirstResponder];
  }
  // Do not disrupt UIKit's live marked-text session. Each composition edit has already reached the core.
  if (!composing) {
    NSInteger n = focused.text.length;
    NSInteger a = MIN((NSInteger)the_view.sel.location, n);
    NSInteger b = MIN((NSInteger)NSMaxRange(the_view.sel), n);
    UITextPosition *start = [focused positionFromPosition:focused.beginningOfDocument offset:a];
    UITextPosition *end = [focused positionFromPosition:focused.beginningOfDocument offset:b];
    if (start && end) focused.selectedTextRange = [focused textRangeFromPosition:start toPosition:end];
  }
  review_syncing = NO;
}

static void mb_review_merge(void) {
  NSMutableArray *elements = [NSMutableArray arrayWithArray:review_order ?: @[]];
  // Once bound, countdown wording may change but the semantic node remains authoritative. Never
  // resurrect the event's old fallback text just because the live Status label has advanced.
  UIAccessibilityElement *target = review_error_status_node ? nil : review_error;
  for (id element in elements) {
    if (![element isKindOfClass:MBReviewElement.class]) continue;
    MBReviewElement *status = element;
    if (![status.accessibilityIdentifier isEqualToString:@"review-status"]) continue;
    BOOL bound = review_error_status_node && [status.node isEqualToString:review_error_status_node];
    BOOL initial = !review_error_status_node &&
                   (!review_error || [status.accessibilityLabel isEqualToString:review_error_words]);
    if (bound || initial) {
      target = status;
      if (review_error) review_error_status_node = status.node;
      break;
    }
  }
  if (review_error && target == review_error) [elements addObject:review_error];
  the_view.accessibilityElements = elements.count ? elements : nil;
  if (review_error_pending && target && review_voiceover_running()) {
    review_error_pending = NO;
    // One focus notification speaks the error; do not also post an announcement.
    review_post_notification(UIAccessibilityLayoutChangedNotification, target);
  }
}

static void mb_review_drop_tree(void) {
  mb_review_clear_field(review_editing);
  review_editing = nil;
  for (id element in review_order) {
    if ([element isKindOfClass:MBReviewField.class]) {
      mb_review_clear_field(element);
      [element removeFromSuperview];
    }
  }
  review_order = nil;
  review_nodes = nil;
  review_scope_kind = 0;
  mb_review_merge();
}

static int32_t mb_review_a11y_on(void) {
  if (review_a11y_reset_pending) {
    review_a11y_reset_pending = NO;
    // tick clears wantFrame before entering the core frame, so this schedules the repaint that
    // resends unchanged semantics after this frame's synthetic off resets Ctx.a11y_sent.
    [the_view requestFrame];
    return 0;
  }
  return review_voiceover_running() ? 1 : 0;
}

static void mb_review_voiceover_changed(void) {
  review_a11y_reset_pending = YES;
  if (!review_voiceover_running()) {
    mb_review_drop_tree();
    if (the_view.imeActive) [the_view becomeFirstResponder];
  }
  // Wake even when the display link was idle; the next accessibility query performs the reset phase.
  [the_view requestFrame];
}

static void mb_review_tree(NSString *tree) {
  if (!review_voiceover_running()) { mb_review_drop_tree(); return; }
  NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray new];
  NSMutableSet<NSString *> *scope = [NSMutableSet new];
  BOOL reviewerRoot = NO, welcomeRoot = NO;
  for (NSString *line in [tree componentsSeparatedByString:@"\n"]) {
    NSArray *row = [line componentsSeparatedByString:@"\x1f"];
    if (row.count != 16 || [row[0] integerValue] <= 0) continue;
    [rows addObject:row];
    if ([row[11] isEqualToString:@"still.fail.reviewer"]) {
      reviewerRoot = YES; [scope addObject:row[0]];
    }
    if ([row[11] isEqualToString:@"still.fail.reviewer.welcome"]) {
      welcomeRoot = YES; [scope addObject:row[0]];
    }
  }
  // Fixed-point ancestry does not depend on the transport's ordering.
  BOOL changed;
  do {
    changed = NO;
    for (NSArray *row in rows) if ([scope containsObject:row[1]] && ![scope containsObject:row[0]]) {
      [scope addObject:row[0]];
      changed = YES;
    }
  } while (changed);
  NSUInteger fields = 0;
  for (NSArray *row in rows) if ([scope containsObject:row[0]] && [row[3] isEqualToString:@"TextField"]) fields++;
  // Fail closed if a different screen accidentally reuses the marker.
  if ((!reviewerRoot && !welcomeRoot) || (reviewerRoot && fields != 2) || (!reviewerRoot && fields != 0)) {
    review_error = nil; review_error_words = nil; review_error_status_node = nil; review_error_pending = NO;
    mb_review_drop_tree(); return;
  }
  NSMutableDictionary *next = [NSMutableDictionary new];
  NSMutableArray *ordered = [NSMutableArray new];
  NSUInteger fieldIndex = 0;
  for (NSArray<NSString *> *row in rows) {
    if (![scope containsObject:row[0]] || [row[11] isEqualToString:@"still.fail.reviewer"] ||
        [row[11] isEqualToString:@"still.fail.reviewer.welcome"]) continue;
    BOOL field = [row[3] isEqualToString:@"TextField"];
    BOOL password = field && fieldIndex++ == 1;
    BOOL button = [row[3] isEqualToString:@"Button"];
    BOOL status = [row[3] isEqualToString:@"Status"];
    if (!field && !button && !status && !row[9].length) continue;
    double x = [row[5] doubleValue], y = [row[6] doubleValue];
    double w = [row[7] doubleValue], h = [row[8] doubleValue];
    if (!isfinite(x) || !isfinite(y) || !isfinite(w) || !isfinite(h) || w <= 0 || h <= 0) continue;
    CGRect rect = CGRectMake(x, y, w, h);
    id old = review_nodes[row[0]];
    BOOL disabled = [row[4] containsString:@"d"];
    if (field) {
      MBReviewField *control = [old isKindOfClass:MBReviewField.class] ? old : [[MBReviewField alloc] initWithFrame:rect];
      control.node = row[0]; control.widget = [row[2] integerValue]; control.actions = row[15];
      control.disabled = disabled;
      control.coreFocused = [row[4] containsString:@"f"];
      control.password = password;
      if (control.secureTextEntry != password) control.secureTextEntry = password;
      control.keyboardType = password ? UIKeyboardTypeDefault : UIKeyboardTypeEmailAddress;
      control.textContentType = password ? UITextContentTypePassword : UITextContentTypeUsername;
      control.returnKeyType = password ? UIReturnKeyGo : UIReturnKeyNext;
      control.enabled = !disabled;
      control.frame = rect;
      control.accessibilityLabel = row[9];
      if (control.superview != the_view) [the_view addSubview:control];
      next[row[0]] = control;
      [ordered addObject:control];
    } else {
      MBReviewElement *element = [old isKindOfClass:MBReviewElement.class] ? old :
        [[MBReviewElement alloc] initWithAccessibilityContainer:the_view];
      element.node = row[0]; element.widget = [row[2] integerValue]; element.actions = row[15];
      element.disabled = disabled;
      element.isAccessibilityElement = YES;
      element.accessibilityLabel = row[9];
      element.accessibilityIdentifier = status ? @"review-status" : nil;
      element.accessibilityTraits = (button ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText) |
                                    (disabled ? UIAccessibilityTraitNotEnabled : 0);
      element.accessibilityFrameInContainerSpace = rect;
      next[row[0]] = element;
      [ordered addObject:element];
    }
  }
  for (NSString *node in review_nodes) {
    id old = review_nodes[node];
    if (next[node] != old && [old isKindOfClass:MBReviewField.class]) {
      mb_review_clear_field(old);
      [old removeFromSuperview];
    }
  }
  NSInteger kind = reviewerRoot ? 2 : 1;
  BOOL entering = review_scope_kind != kind;
  BOOL announcingError = review_error_pending;
  review_scope_kind = kind;
  review_nodes = next;
  review_order = ordered;
  mb_review_sync_editor();
  mb_review_merge();
  if (entering && !announcingError && ordered.count)
    review_post_notification(UIAccessibilityLayoutChangedNotification, ordered.firstObject);
}

// Error events select the existing Status target instead of replacing accessibilityElements and destroying form.
static void mb_review_accessibility(NSDictionary *params) {
  NSString *words = [params[@"text"] isKindOfClass:NSString.class] ? params[@"text"] : @"";
  if (!the_view) return;
  if (!words.length) {
    review_error = nil;
    review_error_words = nil;
    review_error_status_node = nil;
    review_error_pending = NO;
    mb_review_merge();
    return;
  }
  BOOL fresh = ![review_error_words isEqualToString:words];
  if (fresh) review_error_status_node = nil;
  review_error_words = words;
  if (!review_error) review_error = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:the_view];
  review_error.isAccessibilityElement = YES;
  review_error.accessibilityLabel = words;
  review_error.accessibilityTraits = UIAccessibilityTraitStaticText;
  review_error.accessibilityFrameInContainerSpace = CGRectMake([params[@"x"] doubleValue], [params[@"y"] doubleValue],
    MAX(1, [params[@"w"] doubleValue]), MAX(1, [params[@"h"] doubleValue]));
  review_error_pending = fresh;
  mb_review_merge();
}

