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

// People as an icon (`avatars:` then each `rrggbbaa,letter` apart by `;`, at most three): their discs, each its letter
// in white on its colour, the ones after a little over the one before, in their own colours (not the bar's tint).
static UIImage *nav_avatars(NSString *spec, CGFloat size) {
  NSArray<NSString *> *each = [[spec substringFromIndex:8] componentsSeparatedByString:@";"];
  NSUInteger n = MIN(each.count, (NSUInteger)3);
  if (!n) return nil;
  CGFloat d = size, step = size * 0.6, ring = 1.5;
  CGSize all = CGSizeMake(d + step * (n - 1), d);
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:all];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    for (NSUInteger i = 0; i < n; i++) {
      NSArray<NSString *> *p = [each[i] componentsSeparatedByString:@","];
      if (p.count < 2) continue;
      unsigned long long c = strtoull(p[0].UTF8String, NULL, 16);
      UIColor *ground = [UIColor colorWithRed:((c >> 24) & 0xFF) / 255.0 green:((c >> 16) & 0xFF) / 255.0
                                          blue:((c >> 8) & 0xFF) / 255.0 alpha:1];
      CGRect disc = CGRectMake(step * i, 0, d, d);
      // (cut out of the one before by a ring, as the app's stack has them)
      if (i > 0) [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(disc, -ring, -ring)] fillWithBlendMode:kCGBlendModeClear alpha:1];
      [ground setFill];
      [[UIBezierPath bezierPathWithOvalInRect:disc] fill];
      NSString *letter = p[1];
      UIFont *font = [UIFont systemFontOfSize:d * 0.5 weight:UIFontWeightSemibold];
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

// A workspace's mark (`badge:rrggbbaa,letter`) as a bar's button has it: its colour, the glass's tint (the system's
// prominent glass, filled with it), and its letter (or emoji) in white, alone (the user, 2026-10-27: filling its glass,
// still glass).
static UIColor *nav_badge_tint(NSString *spec) {
  NSArray<NSString *> *p = [[spec substringFromIndex:6] componentsSeparatedByString:@","];
  if (p.count < 2) return nil;
  unsigned long long c = strtoull(p[0].UTF8String, NULL, 16);
  return [UIColor colorWithRed:((c >> 24) & 0xFF) / 255.0 green:((c >> 16) & 0xFF) / 255.0 blue:((c >> 8) & 0xFF) / 255.0 alpha:1];
}

static UIImage *nav_badge_glyph(NSString *spec, CGFloat size) {
  NSArray<NSString *> *p = [[spec substringFromIndex:6] componentsSeparatedByString:@","];
  if (p.count < 2) return nil;
  NSString *letter = [[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@","];
  UIFont *font = [UIFont systemFontOfSize:size * 0.75 weight:UIFontWeightSemibold];
  NSDictionary *attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : UIColor.whiteColor};
  CGSize s = [letter sizeWithAttributes:attrs];
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
  UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    [letter drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withAttributes:attrs];
  }];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// The side of a workspace's picture on the bar's button, a disc on its glass: as large as the bar draws an image (the
// glass larger round it, tinted as the picture is).
static const CGFloat nav_mark_picture = 34;

