// The system's own bars for the app's places and actions (@hostapi.nav_bar, src/hostapi/nav.mbt): where the system
// lays out an app's tabs in every pose of its screens (an iPhone Duo's, iOS 27.1: down the trailing edge on its side
// and on its outer screen, across the top and foot upright), the app's tabs, its actions and its menus handed to it,
// laid out and drawn by it in its own glass. Included by ios_app.m, whose statics it uses (the_view, the_controller,
// say_system); all of it apart from the app's own frame, which every other iPhone keeps. What came after iOS 18 is
// under its SDK's macro as well as @available: the app is built with iOS 18's SDK too (CI's Xcode 16).

// ---- the system's own bars (@hostapi.nav_bar: src/hostapi/nav.mbt) ----
// The app's view in a UITabBarController's chosen tab, each tab a UINavigationController over a slot the app's
// controller moves into as its tab is chosen: the places the app hands over its tabs, its actions the navigation bar's
// items, laid out by the system as its own apps' are (down the trailing edge on an iPhone Duo's outer screen and its
// inner one on its side, iOS 27.1; across the view's top and foot upright), in its own glass. No tabs (the app's own
// frame on a phone): neither bar, the app's view the whole window as before. Chosen, a tab or an item said to the app on
// the system channel (`{"nav": id}`).

// An icon of the app's (sfapp icon_data: groups of a kind (0 a line, 1 closed, 2 filled), a stroke's width, how many
// points and the points, on a 24 grid) as a template image `size` across, for the bars to tint.
static UIImage *nav_icon(NSString *data, CGFloat size) {
  NSArray<NSString *> *parts = [data componentsSeparatedByString:@" "];
  NSMutableArray<NSNumber *> *n = [NSMutableArray arrayWithCapacity:parts.count];
  for (NSString *p in parts)
    if (p.length) [n addObject:@(p.doubleValue)];
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    CGContextScaleCTM(ctx.CGContext, size / 24, size / 24);
    [UIColor.blackColor setStroke];
    [UIColor.blackColor setFill];
    NSUInteger i = 0;
    // (7: a piece of one shape of many, filled once the pieces end, by the even-odd rule where its width is 1)
    UIBezierPath *compound = nil;
    while (i + 2 < n.count) {
      int kind = n[i].intValue;
      double width = n[i + 1].doubleValue;
      NSUInteger k = n[i + 2].unsignedIntegerValue;
      i += 3;
      if (i + 2 * k > n.count) break;
      if (kind != 7 && compound) {
        [compound fill];
        compound = nil;
      }
      if (kind == 7) {
        if (!compound) {
          compound = [UIBezierPath bezierPath];
          compound.usesEvenOddFillRule = width > 0.5;
        }
        for (NSUInteger j = 0; j < k; j++) {
          CGPoint pt = CGPointMake(n[i + 2 * j].doubleValue, n[i + 2 * j + 1].doubleValue);
          if (j == 0) [compound moveToPoint:pt];
          else [compound addLineToPoint:pt];
        }
        [compound closePath];
        i += 2 * k;
        continue;
      }
      // (4: the alpha of what comes after, its width; 5: a shape cut out of what is drawn)
      if (kind == 4) {
        CGContextSetAlpha(ctx.CGContext, width);
        continue;
      }
      UIBezierPath *p = [UIBezierPath bezierPath];
      p.lineCapStyle = kCGLineCapRound;
      p.lineJoinStyle = kCGLineJoinRound;
      for (NSUInteger j = 0; j < k; j++) {
        CGPoint pt = CGPointMake(n[i + 2 * j].doubleValue, n[i + 2 * j + 1].doubleValue);
        if (j == 0) [p moveToPoint:pt];
        else [p addLineToPoint:pt];
      }
      i += 2 * k;
      if (kind >= 1) [p closePath];
      if (kind == 5) [p fillWithBlendMode:kCGBlendModeClear alpha:1];
      else if (kind == 2) [p fill];
      else {
        p.lineWidth = width;
        [p stroke];
      }
    }
    if (compound) [compound fill];
  }];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// People as an icon (`avatars:` then each `rrggbbaa,letter` (an alpha of 0: no disc, the letter alone) apart by `\x1d`, at most three; `\x1f` and a picture's
// address after one that has one): their discs, each its picture once loaded (`then` told), else its letter in white
// on its colour, the ones after a little over the one before, in their own colours (not the bar's tint).
static UIImage *nav_picture(NSString *url, CGFloat size, BOOL round, void (^then)(void));
static UIImage *nav_avatars(NSString *spec, CGFloat size, void (^then)(void)) {
  NSArray<NSString *> *each = [[spec substringFromIndex:8] componentsSeparatedByString:@"\x1d"];
  NSUInteger n = MIN(each.count, (NSUInteger)3);
  if (!n) return nil;
  CGFloat d = size, step = size * 0.6, ring = 1.5;
  CGSize all = CGSizeMake(d + step * (n - 1), d);
  NSMutableArray *faces = [NSMutableArray array];
  for (NSUInteger i = 0; i < n; i++) {
    NSRange pic = [each[i] rangeOfString:@"\x1f"];
    UIImage *got = pic.location == NSNotFound ? nil : nav_picture([each[i] substringFromIndex:pic.location + 1], d, YES, then);
    [faces addObject:got ?: NSNull.null];
  }
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:all];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    for (NSUInteger i = 0; i < n; i++) {
      NSString *one = each[i];
      NSRange pic = [one rangeOfString:@"\x1f"];
      if (pic.location != NSNotFound) one = [one substringToIndex:pic.location];
      NSArray<NSString *> *p = [one componentsSeparatedByString:@","];
      if (p.count < 2) continue;
      unsigned long long c = strtoull(p[0].UTF8String, NULL, 16);
      UIColor *ground = [UIColor colorWithRed:((c >> 24) & 0xFF) / 255.0 green:((c >> 16) & 0xFF) / 255.0
                                          blue:((c >> 8) & 0xFF) / 255.0 alpha:1];
      CGRect disc = CGRectMake(step * i, 0, d, d);
      // (cut out of the one before by a ring, as the app's stack has them)
      if (i > 0) [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(disc, -ring, -ring)] fillWithBlendMode:kCGBlendModeClear alpha:1];
      if (faces[i] != NSNull.null) {
        [(UIImage *)faces[i] drawInRect:disc];
        continue;
      }
      // (a colour of no alpha: the letter (an emoji) on the glass alone, larger)
      BOOL bare = (c & 0xFF) == 0;
      if (!bare) {
        [ground setFill];
        [[UIBezierPath bezierPathWithOvalInRect:disc] fill];
      }
      NSString *letter = [[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@","];
      UIFont *font = [UIFont systemFontOfSize:d * (bare ? 0.62 : 0.5) weight:UIFontWeightSemibold];
      NSDictionary *attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : UIColor.whiteColor};
      CGSize s = [letter sizeWithAttributes:attrs];
      [letter drawAtPoint:CGPointMake(CGRectGetMidX(disc) - s.width / 2, CGRectGetMidY(disc) - s.height / 2) withAttributes:attrs];
    }
  }];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// A workspace's mark as an icon (`badge:rrggbbaa,letter`): its letter (or emoji) in white on a rounded square of its
