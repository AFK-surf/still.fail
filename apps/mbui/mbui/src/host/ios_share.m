// The iOS app's share extension (the system's share sheet: "Share.appex" in the app's PlugIns, built by scripts/ios.sh
// when the app names one: MBUI_IOS_SHARE_PLIST). What another app shares (words, a link, pictures and files) is kept
// for the app in the inbox the two share (their app group's container, its Info.plist's MBUIAppGroup:
// share-inbox/<when>/, share.json written last), and the person is told to open the app, which takes it the next
// time it comes to the front (ios_app.m's shared_in) and shows it as Android's app shows what is shared to it. A share
// extension cannot open its app itself; it says so in the app's own words (its Info.plist's MBUIShareTaking,
// MBUIShareTaken, MBUIShareFailed, MBUIShareDone).
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MBShareController : UIViewController
@property(nonatomic, strong) UILabel *said;
@property(nonatomic, strong) UIButton *done;
@end

static NSString *words(NSString *key, NSString *otherwise) {
  NSString *s = NSBundle.mainBundle.infoDictionary[key];
  return [s isKindOfClass:NSString.class] && s.length ? s : otherwise;
}

// a file's name for the inbox: its own, not a path, never empty
static NSString *safe_name(NSString *n, NSString *otherwise) {
  n = [n.lastPathComponent stringByReplacingOccurrencesOfString:@":" withString:@"-"];
  return n.length && ![n hasPrefix:@"."] ? n : otherwise;
}

// A HEIC picture as JPEG (as the other apps read the library's: the photo picker's Compatible), written to `to`; NO when
// it is no HEIC or could not be.
static BOOL heic_as_jpeg(NSURL *from, NSURL *to) {
  CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)from, NULL);
  if (!src) return NO;
  NSString *type = (__bridge NSString *)CGImageSourceGetType(src);
  UTType *t = type ? [UTType typeWithIdentifier:type] : nil;
  BOOL ok = NO;
  if (t && ([t conformsToType:UTTypeHEIC] || [t conformsToType:UTTypeHEIF])) {
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)to, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
    if (dst) {
      CGImageDestinationAddImageFromSource(dst, src, 0, (__bridge CFDictionaryRef) @{(id)kCGImageDestinationLossyCompressionQuality : @0.9});
      ok = CGImageDestinationFinalize(dst);
      CFRelease(dst);
    }
  }
  CFRelease(src);
  return ok;
}

@implementation MBShareController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  self.said = [UILabel new];
  self.said.text = words(@"MBUIShareTaking", @"…");
  self.said.numberOfLines = 0;
  self.said.textAlignment = NSTextAlignmentCenter;
  self.said.font = [UIFont systemFontOfSize:17];
  self.said.translatesAutoresizingMaskIntoConstraints = NO;
  self.done = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.done setTitle:words(@"MBUIShareDone", @"OK") forState:UIControlStateNormal];
  self.done.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
  self.done.enabled = NO;
  self.done.translatesAutoresizingMaskIntoConstraints = NO;
  [self.done addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.said];
  [self.view addSubview:self.done];
  UILayoutGuide *g = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.said.centerYAnchor constraintEqualToAnchor:g.centerYAnchor constant:-24],
    [self.said.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:32],
    [self.said.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-32],
    [self.done.topAnchor constraintEqualToAnchor:self.said.bottomAnchor constant:24],
    [self.done.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
  ]];
  [self take];
}

- (void)finish {
  [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (void)told:(BOOL)ok {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.said.text = ok ? words(@"MBUIShareTaken", @"OK") : words(@"MBUIShareFailed", @"—");
    self.done.enabled = YES;
  });
}

