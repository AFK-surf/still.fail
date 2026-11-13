// iOS soft keyboard responder and marked-text transitions (ios_app.m, scripts/ios_ime_test.m).
// Keeps UIKit firstResponder synchronized with MBView.imeActive and clears marked composition before resigning.

@protocol MBImeDelegate <NSObject>
- (void)textWillChange:(id)textInput;
- (void)textDidChange:(id)textInput;
- (void)selectionWillChange:(id)textInput;
- (void)selectionDidChange:(id)textInput;
@end

@protocol MBImeView <NSObject>
@property(nonatomic) BOOL imeActive;
@property(nonatomic) CGRect caretRect;
@property(nonatomic) NSRange marked;
@property(nonatomic, copy) NSString *doc;
@property(nonatomic) NSRange sel;
@property(nonatomic, readonly) BOOL isFirstResponder;
- (id<MBImeDelegate>)imeInputDelegate;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
@end

static inline NSRange mb_ime_clamp_sel(NSString *text, NSInteger a, NSInteger b) {
  NSUInteger start = MIN((NSUInteger)MAX(0, a), text.length);
  NSUInteger end = MIN((NSUInteger)MAX(a, b), text.length);
  return NSMakeRange(start, end - start);
}

static inline void mb_ime_clear_marked(id<MBImeView> v, NSString *text, NSRange sel) {
  id<MBImeDelegate> d = [v imeInputDelegate];
  [d textWillChange:v];
  v.marked = NSMakeRange(NSNotFound, 0);
  v.doc = text;
  v.sel = sel;
  [d textDidChange:v];
}

static inline BOOL mb_ime_can_become_first_responder(id<MBImeView> v) {
  return v && v.imeActive;
}

static inline void mb_ime_resign_if_idle(id<MBImeView> v) {
  if (!v || v.imeActive || !v.isFirstResponder) return;
  if (v.marked.location != NSNotFound) {
    NSString *doc = v.doc ?: @"";
    mb_ime_clear_marked(v, doc, mb_ime_clamp_sel(doc, (NSInteger)v.sel.location, (NSInteger)(v.sel.location + v.sel.length)));
  }
  [v resignFirstResponder];
}

static inline void mb_ime_set(id<MBImeView> v, BOOL active, CGRect caret, NSString *text, NSInteger a, NSInteger b) {
  if (!v) return;
  BOOL was = v.imeActive;
  v.imeActive = active;
  v.caretRect = caret;
  // When leaving IME or activating a fresh field while marked composition is still open (e.g. Chinese Pinyin),
  // discard marked text and notify the input delegate first so UIKit finishes composition cleanly before resigning.
  NSString *t = text ?: @"";
  NSRange sel = mb_ime_clamp_sel(t, a, b);
  if ((!v.imeActive || !was) && v.marked.location != NSNotFound) {
    mb_ime_clear_marked(v, t, sel);
  } else if (v.marked.location == NSNotFound) {
    id<MBImeDelegate> d = [v imeInputDelegate];
    if (![t isEqualToString:v.doc]) {
      [d textWillChange:v];
      v.doc = t;
      v.sel = sel;
      [d textDidChange:v];
    } else if (!NSEqualRanges(sel, v.sel)) {
      [d selectionWillChange:v];
      v.sel = sel;
      [d selectionDidChange:v];
    }
  }
  if (v.imeActive && !was) [v becomeFirstResponder];
  if (!v.imeActive && (was || v.isFirstResponder)) [v resignFirstResponder];
}