// colour, in its own colours, a little smaller than the tabs' icons so the system's lit ground shows round it.
static UIImage *nav_badge(NSString *spec, CGFloat size) {
  NSArray<NSString *> *p = [[spec substringFromIndex:6] componentsSeparatedByString:@","];
  if (p.count < 2) return nil;
  unsigned long long c = strtoull(p[0].UTF8String, NULL, 16);
  UIColor *ground = [UIColor colorWithRed:((c >> 24) & 0xFF) / 255.0 green:((c >> 16) & 0xFF) / 255.0
                                      blue:((c >> 8) & 0xFF) / 255.0 alpha:1];
  NSString *letter = [[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@","];
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    CGRect box = CGRectInset(CGRectMake(0, 0, size, size), 1, 1);
    [ground setFill];
    [[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:size * 0.28] fill];
    UIFont *font = [UIFont systemFontOfSize:size * 0.5 weight:UIFontWeightSemibold];
    NSDictionary *attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : UIColor.whiteColor};
    CGSize s = [letter sizeWithAttributes:attrs];
    [letter drawAtPoint:CGPointMake(CGRectGetMidX(box) - s.width / 2, CGRectGetMidY(box) - s.height / 2) withAttributes:attrs];
  }];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// The side of a workspace's mark on the bar's button (nav_avatars): the glass a thin ring round it.
static const CGFloat nav_face = 40;

// A picture by its address (an https link, a data: URL) as a mark: rounded, in its own colours; loaded once, kept by
// its address (nil while it comes: `then` is told once it is here, each asker's, not the first's alone: the bars are
// made again while it comes, and only the items made last are shown).
static NSMutableDictionary<NSString *, UIImage *> *nav_pictures;
static NSMutableDictionary<NSString *, NSMutableArray *> *nav_loading;
static UIImage *nav_picture(NSString *url, CGFloat size, BOOL round, void (^then)(void)) {
  if (!nav_pictures) {
    nav_pictures = [NSMutableDictionary dictionary];
    nav_loading = [NSMutableDictionary dictionary];
  }
  NSString *key = [NSString stringWithFormat:@"%@\x1f%.0f%@", url, size, round ? @"o" : @""];
  UIImage *had = nav_pictures[key];
  if (had) return had;
  void (^made)(NSData *) = ^(NSData *data) {
    UIImage *raw = data ? [UIImage imageWithData:data] : nil;
    if (!raw) return;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
      CGRect box = round ? CGRectMake(0, 0, size, size) : CGRectInset(CGRectMake(0, 0, size, size), 1, 1);
      [(round ? [UIBezierPath bezierPathWithOvalInRect:box] : [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:size * 0.24]) addClip];
      // (covering the square, as the app's marks are: FitCover)
      CGFloat k = MAX(box.size.width / raw.size.width, box.size.height / raw.size.height);
      CGSize s = CGSizeMake(raw.size.width * k, raw.size.height * k);
      [raw drawInRect:CGRectMake(CGRectGetMidX(box) - s.width / 2, CGRectGetMidY(box) - s.height / 2, s.width, s.height)];
    }];
    nav_pictures[key] = [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
  };
  if ([url hasPrefix:@"data:"]) {
    NSRange comma = [url rangeOfString:@","];
    if (comma.location == NSNotFound) return nil;
    made([[NSData alloc] initWithBase64EncodedString:[url substringFromIndex:comma.location + 1]
                                             options:NSDataBase64DecodingIgnoreUnknownCharacters]);
    return nav_pictures[key];
  }
  NSURL *u = [NSURL URLWithString:url];
  if (!u) return nil;
  NSMutableArray *waiting = nav_loading[key];
  if (waiting) {
    if (then) [waiting addObject:then];
    return nil;
  }
  nav_loading[key] = waiting = [NSMutableArray array];
  if (then) [waiting addObject:then];
  [[NSURLSession.sharedSession dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSArray *told = nav_loading[key];
      [nav_loading removeObjectForKey:key];
      made(err ? nil : data);
      if (nav_pictures[key])
        for (void (^t)(void) in told) t();
    });
  }] resume];
  return nil;
}

// An icon of the app's in any of its forms: people's faces, a workspace's mark (its picture, `\x1e` and its
// address after it, in place of the mark once loaded: `then` told), else its shapes.
static UIImage *nav_any_then(NSString *icon, CGFloat size, void (^then)(void)) {
  NSRange pic = [icon rangeOfString:@"\x1e"];
  if (pic.location != NSNotFound) {
    UIImage *got = nav_picture([icon substringFromIndex:pic.location + 1], size, NO, then);
    if (got) return got;
    icon = [icon substringToIndex:pic.location];
  }
  if ([icon hasPrefix:@"avatars:"]) return nav_avatars(icon, size, then);
  if ([icon hasPrefix:@"badge:"]) return nav_badge(icon, size);
  return nav_icon(icon, size);
}

static UIImage *nav_any(NSString *icon, CGFloat size) { return nav_any_then(icon, size, nil); }