// What is shared, into the inbox: its words (an item's text, a link's address after them, a title), its files (each
// attachment that is neither, by its own name); share.json last, so the app never takes half of one.
- (void)take {
  NSString *group = words(@"MBUIAppGroup", @"");
  NSURL *box = group.length ? [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group] : nil;
  if (!box) {
    NSLog(@"share: no container for the app group %@", group);
    [self told:NO];
    return;
  }
  NSString *stamp = [NSString stringWithFormat:@"%.0f-%u", NSDate.date.timeIntervalSince1970 * 1000, arc4random()];
  NSURL *dir = [[box URLByAppendingPathComponent:@"share-inbox" isDirectory:YES] URLByAppendingPathComponent:stamp isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSMutableArray<NSString *> *texts = [NSMutableArray new];
  NSMutableArray<NSDictionary *> *files = [NSMutableArray new];
  __block NSString *title = @"";
  int order = 0;
  dispatch_group_t g = dispatch_group_create();
  NSObject *lock = [NSObject new];
  for (NSExtensionItem *item in self.extensionContext.inputItems) {
    if (item.attributedContentText.string.length) [texts addObject:item.attributedContentText.string];
    if (item.attributedTitle.string.length) title = item.attributedTitle.string;
    for (NSItemProvider *p in item.attachments) {
      int n = order++;
      dispatch_group_enter(g);
      if ([p hasItemConformingToTypeIdentifier:UTTypeURL.identifier] &&
          ![p hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier]) {
        [p loadObjectOfClass:NSURL.class completionHandler:^(NSURL *u, NSError *e) {
          @synchronized(lock) {
            // (a link the words already say, once)
            if (u.absoluteString.length && ![[texts componentsJoinedByString:@"\n"] containsString:u.absoluteString])
              [texts addObject:u.absoluteString];
          }
          dispatch_group_leave(g);
        }];
      } else if ([p hasItemConformingToTypeIdentifier:UTTypePlainText.identifier] &&
                 ![p hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier]) {
        [p loadObjectOfClass:NSString.class completionHandler:^(NSString *s, NSError *e) {
          @synchronized(lock) {
            if (s.length) [texts addObject:s];
          }
          dispatch_group_leave(g);
        }];
      } else {
        // a file: the provider's own copy of it, by the type it says first (a picture as the library keeps it, a
        // PDF, any document)
        NSString *type = p.registeredTypeIdentifiers.firstObject ?: UTTypeData.identifier;
        [p loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *e) {
          if (url) {
            UTType *t = [UTType typeWithIdentifier:type];
            NSString *otherwise = [@"file" stringByAppendingPathExtension:t.preferredFilenameExtension ?: @"bin"];
            NSString *name = safe_name(p.suggestedName.length ? p.suggestedName : url.lastPathComponent, otherwise);
            if (!name.pathExtension.length && t.preferredFilenameExtension) name = [name stringByAppendingPathExtension:t.preferredFilenameExtension];
            NSString *mime = t.preferredMIMEType ?: @"";
            NSURL *to = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%d-%@", n, name]];
            NSError *ce = nil;
            BOOL ok;
            NSString *jpeg = [name.stringByDeletingPathExtension stringByAppendingPathExtension:@"jpg"];
            NSURL *as = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%d-%@", n, jpeg]];
            if (heic_as_jpeg(url, as)) {
              ok = YES, name = jpeg, mime = @"image/jpeg", to = as;
            } else {
              ok = [NSFileManager.defaultManager copyItemAtURL:url toURL:to error:&ce];
            }
            if (ok) {
              @synchronized(lock) {
                [files addObject:@{@"name" : name, @"type" : mime, @"path" : to.lastPathComponent, @"n" : @(n)}];
              }
            } else {
              NSLog(@"share: %@ not kept: %@", name, ce);
            }
          }
          dispatch_group_leave(g);
        }];
      }
    }
  }
  dispatch_group_notify(g, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *text = [texts componentsJoinedByString:@"\n"];
    if (!text.length && !files.count) {
      [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
      [self told:NO];
      return;
    }
    // (in the order they were shared, not the order they were read)
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"n"] compare:b[@"n"]]; }];
    NSMutableDictionary *said = [@{@"text" : text, @"files" : files} mutableCopy];
    if (title.length && ![title isEqualToString:text]) said[@"title"] = title;
    NSData *json = [NSJSONSerialization dataWithJSONObject:said options:0 error:nil];
    BOOL ok = json && [json writeToURL:[dir URLByAppendingPathComponent:@"share.json"] atomically:YES];
    NSLog(@"share: kept %lu characters, %lu files in %@", (unsigned long)text.length, (unsigned long)files.count, stamp);
    [self told:ok];
  });
}

@end
