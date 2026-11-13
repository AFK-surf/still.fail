// src/host/ios_ime.h tests: iOS IME responder gating, marked-text teardown on blur, and idle resign guards.
//   cc -Wall -Werror -fobjc-arc -I src/host scripts/ios_ime_test.m -framework Foundation -framework CoreGraphics -o out/ios_ime_test && out/ios_ime_test
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#import "ios_ime.h"

@interface FakeImeDelegate : NSObject <MBImeDelegate>
@property(nonatomic, strong) NSMutableArray<NSString *> *events;
@end

@implementation FakeImeDelegate
- (instancetype)init {
  if (!(self = [super init])) return nil;
  _events = [NSMutableArray array];
  return self;
}
- (void)textWillChange:(id)textInput { (void)textInput; [self.events addObject:@"textWillChange"]; }
- (void)textDidChange:(id)textInput { (void)textInput; [self.events addObject:@"textDidChange"]; }
- (void)selectionWillChange:(id)textInput { (void)textInput; [self.events addObject:@"selectionWillChange"]; }
- (void)selectionDidChange:(id)textInput { (void)textInput; [self.events addObject:@"selectionDidChange"]; }
@end

@interface FakeImeView : NSObject <MBImeView>
@property(nonatomic) BOOL imeActive;
@property(nonatomic) CGRect caretRect;
@property(nonatomic) NSRange marked;
@property(nonatomic, copy) NSString *doc;
@property(nonatomic) NSRange sel;
@property(nonatomic) BOOL isFirstResponder;
@property(nonatomic) BOOL deferResign;
@property(nonatomic) int becomeCalls;
@property(nonatomic) int resignCalls;
@property(nonatomic, strong) FakeImeDelegate *delegate;
@end

@implementation FakeImeView
- (instancetype)init {
  if (!(self = [super init])) return nil;
  _marked = NSMakeRange(NSNotFound, 0);
  _doc = @"";
  _sel = NSMakeRange(0, 0);
  _delegate = [FakeImeDelegate new];
  return self;
}
- (id<MBImeDelegate>)imeInputDelegate { return self.delegate; }
- (BOOL)becomeFirstResponder {
  self.becomeCalls++;
  if (!mb_ime_can_become_first_responder(self)) return NO;
  self.isFirstResponder = YES;
  return YES;
}
- (BOOL)resignFirstResponder {
  self.resignCalls++;
  if (self.deferResign) return NO;
  [self.delegate.events addObject:(self.marked.location == NSNotFound ? @"resignClean" : @"resignWithMarked")];
  self.isFirstResponder = NO;
  return YES;
}
@end

static int failed;

#define CHECK(c)                                                      \
  do {                                                                \
    if (!(c)) {                                                       \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                     \
    }                                                                 \
  } while (0)

int main(void) {
  @autoreleasepool {
    FakeImeView *v = [FakeImeView new];

    // 1. Idle view cannot become first responder (blocks UIKit modal/tab/window auto-restore).
    CHECK(!mb_ime_can_become_first_responder(v));
    CHECK(![v becomeFirstResponder]);
    CHECK(!v.isFirstResponder);

    // 2. Activating IME enables becoming first responder cleanly.
    mb_ime_set(v, YES, CGRectMake(10, 20, 2, 18), @"hello", 5, 5);
    CHECK(v.imeActive && v.isFirstResponder);
    CHECK(mb_ime_can_become_first_responder(v));
    CHECK([v.doc isEqualToString:@"hello"] && NSEqualRanges(v.sel, NSMakeRange(5, 0)));

    // 3. Ongoing Chinese Pinyin composition in the same focused field keeps marked text intact.
    v.doc = @"nihao";
    v.marked = NSMakeRange(0, 5);
    v.sel = NSMakeRange(5, 0);
    [v.delegate.events removeAllObjects];
    mb_ime_set(v, YES, CGRectMake(14, 20, 2, 18), @"nihao", 5, 5);
    CHECK(NSEqualRanges(v.marked, NSMakeRange(0, 5)));
    CHECK(v.delegate.events.count == 0);
    // While active, idle resign guard must be a no-op.
    mb_ime_resign_if_idle(v);
    CHECK(v.isFirstResponder);

    // 4. Leaving IME with open Pinyin marked text clears marked + notifies delegate before resigning.
    mb_ime_set(v, NO, CGRectZero, @"", 0, 0);
    CHECK(!v.imeActive && !v.isFirstResponder);
    CHECK(v.marked.location == NSNotFound);
    CHECK([v.doc isEqualToString:@""] && NSEqualRanges(v.sel, NSMakeRange(0, 0)));
    CHECK(([v.delegate.events isEqualToArray:@[@"textWillChange", @"textDidChange", @"resignClean"]]));

    // 5. Wedged first responder (was == NO while isFirstResponder == YES) must still resign on mb_ime_set(NO).
    mb_ime_set(v, YES, CGRectMake(0, 0, 2, 18), @"a", 1, 1);
    v.deferResign = YES;
    mb_ime_set(v, NO, CGRectZero, @"", 0, 0);
    CHECK(!v.imeActive && v.isFirstResponder);
    v.deferResign = NO;
    int resignsBefore = v.resignCalls;
    mb_ime_set(v, NO, CGRectZero, @"", 0, 0);
    CHECK(v.resignCalls == resignsBefore + 1 && !v.isFirstResponder);

    // 6. Idle resign helper (called on keyboard show/frame/window key/app active/nav_put) clears any wedged responder.
    v.imeActive = NO;
    v.isFirstResponder = YES;
    v.doc = @"ni";
    v.marked = NSMakeRange(0, 2);
    v.sel = NSMakeRange(2, 0);
    [v.delegate.events removeAllObjects];
    mb_ime_resign_if_idle(v);
    CHECK(!v.isFirstResponder && v.marked.location == NSNotFound);
    CHECK(([v.delegate.events isEqualToArray:@[@"textWillChange", @"textDidChange", @"resignClean"]]));

    // 7. Out-of-bounds selection indices clamp cleanly.
    mb_ime_set(v, NO, CGRectZero, @"xy", -3, 999);
    CHECK(NSEqualRanges(v.sel, NSMakeRange(0, 2)));
  }
  if (!failed) printf("ios_ime: ok\n");
  return failed;
}