// An item with no icon of its own (a workspace's): its first letter, set in the system's font, as its icon.
static UIImage *nav_letter(NSString *title, CGFloat size) {
  if (!title.length) return nil;
  NSString *letter = [title substringWithRange:[title rangeOfComposedCharacterSequenceAtIndex:0]];
  UIFont *font = [UIFont systemFontOfSize:size * 0.72 weight:UIFontWeightSemibold];
  NSDictionary *attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : UIColor.blackColor};
  CGSize s = [letter sizeWithAttributes:attrs];
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    [letter drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withAttributes:attrs];
  }];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// The system's tab bar for the app's places (iOS 18's UITabBarController with UITabs: on an iPhone Duo's inner screen on
// its side and its outer one, iOS 27.1 lays it down the trailing edge at its foot; upright, across the view's foot), in
// its own glass, with its own motion; the one action most wanted a tab of its own after them (pinned, iOS 27's prominent tab, set
// apart as the system sets search apart), which does what it says and is never chosen. Each tab a
// UINavigationController over a slot the app's controller moves into as its tab is chosen, its bar hidden: what a page
// does is the page's own, in its content. No tabs (the app's own frame on a phone): none, the app's view the whole
// window as before. Chosen, a tab is said to the app on the system channel (`{"nav": id}`).

// A tab's page: the app's controller in it while its tab is chosen, the status bar, the home indicator and the turns
// asked of it.
@interface MBSlot : UIViewController
@property(nonatomic, strong) NSDictionary<NSString *, UIBarButtonItem *> *barItems;
@property(nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *barSpecs;
@property(nonatomic, strong) UIColor *barInk;
@property(nonatomic, strong) UIColor *barAccent;
@end

@implementation MBSlot
- (UIViewController *)childViewControllerForStatusBarStyle { return the_controller; }
- (UIViewController *)childViewControllerForStatusBarHidden { return the_controller; }
- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden { return the_controller; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return the_controller.supportedInterfaceOrientations; }
@end

// The visual capsule follows the app's header height; its touch target remains at least 44 points high.
@interface MBFloatingButton : UIButton
@property(nonatomic) BOOL inputBlocked;
@end
@implementation MBFloatingButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  if (self.inputBlocked) return NO;
  return CGRectContainsPoint(CGRectInset(self.bounds, -MAX(0, (44 - self.bounds.size.width) / 2),
                                        -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}
@end

API_AVAILABLE(ios(18.0))
@interface MBTabs : UITabBarController <UITabBarControllerDelegate>
@property(nonatomic, copy) NSString *spec;
@property(nonatomic, copy) NSString *tabsKey;
@property(nonatomic, copy) NSString *action;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UIButton *> *floatingButtons;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *floatingKeys;
@property(nonatomic) BOOL shown;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UINavigationController *> *navs;
// each id's one tab over its controller, kept as tabs come and go: a tab made again over a controller the one before
// still had stopped the app (UIKit's assertion in -[UITab viewController], an iPhone Duo back from hours away,
// 2026-10-30..11-01), even with the tabs before let go of first
@property(nonatomic, strong) NSMutableDictionary<NSString *, UITab *> *tabsById;
// (a tab chosen by the app, not the person: not said back)
@property(nonatomic) BOOL choosing;
// what is pressed, not gone to (the action most wanted, what opens over the page: `act/`): the navigation bar's items,
// not tabs; their key (made again only as it changes)
@property(nonatomic, copy) NSString *actsKey;
// the icon each tab was drawn with, by its id (drawn again only as it changes)
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *icons;
@end


static UIViewController *the_root;

// The app's controller in `slot`, filling it (under the bars: their room the safe area it says, `bars`).
static void nav_put(UIViewController *slot) {
  MBController *c = the_controller;
  if (!c || c.parentViewController == slot) return;
  [slot loadViewIfNeeded];
  if (c.parentViewController) {
    [c willMoveToParentViewController:nil];
    [c.view removeFromSuperview];
    [c removeFromParentViewController];
  }
  [slot addChildViewController:c];
  c.view.frame = slot.view.bounds;
  c.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [slot.view addSubview:c.view];
  [c didMoveToParentViewController:slot];
  [slot setNeedsStatusBarAppearanceUpdate];
  [the_view requestFrame];
}

// The action's icon: the app's icon in white on a disc of its accent, kept as drawn (the system's tab tints it not).
static UIImage *nav_disc(NSString *icon, UIColor *ground, CGFloat size) {
  UIImage *glyph = nav_icon(icon, size * 0.55);
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    [ground setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
    [[glyph imageWithTintColor:UIColor.whiteColor] drawInRect:CGRectMake(size * 0.225, size * 0.225, size * 0.55, size * 0.55)];
  }];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIColor *nav_rgba(id v) {
  uint32_t c = (uint32_t)[v unsignedLongLongValue];
  return [UIColor colorWithRed:((c >> 24) & 0xFF) / 255.0 green:((c >> 16) & 0xFF) / 255.0 blue:((c >> 8) & 0xFF) / 255.0
                         alpha:(c & 0xFF) / 255.0];
}

// The title of what is up over the whole window (a picture's name) over it: on a glass of its own, as the bar's items
// are (iOS 26's UIGlassEffect, a capsule round the words), not bare words over the picture (the user, 2026-10-27); iOS
// 18's bar its words. None: none.
// Native menus share the same rows whether anchored to a bar item or a content button.
static UIMenu *nav_menu(NSArray<NSDictionary *> *rows, void (^chosen)(NSString *)) {
  NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
  NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
  void (^close)(void) = ^{
    if (actions.count) [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
        options:UIMenuOptionsDisplayInline children:[actions copy]]];
    [actions removeAllObjects];
  };
  for (NSDictionary *m in rows) {
    NSString *ident = m[@"id"];
    if ([ident isEqualToString:@"-"]) { close(); continue; }
    UIImage *img = [m[@"icon"] length] ? nav_any(m[@"icon"], 22) : nil;
    UIAction *action = [UIAction actionWithTitle:m[@"title"] image:img identifier:nil handler:^(UIAction *a) { chosen(ident); }];
    action.state = [m[@"checked"] boolValue] ? UIMenuElementStateOn : UIMenuElementStateOff;
    [actions addObject:action];
  }
  close();
  return [UIMenu menuWithChildren:groups];
}

static void nav_title(UINavigationItem *item, NSString *title, UIColor *ink) {
  item.title = nil;
  item.titleView = nil;
  if (!title.length) return;
#ifdef __IPHONE_26_0
  if (@available(iOS 26.0, *)) {
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.textColor = ink;
    l.lineBreakMode = NSLineBreakByTruncatingMiddle;
    CGFloat h = 44, side = 16;
    CGFloat w = MIN(ceil([l sizeThatFits:CGSizeMake(CGFLOAT_MAX, h)].width), 240);
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect new]];
    glass.frame = CGRectMake(0, 0, w + 2 * side, h);
    glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    l.frame = CGRectMake(side, 0, w, h);
    [glass.contentView addSubview:l];
    item.titleView = glass;
    return;
  }