// A picture's colour, all of it as one (its glass's tint).
static UIColor *nav_mean(UIImage *img) {
  unsigned char px[4] = {0};
  CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
  CGContextRef c = CGBitmapContextCreate(px, 1, 1, 8, 4, rgb, kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(rgb);
  if (!c) return nil;
  CGContextSetInterpolationQuality(c, kCGInterpolationMedium);
  CGContextDrawImage(c, CGRectMake(0, 0, 1, 1), img.CGImage);
  CGContextRelease(c);
  if (!px[3]) return nil;
  return [UIColor colorWithRed:px[0] / (CGFloat)px[3] green:px[1] / (CGFloat)px[3] blue:px[2] / (CGFloat)px[3] alpha:1];
}

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
  if ([icon hasPrefix:@"avatars:"]) return nav_avatars(icon, size);
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
@end

@implementation MBSlot
- (UIViewController *)childViewControllerForStatusBarStyle { return the_controller; }
- (UIViewController *)childViewControllerForStatusBarHidden { return the_controller; }
- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden { return the_controller; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return the_controller.supportedInterfaceOrientations; }
@end

API_AVAILABLE(ios(18.0))
@interface MBTabs : UITabBarController <UITabBarControllerDelegate>
@property(nonatomic, copy) NSString *spec;
@property(nonatomic, copy) NSString *tabsKey;
@property(nonatomic, copy) NSString *action;
@property(nonatomic) BOOL shown;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UINavigationController *> *navs;
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
      if ([t.identifier isEqualToString:self.action]) r = [t frameInView:v];
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
    UIViewController *slot = nav.viewControllers.firstObject;
    NSMutableArray<UIBarButtonItem *> *made = [NSMutableArray array];
    // (`lead/` the bar's leading items: the workspace's, where the system puts back and close, the column's top)
    NSMutableArray<UIBarButtonItem *> *lead = [NSMutableArray array];
    // (`act/` the toolbar's: down the side, at the column's foot over the tabs, 待处理's bell by them)
    NSMutableArray<UIBarButtonItem *> *foot = [NSMutableArray array];
    NSString *lastIdent = @"";
    for (NSDictionary *d in items) {
      // (a picture the host loads: drawn in once it is here, on the item made, while it is shown)
      __block __weak UIBarButtonItem *drawn = nil;
      NSString *spec = d[@"icon"];
      // (a workspace's mark filling its glass, still glass: with no picture, the glass in its colour and its letter on
      // it; with one, the picture a disc as large as the bar draws one, on a glass of its colour: the user, 2026-10-27)
      UIColor *tint = nil;
      NSString *picture = nil, *mark = spec;
      if ([spec hasPrefix:@"badge:"]) {
        NSRange pic = [spec rangeOfString:@"\x1e"];
        if (pic.location == NSNotFound) tint = nav_badge_tint(spec);
        else {
          picture = [spec substringFromIndex:pic.location + 1];
          mark = [spec substringToIndex:pic.location];
        }
      }
      UIImage *icon = tint ? nav_badge_glyph(spec, 24)
                      : picture ? nav_picture(picture, nav_mark_picture, YES, ^{
                          UIImage *got = nav_picture(picture, nav_mark_picture, YES, nil);
                          drawn.image = got;
                          drawn.tintColor = nav_mean(got) ?: drawn.tintColor;
                        }) ?: nav_badge(mark, nav_mark_picture)
                      : [spec length] ? nav_any_then(spec, 24, ^{
                          drawn.image = nav_any(spec, 24);
                        })
                                      : nav_letter(d[@"title"], 24);
      BOOL prominent = [d[@"prominent"] boolValue];
      NSString *ident = d[@"id"];
      // (said with where the item is in the app's view, for what opens from it: a popover at it)
      __block __weak UIBarButtonItem *weak = nil;
      UIBarButtonItem *b = [[UIBarButtonItem alloc]
          initWithPrimaryAction:[UIAction actionWithTitle:d[@"title"]
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
                                                  }]];
      weak = b;
      // (with a menu: its rows, the one checked so, each said as chosen)
      NSArray *rows = d[@"menu"];
      if (rows.count) {
        // (rows in groups, a line between them where a row is "-"; each its icon, if it says one)
        NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
        NSMutableArray<UIMenuElement *> *acts = [NSMutableArray array];
        void (^close)(void) = ^{
          if (acts.count) [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                                          options:UIMenuOptionsDisplayInline children:[acts copy]]];
          [acts removeAllObjects];
        };
        for (NSDictionary *m in rows) {
          NSString *row = m[@"id"];
          if ([row isEqualToString:@"-"]) {
            close();
            continue;
          }
          NSString *mi = m[@"icon"];
          UIImage *img = [mi length] ? nav_any(mi, 22) : nil;
          UIAction *x = [UIAction actionWithTitle:m[@"title"] image:img identifier:nil handler:^(UIAction *a) {
            say_system(@{@"nav" : row});
          }];
          x.state = [m[@"checked"] boolValue] ? UIMenuElementStateOn : UIMenuElementStateOff;
          [acts addObject:x];
        }
        close();
        b = [[UIBarButtonItem alloc] initWithImage:icon menu:[UIMenu menuWithChildren:groups]];
        b.title = d[@"title"];
        drawn = b;
      }