#endif
  item.title = title;
}

@implementation MBTabs
- (UIViewController *)childViewControllerForStatusBarStyle { return the_controller; }
- (UIViewController *)childViewControllerForStatusBarHidden { return the_controller; }
- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden { return the_controller; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return the_controller.supportedInterfaceOrientations; }
- (void)viewDidLoad {
  [super viewDidLoad];
  self.delegate = self;
  self.navs = [NSMutableDictionary dictionary];
  self.tabsById = [NSMutableDictionary dictionary];
  [self applyNone];
}
// Where the system put the action's tab (iOS 27's prominent one: an iPhone Duo's round one at its column's foot) in
// the app's view, said as it moves (`nav_action`; w 0 where none shows), for what the app lines up with it (its
// composer at the foot of the card beside it).
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  UIView *v = the_view;
  CGRect r = CGRectZero;
  if (v && self.action.length && !self.tabBarHidden)
    for (UITab *t in self.tabs)
      if ([t.identifier isEqualToString:self.action]) {
        r = [t frameInView:v];
      }
  if (CGRectIsNull(r) || CGRectIsInfinite(r)) r = CGRectZero;
  static CGRect said;
  if (CGRectEqualToRect(r, said)) return;
  said = r;
  say_system(@{@"nav_action" : @{@"x" : @(r.origin.x), @"y" : @(r.origin.y), @"w" : @(r.size.width), @"h" : @(r.size.height)}});
}
// What is pressed, not gone to, as the navigation bar's own items on every tab's page (the system lays them out:
// down the side with the tabs where its vertical bar is, across the top upright), its title none: the action most
// wanted prominent, on the accent; a dot a badge.
// Bare (something up over the whole window, the tabs put away): `title` over them, the bar put away with none.
- (void)barItems:(NSArray<NSDictionary *> *)items ink:(UIColor *)ink accent:(UIColor *)accent bare:(BOOL)bare title:(NSString *)title {
  NSMutableString *key = [NSMutableString stringWithFormat:@"%d\x1f%@\x1e", bare, bare ? title : @""];
  for (NSDictionary *d in items) {
    [key appendFormat:@"%@\x1f%@\x1f%@\x1f%@", d[@"id"], d[@"icon"], d[@"dot"], d[@"title"]];
    for (NSDictionary *m in d[@"menu"]) [key appendFormat:@"\x1d%@\x1f%@\x1f%@\x1f%@", m[@"id"], m[@"title"], m[@"checked"], m[@"icon"]];
    [key appendString:@"\x1e"];
  }
  [key appendFormat:@"%lu", (unsigned long)self.navs.count];
  if ([key isEqualToString:self.actsKey]) return;
  self.actsKey = key;
  if (getenv("MBUI_NAV_LOG")) {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *d in items) {
      NSMutableArray *rows = [NSMutableArray array];
      for (NSDictionary *m in d[@"menu"]) [rows addObject:m[@"title"] ?: @""];
      [ids addObject:rows.count ? [NSString stringWithFormat:@"%@{%@}", d[@"id"], [rows componentsJoinedByString:@","]] : d[@"id"]];
    }
    say([NSString stringWithFormat:@"NAVLOG bar items: %@", [ids componentsJoinedByString:@" "]]);
  }
  for (NSString *k in self.navs) {
    UINavigationController *nav = self.navs[k];
    MBSlot *slot = (MBSlot *)nav.viewControllers.firstObject;
    NSMutableDictionary *keptItems = [NSMutableDictionary dictionary];
    NSMutableDictionary *keptSpecs = [NSMutableDictionary dictionary];
    NSMutableArray<UIBarButtonItem *> *made = [NSMutableArray array];
    // (`lead/` the bar's leading items: the workspace's, where the system puts back and close, the column's top)
    NSMutableArray<UIBarButtonItem *> *lead = [NSMutableArray array];
    // (`act/` the toolbar's: down the side, at the column's foot over the tabs, 待处理's bell by them)
    NSMutableArray<UIBarButtonItem *> *foot = [NSMutableArray array];
    NSString *lastIdent = @"";
    for (NSDictionary *d in items) {
      NSString *ident = d[@"id"];
      UIBarButtonItem *b = slot.barItems[ident];
      BOOL reuse = b && [slot.barSpecs[ident] isEqual:d] && [slot.barInk isEqual:ink] && [slot.barAccent isEqual:accent];
      if (!reuse) {
        // (the same action said otherwise, its icon, words, menu or dot, in the same colours: the item there changed in
        // place, not made anew, so the system swaps what it shows on the button there and fades none of the column's
        // buttons, as Outlook's do: the user, 2026-10-31; a new item, even with its identifier, is faded in for the old)
        UIBarButtonItem *was = b && [slot.barInk isEqual:ink] && [slot.barAccent isEqual:accent] ? b : nil;
        // (a picture the host loads: drawn in once it is here, on the item, while it is shown and still said so)
        __block __weak UIBarButtonItem *drawn = nil;
        __weak MBSlot *slotWeak = slot;
        BOOL (^still)(void) = ^BOOL { return [slotWeak.barSpecs[ident] isEqual:d]; };
        NSString *spec = d[@"icon"];
        // (a workspace's mark a disc nearly the glass's own size, on the glass as it is: its picture once here, else its
        // letter on its colour, an emoji alone with no colour round it: the user, 2026-10-28)
        if ([spec hasPrefix:@"badge:"]) {
          NSRange pic = [spec rangeOfString:@"\x1e"];
          NSString *mark = pic.location == NSNotFound ? [spec substringFromIndex:6] : [spec substringWithRange:NSMakeRange(6, pic.location - 6)];
          NSRange comma = [mark rangeOfString:@","];
          if (comma.location != NSNotFound && comma.location + 1 < mark.length &&
              ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[mark characterAtIndex:comma.location + 1]])
            mark = [@"00000000" stringByAppendingString:[mark substringFromIndex:comma.location]];
          spec = pic.location == NSNotFound ? [@"avatars:" stringByAppendingString:mark]
                                            : [NSString stringWithFormat:@"avatars:%@\x1f%@", mark, [spec substringFromIndex:pic.location + 1]];
        }
        UIImage *icon = [spec hasPrefix:@"avatars:"] ? nav_avatars(spec, nav_face, ^{
                          if (still()) drawn.image = nav_avatars(spec, nav_face, nil);
                        })
                        : [spec length] ? nav_any_then(spec, 24, ^{
                            if (still()) drawn.image = nav_any(spec, 24);
                          })
                                        : nav_letter(d[@"title"], 24);
        BOOL prominent = [d[@"prominent"] boolValue];
        // (said with where the item is in the app's view, for what opens from it: a popover at it)
        __block __weak UIBarButtonItem *weak = nil;
        UIAction *action = [UIAction actionWithTitle:d[@"title"]
                                               image:icon
                                          identifier:nil
                                             handler:^(UIAction *a) {
                                               UIBarButtonItem *it = weak;
                                               UIView *v = the_view;
                                               if (it && v) {
                                                 CGRect r = [it frameInView:v];
                                                 say_system(@{@"nav" : ident, @"at" : @[ @(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height) ]});
                                               } else {
                                                 say_system(@{@"nav" : ident});
                                               }
                                             }];
        // (with a menu: its rows, the one checked so, each said as chosen)
        NSArray *rows = d[@"menu"];
        if (rows.count) {
          UIMenu *menu = nav_menu(rows, ^(NSString *row) {
            UIBarButtonItem *it = drawn;
            UIView *v = the_view;
            CGRect r = it && v ? [it frameInView:v] : CGRectZero;
            say_system(@{@"nav" : row, @"at" : @[ @(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height) ]});
          });
          if (was.menu) {
            b = was;
            b.menu = menu;
            b.image = icon;
          } else {
            b = [[UIBarButtonItem alloc] initWithImage:icon menu:menu];
          }
          b.title = d[@"title"];
        } else if (was && !was.menu) {
          b = was;
          b.primaryAction = action;
        } else {
          b = [[UIBarButtonItem alloc] initWithPrimaryAction:action];
        }
        weak = b;
        drawn = b;
#ifdef __IPHONE_26_0
        if (@available(iOS 26.0, *)) {
          // Match the same action across configurations so UIKit carries its glass through the transition.
          b.identifier = ident;
          if (prominent) {
            b.style = UIBarButtonItemStyleProminent;
            b.tintColor = accent;
          } else {
            b.style = UIBarButtonItemStylePlain;
            b.tintColor = ink;
          }
          // (the app's own, 待处理's, on a glass of its own, apart from the card's: the user, 2026-10-27)
          if ([ident hasPrefix:@"act/"] || [ident hasPrefix:@"lead/"]) b.sharesBackground = NO;
#ifdef __IPHONE_27_0
          // (short of room in the column, what goes first: never 待处理's bell, the user 2026-10-27, more wanted than the
          // workspace's and than any page's action; a page's first)
          if (@available(iOS 27.0, *)) {
            // (the bell above all: on the outer screen's short column there is room for one of the app's own)
            if ([ident hasSuffix:@"/attention"]) b.visibilityPriority = UIBarButtonItemVisibilityPriorityHigh;
            else if (![ident hasPrefix:@"act/"] && ![ident hasPrefix:@"lead/"]) b.visibilityPriority = UIBarButtonItemVisibilityPriorityLow;
          }
#endif
          b.badge = [d[@"dot"] boolValue] ? [UIBarButtonItemBadge indicatorBadge] : nil;
        }
#endif
      }
      keptItems[ident] = b;
      keptSpecs[ident] = d;
      if ([ident hasPrefix:@"lead/"]) [lead addObject:b];
      else if ([ident hasPrefix:@"act/"]) [foot addObject:b];
      else {
        // (who's in a page apart from what it does: a glass each, a space between)
        BOOL who = [ident hasPrefix:@"page/who/"];
#ifdef __IPHONE_26_0
        if (@available(iOS 26.0, *))
          if (!who && made.count && [lastIdent hasPrefix:@"page/who/"]) b.sharesBackground = NO;
#endif
        [made addObject:b];
        lastIdent = ident;
      }
    }
    slot.barItems = keptItems;
    slot.barSpecs = keptSpecs;
    slot.barInk = ink;
    slot.barAccent = accent;
    // Only the visible tab transitions; initial setup and the other tabs take their items at once.
    BOOL animate = nav == self.selectedViewController && nav.isViewLoaded && nav.view.window != nil &&
                   !UIAccessibilityIsReduceMotionEnabled();
    // (from the bar's end in: the action most wanted outermost)
    NSArray *right = made.reverseObjectEnumerator.allObjects;
    if (![slot.navigationItem.rightBarButtonItems isEqualToArray:right])
      [slot.navigationItem setRightBarButtonItems:right animated:animate];
    if (![slot.navigationItem.leftBarButtonItems isEqualToArray:lead])
      [slot.navigationItem setLeftBarButtonItems:lead animated:animate];
    if (![slot.toolbarItems isEqualToArray:foot]) [slot setToolbarItems:foot animated:animate];
    // (the chosen tab's alone: shown on two, the column shows its items twice; didSelectTab)
    BOOL hidden = foot.count == 0 || nav != self.selectedViewController;
    if (nav.toolbarHidden != hidden) [nav setToolbarHidden:hidden animated:animate];
    nav_title(slot.navigationItem, bare ? title : @"", ink);
    // (put away only when something is up over the whole window, its title alone: hidden with its items gone, the system's
    // column keeps showing the views of those it had, a page's actions on the next tab, the outer screen's workspace
    // button on the inner one; the user, 2026-10-27. Shown with none it takes no room: there, its items are the column's.
    // Nor with no title either (a remote screen's 全屏): put away, the column showed the chat's actions under it; shown,
    // it is told they are gone, the user 2026-10-29)
    [nav setNavigationBarHidden:(bare && made.count + lead.count == 0 && title.length > 0) animated:bare];
  }
}
- (UINavigationController *)navFor:(NSString *)ident {
  UINavigationController *nav = self.navs[ident];
  if (!nav) {
    nav = [[UINavigationController alloc] initWithRootViewController:[MBSlot new]];
    [nav setNavigationBarHidden:YES animated:NO];
    self.navs[ident] = nav;
  }
  return nav;
}
// The tab of `ident` (made once, over its controller), its words and picture as given.
- (UITab *)tabFor:(NSString *)ident title:(NSString *)title image:(UIImage *)image {
  UITab *tab = self.tabsById[ident];
  if (!tab) {
    UINavigationController *nav = [self navFor:ident];
    tab = [[UITab alloc] initWithTitle:title image:image identifier:ident viewControllerProvider:^(UITab *t) { return nav; }];
    self.tabsById[ident] = tab;
    return tab;
  }
  if (![tab.title isEqualToString:title]) tab.title = title;
  tab.image = image;
  return tab;
}
// The app reserves only the geometry. UIKit owns the glass, press feedback, title, image and popup menu.
- (void)floatingItems:(NSArray<NSDictionary *> *)items ink:(UIColor *)ink {
  if (!self.floatingButtons) {
    self.floatingButtons = [NSMutableDictionary dictionary];
    self.floatingKeys = [NSMutableDictionary dictionary];
  }
  NSMutableSet<NSString *> *live = [NSMutableSet set];
  for (NSDictionary *f in items) {
    NSDictionary *d = f[@"item"];
    NSString *ident = d[@"id"];
    if (!ident.length || !the_view) continue;
    [live addObject:ident];
    UIButton *button = self.floatingButtons[ident];
    if (!button) {
      button = [MBFloatingButton buttonWithType:UIButtonTypeSystem];
      __weak UIButton *pressed = button;
      [button addAction:[UIAction actionWithHandler:^(UIAction *action) {
        UIButton *b = pressed;
        if (b.menu) return;
        CGRect r = [b convertRect:b.bounds toView:the_view];
        say_system(@{@"nav": ident, @"at": @[ @(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height) ]});
      }] forControlEvents:UIControlEventTouchUpInside];
      button.accessibilityIdentifier = ident;
      self.floatingButtons[ident] = button;
    }
    if (button.superview != the_view) [the_view addSubview:button];
    button.frame = CGRectMake([f[@"x"] doubleValue], [f[@"y"] doubleValue], [f[@"w"] doubleValue], [f[@"h"] doubleValue]);
    BOOL blocked = [f[@"blocked"] boolValue];
    ((MBFloatingButton *)button).inputBlocked = blocked;
    button.accessibilityElementsHidden = blocked;
    // Keep the live glass stable while a canvas presenter opens. Its backdrop already
    // changes with the presenter; an extra opacity jump makes every sibling flash.
    NSString *key = [NSString stringWithFormat:@"%@/%@", d, ink];
    if (![self.floatingKeys[ident] isEqualToString:key]) {
      self.floatingKeys[ident] = key;
      BOOL withTitle = [d[@"prominent"] boolValue];
      UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
#ifdef __IPHONE_26_0
      if (@available(iOS 26.0, *)) {
        config = [UIButtonConfiguration glassButtonConfiguration];
      }
#endif
      config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
      config.baseForegroundColor = ink;
      BOOL dot = [d[@"dot"] boolValue];
      config.contentInsets = withTitle ? NSDirectionalEdgeInsetsMake(0, 8, 0, dot ? 24 : 8) : NSDirectionalEdgeInsetsZero;
      config.imagePadding = withTitle ? 6 : 0;
      if (withTitle) {
        config.titleLineBreakMode = NSLineBreakByTruncatingTail;
        config.attributedTitle = [[NSAttributedString alloc] initWithString:d[@"title"] attributes:@{
          NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
        }];
      }
      button.contentHorizontalAlignment = withTitle ? UIControlContentHorizontalAlignmentLeading : UIControlContentHorizontalAlignmentCenter;
      __weak UIButton *weak = button;
      __weak MBTabs *owner = self;
      NSString *icon = d[@"icon"];
      config.image = nav_any_then(icon, 24, ^{
        UIButton *b = weak;
        if (!b || ![owner.floatingKeys[ident] isEqualToString:key]) return;
        UIButtonConfiguration *next = b.configuration;
        next.image = nav_any(icon, 24);
        b.configuration = next;
      });
      button.configuration = config;
      button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
      button.titleLabel.numberOfLines = 1;
      button.accessibilityLabel = d[@"title"];
      button.showsMenuAsPrimaryAction = [d[@"menu"] count] > 0;
      button.menu = [d[@"menu"] count] ? nav_menu(d[@"menu"], ^(NSString *row) {
        UIButton *b = weak;
        CGRect r = b && the_view ? [b convertRect:b.bounds toView:the_view] : CGRectZero;
        say_system(@{@"nav": row, @"at": @[ @(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height) ]});
      }) : nil;
      UIView *badge = [button viewWithTag:71];
      if (!badge) {
        badge = [UIView new]; badge.tag = 71;
        badge.userInteractionEnabled = NO;
        badge.backgroundColor = UIColor.systemBlueColor;
        badge.layer.cornerRadius = 3;
        [button addSubview:badge];
      }
      badge.hidden = !dot;
    }
    [button viewWithTag:71].frame = CGRectMake(button.bounds.size.width - 18, (button.bounds.size.height - 6) / 2, 6, 6);
  }
  for (NSString *ident in [self.floatingButtons.allKeys copy]) {
    if ([live containsObject:ident]) continue;
    [self.floatingButtons[ident] removeFromSuperview];
    [self.floatingButtons removeObjectForKey:ident];
    [self.floatingKeys removeObjectForKey:ident];
  }
}
// No tabs: one tab, the bar hidden, the app's controller in it.
- (void)applyNone {
  [self floatingItems:@[] ink:UIColor.labelColor];
  UINavigationController *nav = [self navFor:@""];
  if (self.tabsKey.length || !self.tabs.count) {
    self.tabsKey = @"";
    self.choosing = YES;
    self.tabs = @[ [self tabFor:@"" title:@"" image:nil] ];
    self.choosing = NO;
  }
  self.tabBarHidden = YES;
  self.shown = NO;
  self.actsKey = nil;
  // (nor the navigation bar's items: the app's own frame has them)
  UIViewController *slot = nav.viewControllers.firstObject;
  slot.navigationItem.rightBarButtonItems = nil;
  [nav setNavigationBarHidden:YES animated:NO];
  nav_put(slot);
}
- (void)apply:(NSDictionary *)b {
  // the places: the items of the groups not folded (the card's own are its page's); the one most wanted apart
  NSMutableArray<NSDictionary *> *places = [NSMutableArray array];
  NSDictionary *act = nil;  // (none: what is pressed is the navigation bar's)
  NSMutableArray<NSDictionary *> *buttons = [NSMutableArray array];
  // (the card in use's own, before the app's own actions, on one glass with 待处理's; the action most wanted apart, last)
  NSMutableArray<NSDictionary *> *own = [NSMutableArray array];
  // (something up over the whole window: the tabs put away, its own items alone)
  BOOL bare = [b[@"bare"] boolValue];
  for (NSDictionary *g in b[@"groups"]) {
    if ([g[@"foldable"] boolValue]) {
      [own addObjectsFromArray:g[@"items"]];
      continue;
    }
    for (NSDictionary *d in g[@"items"]) {
      // (the one most wanted the tab bar's own action at its end, set apart as the system sets search apart; what opens
      // over the page the navigation bar's item)
      if ([d[@"prominent"] boolValue]) act = d;
      else if ([d[@"id"] hasPrefix:@"act/"] || [d[@"id"] hasPrefix:@"lead/"]) [buttons addObject:d];
      else [places addObject:d];
    }
  }
  if (!places.count) {
    [self applyNone];
    return;
  }
  UIColor *ink = [b[@"ink"] unsignedLongLongValue] ? nav_rgba(b[@"ink"]) : UIColor.labelColor;
  UIColor *accent = [b[@"chosen_ink"] unsignedLongLongValue] ? nav_rgba(b[@"chosen_ink"]) : UIColor.tintColor;
  self.tabBar.tintColor = accent;
  self.view.tintColor = accent;
  self.tabBar.unselectedItemTintColor = ink;
  [self floatingItems:bare ? @[] : b[@"floating"] ink:ink];
  // the tabs again only as they change (their ids, words and icons)
  NSMutableString *key = [NSMutableString string];
  // (an icon that changes, the stations' at a glance, drawn again in place: below)
  // (and words that change, the workspace's name on 我的: set in place too. A tab made again over its controller, while
  // the one before still has it, is refused: UIKit's "cannot be shared between multiple UITab", the app stopped)
  for (NSDictionary *t in places) [key appendFormat:@"%@\x1e", t[@"id"]];
  if (act) [key appendFormat:@"!%@\x1f%@\x1f%@\x1f%@", act[@"id"], act[@"title"], act[@"icon"], b[@"chosen_ink"]];
  if (![key isEqualToString:self.tabsKey]) {
    self.tabsKey = key;
    NSMutableArray<UITab *> *made = [NSMutableArray array];
    // (an id twice one tab: one controller is never two tabs')
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *t in places) {
      if ([seen containsObject:t[@"id"]]) continue;
      [seen addObject:t[@"id"]];
      UITab *tab = [self tabFor:t[@"id"] title:t[@"title"] image:nav_any(t[@"icon"], 26)];
      // (the action's tab before, a place now: pinned no more)
      tab.preferredPlacement = UITabPlacementDefault;
      [made addObject:tab];
    }
    // (the action a tab of its own the system sets apart at the bar's end, as Xiaohongshu's 发布 is, on the system's
    // glass, with an accent glyph: never chosen, shouldSelectTab says it)
    self.action = act[@"id"];
    if (act && ![seen containsObject:act[@"id"]]) {
      UITab *x = [self tabFor:act[@"id"] title:act[@"title"] image:[nav_icon(act[@"icon"], 26) imageWithTintColor:accent renderingMode:UIImageRenderingModeAlwaysOriginal]];
      x.preferredPlacement = UITabPlacementPinned;
      [made addObject:x];
    }
    [self.icons removeAllObjects];
    self.choosing = YES;
    // (the tabs before let go of their controllers first: one controller is never two tabs' at once)
    if (self.tabs.count) self.tabs = @[];
    self.tabs = made;
    // (apart, under the tabs' glass in the column, on its own: iOS 27's prominent tab)
#ifdef __IPHONE_27_0
    if (@available(iOS 27.0, *)) self.prominentTabIdentifier = act[@"id"];
#endif
    self.choosing = NO;
  }
  if (!self.icons) self.icons = [NSMutableDictionary dictionary];
  for (UITab *tab in self.tabs)
    for (NSDictionary *t in places)
      if ([t[@"id"] isEqualToString:tab.identifier]) {
        tab.badgeValue = [t[@"dot"] boolValue] ? @"" : nil;
        if (![tab.title isEqualToString:t[@"title"]]) tab.title = t[@"title"];
        if (![self.icons[tab.identifier] isEqualToString:t[@"icon"]]) {
          NSString *icon = t[@"icon"];
          self.icons[tab.identifier] = icon;
          __weak UITab *weak = tab;
          __weak MBTabs *me = self;
          tab.image = nav_any_then(icon, 26, ^{
            // (its picture come: drawn in place of its mark, while the tab still shows it)
            if ([me.icons[weak.identifier] isEqualToString:icon]) weak.image = nav_any(icon, 26);
          });
        }
      }
  if (self.tabBarHidden != bare) [self setTabBarHidden:bare animated:YES];
  self.shown = YES;
  if (bare) [buttons removeAllObjects];
  [buttons insertObjects:own atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, own.count)]];
  NSString *title = [b[@"title"] isKindOfClass:NSString.class] ? b[@"title"] : @"";
  [self barItems:buttons ink:ink accent:accent bare:bare title:title];
  UITab *want = nil;
  for (UITab *tab in self.tabs)
    if ([tab.identifier isEqualToString:b[@"selected"]]) want = tab;
  // (none said, a page of no tab's (the settings): in the tab it was opened over)
  if (!want && ![b[@"selected"] length]) want = self.selectedTab;
  if (!want) want = self.tabs.firstObject;
  if (want && self.selectedTab != want) {
    self.choosing = YES;
    self.selectedTab = want;
    self.choosing = NO;
  }
  UINavigationController *nav = self.navs[self.selectedTab.identifier ?: @""];
  if (nav) nav_put(nav.viewControllers.firstObject);
}
- (BOOL)tabBarController:(UITabBarController *)c shouldSelectTab:(UITab *)tab {
  // the action, and a tab that opens something over the page (`act/`): done, not chosen
  if (self.action && [tab.identifier isEqualToString:self.action]) {
    if (!self.choosing) say_system(@{@"nav" : self.action});
    return NO;
  }
  if ([tab.identifier hasPrefix:@"act/"]) {
    if (!self.choosing) say_system(@{@"nav" : tab.identifier});
    return NO;
  }
  // (the workspace's tab, `menu/`: what it holds opened beside it, where the system has it, not gone to)
  if ([tab.identifier hasPrefix:@"menu/"]) {
    if (!self.choosing) {
      UIView *v = the_view;
      CGRect r = v ? [tab frameInView:v] : CGRectZero;
      say_system(@{@"nav" : tab.identifier, @"at" : @[ @(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height) ]});
    }
    return NO;
  }
  return YES;
}
- (void)tabBarController:(UITabBarController *)c didSelectTab:(UITab *)tab previousTab:(UITab *)was {
  UINavigationController *nav = self.navs[tab.identifier ?: @""];
  if (nav) nav_put(nav.viewControllers.firstObject);
  // (the toolbar the chosen tab's alone: shown on two, the column shows its items twice)
  for (NSString *k in self.navs) {
    UINavigationController *n = self.navs[k];
    [n setToolbarHidden:(n != nav || !n.viewControllers.firstObject.toolbarItems.count) animated:NO];
  }
  if (!self.choosing && tab.identifier.length) say_system(@{@"nav" : tab.identifier});
}
@end


// No room the app keeps at the trailing edge for its own (the system's tab bar is in the safe area it says).
static CGFloat nav_right(void) { return 0; }

// The places as the app has them (nav.mbt NavBar's JSON): 1 where the system's tab bar shows them (an iPhone, iOS 26
// on), 0 where the app draws its own.
static BOOL had_hinge;

// Whether the system lays out the app's tabs and actions itself in every pose (mb_host_nav_bar takes them, the app's
// frame the same on both screens): an iPhone Duo's (a hinge), iOS 27.1 on.
int32_t mb_host_nav_able(void) {
  if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return 0;
  if (![the_root isKindOfClass:MBTabs.class]) return 0;
  // (a hinge once seen where the view is, the inner screen's; or the system's bars down the side, the outer one's)
  if (the_controller.hinge >= 0) had_hinge = YES;
  if (had_hinge) return 1;
#ifdef __IPHONE_27_1
  if (@available(iOS 27.1, *)) return the_controller.traitCollection.verticalBarEdge != UIVerticalBarEdgeUnspecified ? 1 : 0;
#endif
  return 0;
}

int32_t mb_host_nav_bar(moonbit_string_t spec) {
  if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return 0;
  if (@available(iOS 26.0, *)) {
    MBTabs *t = (MBTabs *)the_root;
    if (![t isKindOfClass:MBTabs.class]) return 0;
    NSString *s = mb_ns_from_string(spec);
    if ([s isEqualToString:t.spec]) return t.shown ? 1 : 0;
    t.spec = s;
    NSDictionary *b = [NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if (![b isKindOfClass:NSDictionary.class]) b = @{};
    [t apply:b];
    return t.shown ? 1 : 0;
  }
  return 0;
}


// How round the window's corners are (@hostapi.window_corner, window_corner_at): the app fills the screen, whose own
// corners (40 and more) are rounder than anything by them could follow within the corner rule's ranges: said as none;
// but where the system lays out the app's tabs in every pose (an iPhone Duo's: mb_host_nav_able), the screen's own,
// the cards along its edges following them (the user, 2026-10-27): read off a view the window's size concentric with
// it (iOS 26's containerConcentricRadius), each corner its own (an iPhone Duo's outer screen: 8 along its hinge, 59
// on the other side; a uniform configuration says the roundest of them for all four).
static UIView *corner_probe;
static double corner_said[4] = {-1, -1, -1, -1};
double mb_host_window_corner_at(int k) {
  if (!mb_host_nav_able()) return 0;
#ifdef __IPHONE_26_0
  if (@available(iOS 26.0, *)) {
    UIWindow *win = the_controller.view.window;
    if (!win) return 0;
    if (!corner_probe) {
      corner_probe = [[UIView alloc] initWithFrame:win.bounds];
      corner_probe.hidden = YES;
      corner_probe.userInteractionEnabled = NO;
      corner_probe.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      UICornerRadius *c = [UICornerRadius containerConcentricRadius];
      corner_probe.cornerConfiguration = [UICornerConfiguration configurationWithTopLeftRadius:c topRightRadius:c
                                                                             bottomLeftRadius:c bottomRightRadius:c];
    }
    if (corner_probe.superview != win) [win addSubview:corner_probe];
    corner_probe.frame = win.bounds;
    [corner_probe layoutIfNeeded];
    // (the corner rule's order: top left, then round it)
    static const UIRectCorner which[4] = {UIRectCornerTopLeft, UIRectCornerTopRight, UIRectCornerBottomRight,
                                          UIRectCornerBottomLeft};
    double r = [corner_probe effectiveRadiusForCorner:which[k & 3]];
    if (r != corner_said[k & 3]) {
      corner_said[k & 3] = r;
      say([NSString stringWithFormat:@"ios: the screen's corner %d %.1f", k & 3, r]);
    }
    return r;
  }
#endif
  return 0;
}
double mb_host_window_corner(void) {
  double most = 0;
  for (int k = 0; k < 4; k++) {
    double r = mb_host_window_corner_at(k);
    if (r > most) most = r;
  }
  return most;
}