#ifdef __IPHONE_26_0
      if (@available(iOS 26.0, *)) {
        if (prominent || tint || picture) {
          b.style = UIBarButtonItemStyleProminent;
          b.tintColor = tint ?: picture ? (nav_mean(icon) ?: nav_badge_tint(mark)) : accent;
        } else {
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
      drawn = b;
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
    // (from the bar's end in: the action most wanted outermost)
    slot.navigationItem.rightBarButtonItems = made.reverseObjectEnumerator.allObjects;
    slot.navigationItem.leftBarButtonItems = lead;
    slot.toolbarItems = foot;
    // (the chosen tab's alone: shown on two, the column shows its items twice; didSelectTab)
    [nav setToolbarHidden:(foot.count == 0 || nav != self.selectedViewController) animated:NO];
    nav_title(slot.navigationItem, bare ? title : @"", ink);
    // (put away only when something is up over the whole window, its title alone: hidden with its items gone, the system's
    // column keeps showing the views of those it had, a page's actions on the next tab, the outer screen's workspace
    // button on the inner one; the user, 2026-10-27. Shown with none it takes no room: there, its items are the column's)
    [nav setNavigationBarHidden:(bare && made.count + lead.count == 0) animated:bare];
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
// No tabs: one tab, the bar hidden, the app's controller in it.
- (void)applyNone {
  UINavigationController *nav = [self navFor:@""];
  if (self.tabsKey.length || !self.tabs.count) {
    self.tabsKey = @"";
    self.choosing = YES;
    self.tabs = @[ [[UITab alloc] initWithTitle:@"" image:nil identifier:@"" viewControllerProvider:^(UITab *t) { return nav; }] ];
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
  // the tabs again only as they change (their ids, words and icons)
  NSMutableString *key = [NSMutableString string];
  // (an icon that changes, the stations' at a glance, drawn again in place: below)
  // (and words that change, the workspace's name on 我的: set in place too. A tab made again over its controller, while
  // the one before still has it, is refused: UIKit's "cannot be shared between multiple UITab", the app stopped)
  for (NSDictionary *t in places) [key appendFormat:@"%@\x1e", t[@"id"]];
  if (act) [key appendFormat:@"!%@\x1f%@\x1f%@", act[@"id"], act[@"title"], act[@"icon"]];
  if (![key isEqualToString:self.tabsKey]) {
    self.tabsKey = key;
    NSMutableArray<UITab *> *made = [NSMutableArray array];
    for (NSDictionary *t in places) {
      UINavigationController *nav = [self navFor:t[@"id"]];
      [made addObject:[[UITab alloc] initWithTitle:t[@"title"] image:nav_any(t[@"icon"], 26) identifier:t[@"id"]
                                viewControllerProvider:^(UITab *x) { return nav; }]];
    }
    // (the action a tab of its own the system sets apart at the bar's end, as Xiaohongshu's 发布 is, on the system's
    // glass, its icon in the accent: never chosen, shouldSelectTab says it)
    self.action = act[@"id"];
    if (act) {
      UINavigationController *own = [self navFor:act[@"id"]];
      UITab *x = [[UITab alloc] initWithTitle:act[@"title"] image:[[nav_icon(act[@"icon"], 26) imageWithTintColor:accent] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] identifier:act[@"id"]
                       viewControllerProvider:^(UITab *t) { return own; }];
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


// How round the window's corners are (@hostapi.window_corner): the app fills the screen, whose own corners (40 and
// more) are rounder than anything by them could follow within the corner rule's ranges: said as none; but where the
// system lays out the app's tabs in every pose (an iPhone Duo's: mb_host_nav_able), the screen's own, the cards along
// its edges following it (the user, 2026-10-27): read off a view the window's size concentric with it (iOS 26's
// containerConcentricRadius).
static UIView *corner_probe;
double mb_host_window_corner(void) {
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
      corner_probe.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius containerConcentricRadius]];
    }
    if (corner_probe.superview != win) [win addSubview:corner_probe];
    corner_probe.frame = win.bounds;
    [corner_probe layoutIfNeeded];
    double k = [corner_probe effectiveRadiusForCorner:UIRectCornerTopLeft];
    static double said_k = -1;
    if (k != said_k) {
      said_k = k;
      say([NSString stringWithFormat:@"ios: the screen's corner %.1f", k]);
    }
    return k;
  }
#endif
  return 0;
}
