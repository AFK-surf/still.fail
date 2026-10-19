// Native views over the canvas (host_native.mbt's view_*), for macOS and iOS:
// a video player (AVPlayer, its bytes read through the app) and a web page
// (WKWebView). They live in a view just under the canvas's (mb_views_root);
// the app paints a hole (kind 9: transparent, unblended) where one shows, and
// what it paints after the hole draws over it. Also files saved
// (mb_host_save_file).
//
// Threads: everything here runs on the main thread (the app's), except the
// resource loader's delegate, which runs on the view's own serial queue
// (lq); the loading requests are only touched there, the reads the app
// answers only on the main thread.
#import "apple.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <WebKit/WebKit.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
typedef NSView PView;
typedef NSImage PImage;
#else
#import <UIKit/UIKit.h>
typedef UIView PView;
typedef UIImage PImage;
#endif

void mb_host_request_frame(void);

// "view N: …" lines, on stdout on macOS (as mb_host_log), the system log on iOS
static void vlog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void vlog(NSString *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);
#if TARGET_OS_OSX
  fprintf(stdout, "%s\n", s.UTF8String);
  fflush(stdout);
#else
  NSLog(@"%@", s);
#endif
}

// a read's most bytes (a part of the core's)
static const long long kMaxRead = 4 << 20;

// ---------------------------------------------------------------------------
// Views of the platform: flipped on macOS (the app's coordinates are from the
// top left), a player's view whose own layer is the AVPlayerLayer (resized
// with it, never animated).

#if TARGET_OS_OSX
@interface MBFlipView : NSView
@end
@implementation MBFlipView
- (BOOL)isFlipped { return YES; }
@end

@interface MBPlayerView : MBFlipView
@end
@implementation MBPlayerView
- (instancetype)initWithFrame:(NSRect)f {
  self = [super initWithFrame:f];
  self.wantsLayer = YES;
  return self;
}
- (CALayer *)makeBackingLayer { return [AVPlayerLayer layer]; }
- (NSView *)hitTest:(NSPoint)p { return nil; }  // a video takes no input: the app's taps over it
@end
static PView *new_box(void) {
  MBFlipView *v = [[MBFlipView alloc] initWithFrame:NSZeroRect];
  v.wantsLayer = YES;
  v.layer.masksToBounds = YES;
  if (@available(macOS 14.0, *)) v.clipsToBounds = YES;
  return v;
}
static CGColorRef black_color(void) { return NSColor.blackColor.CGColor; }
#else
@interface MBPlayerView : UIView
@end
@implementation MBPlayerView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end
static PView *new_box(void) {
  UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
  v.clipsToBounds = YES;
  v.backgroundColor = nil;
  return v;
}
static CGColorRef black_color(void) { return UIColor.blackColor.CGColor; }
#endif

static PView *views_root;

id mb_views_root(CGRect frame) {
  if (views_root) return views_root;
#if TARGET_OS_OSX
  MBFlipView *v = [[MBFlipView alloc] initWithFrame:NSRectFromCGRect(frame)];
  v.wantsLayer = YES;
#else
  UIView *v = [[UIView alloc] initWithFrame:frame];
  v.backgroundColor = nil;
  v.opaque = NO;
#endif
  views_root = v;
  return v;
}

// ---------------------------------------------------------------------------
// Reads: what the player's loading requests wait on, asked of the app.

// One loading request of the player's: its range (of the main thread's), the
// request itself (touched on lq only).
@interface MBLoad : NSObject
@property(nonatomic, strong) AVAssetResourceLoadingRequest *req;  // lq's
@property(nonatomic) BOOL cancelled;                               // lq's
// the main thread's:
@property(nonatomic) long long next, end;  // the next offset it wants; its end (-1: the file's)
@property(nonatomic) BOOL hasData, wantsInfo, infoSent, gone;
@end
@implementation MBLoad
@end

@interface MBRead : NSObject
@property(nonatomic) int32_t rid;
@property(nonatomic) long long off, len;
@property(nonatomic, strong) MBLoad *load;
@end
@implementation MBRead
@end

@class MBNative;

@interface MBLoader : NSObject <AVAssetResourceLoaderDelegate>
@property(nonatomic, weak) MBNative *view;
@property(nonatomic, strong) NSMutableArray<MBLoad *> *loads;  // lq's
@end

// ---------------------------------------------------------------------------

@interface MBNative : NSObject <WKNavigationDelegate>
@property(nonatomic) int32_t vid, kind;
@property(nonatomic, strong) PView *box;      // clips: at the clip rect
@property(nonatomic, strong) PView *content;  // in it: at the view's rect
@property(nonatomic) double x, y, w, h, cx0, cy0, cx1, cy1;
@property(nonatomic) BOOL shown, placed, failed, closed;
// a player's
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) AVPlayerItemVideoOutput *output;
@property(nonatomic, strong) MBLoader *loader;
@property(nonatomic, strong) dispatch_queue_t lq;
@property(nonatomic, copy) NSString *uti;
@property(nonatomic) long long total;  // the file's size, -1 not known yet
@property(nonatomic) double answered;  // bytes given
@property(nonatomic) int nanswers;
@property(nonatomic) double logNext;  // the next count of bytes to log a read at
@property(nonatomic) int32_t nextRid;
@property(nonatomic) double speed;
@property(nonatomic) BOOL observing, readyLogged, frameLogged;
@property(nonatomic, strong) NSMutableArray<MBRead *> *pending;                  // not yet taken
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, MBRead *> *taken;  // taken, not answered
@property(nonatomic, strong) NSMutableArray<MBLoad *> *loads;
@property(nonatomic) CVPixelBufferRef lastFrame;
// a page's
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic) BOOL loaded;
@property(nonatomic) int htmlLen;
@property(nonatomic, strong) PImage *snap;
- (void)advance:(MBLoad *)l;
- (void)drop:(MBLoad *)l;
- (void)end:(MBLoad *)l error:(BOOL)err;
- (void)logState;
- (void)refreshSnap;
@end

static NSMutableDictionary<NSNumber *, MBNative *> *views;
static int32_t next_vid;
static void *kStatus = &kStatus, *kReady = &kReady;

static void fill_info(AVAssetResourceLoadingRequest *req, NSString *uti, long long total) {
  AVAssetResourceLoadingContentInformationRequest *ci = req.contentInformationRequest;
  if (!ci) return;
  ci.contentType = uti;
  if (total >= 0) ci.contentLength = total;
  ci.byteRangeAccessSupported = YES;
}

@implementation MBLoader

- (BOOL)resourceLoader:(AVAssetResourceLoader *)rl
    shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)req {
  MBLoad *l = [MBLoad new];
  l.req = req;
  if (!self.loads) self.loads = [NSMutableArray new];
  [self.loads addObject:l];
  AVAssetResourceLoadingDataRequest *dr = req.dataRequest;
  long long off = dr ? dr.currentOffset : 0;
  long long len = dr ? (long long)dr.requestedLength - (dr.currentOffset - dr.requestedOffset) : 0;
  BOOL toEnd = dr ? dr.requestsAllDataToEndOfResource : NO;
  BOOL info = req.contentInformationRequest != nil;
  BOOL data = dr != nil;
  __weak MBNative *wv = self.view;
  dispatch_async(dispatch_get_main_queue(), ^{
    MBNative *v = wv;
    if (!v || v.closed) return;
    l.next = off;
    l.end = toEnd ? -1 : off + len;
    l.hasData = data;
    l.wantsInfo = info;
    [v.loads addObject:l];
    [v advance:l];
  });
  return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)rl didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)req {
  MBLoad *l = nil;
  for (MBLoad *x in self.loads)
    if (x.req == req) l = x;
  if (!l) return;
  l.cancelled = YES;
  [self.loads removeObject:l];
  __weak MBNative *wv = self.view;
  dispatch_async(dispatch_get_main_queue(), ^{ [wv drop:l]; });
}

@end

@implementation MBNative

- (void)dealloc {
  if (_lastFrame) CVPixelBufferRelease(_lastFrame);
}

// ---- a player's reads ----

// The load's next read asked, or it finished (done, or only what the file is wanted, and known).
- (void)advance:(MBLoad *)l {
  if (l.gone) return;
  if (self.failed) {
    [self end:l error:YES];
    return;
  }
  if (l.wantsInfo && !l.infoSent && self.total >= 0) {
    l.infoSent = YES;
    NSString *uti = self.uti;
    long long total = self.total;
    dispatch_async(self.lq, ^{
      if (!l.cancelled) fill_info(l.req, uti, total);
    });
  }
  if (!l.hasData) {
    if (l.wantsInfo && !l.infoSent) [self ask:l off:0 len:2];  // what the file is: its size, from a small read
    else [self end:l error:NO];
    return;
  }
  long long end = l.end;
  if (self.total >= 0 && (end < 0 || end > self.total)) end = self.total;
  if (end >= 0 && l.next >= end) {
    [self end:l error:NO];
    return;
  }
  long long n = end >= 0 ? MIN(end - l.next, kMaxRead) : kMaxRead;
  [self ask:l off:l.next len:n];
}

- (void)ask:(MBLoad *)l off:(long long)off len:(long long)len {
  MBRead *r = [MBRead new];
  r.rid = ++self.nextRid;
  r.off = off;
  r.len = len;
  r.load = l;
  [self.pending addObject:r];
  mb_host_request_frame();
}

// The load finished: done, or failed (an error the player sees).
- (void)end:(MBLoad *)l error:(BOOL)err {
  if (l.gone) return;
  l.gone = YES;
  [self.loads removeObject:l];
  MBLoader *loader = self.loader;
  dispatch_async(self.lq, ^{
    if (!l.cancelled) {
      if (err)
        [l.req finishLoadingWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                          code:NSURLErrorCannotOpenFile
                                                      userInfo:nil]];
      else
        [l.req finishLoading];
    }
    [loader.loads removeObject:l];
  });
}

// The player gave the load up: its reads not asked any more, their answers dropped.
- (void)drop:(MBLoad *)l {
  l.gone = YES;
  [self.loads removeObject:l];
  NSMutableArray *keep = [NSMutableArray new];
  for (MBRead *r in self.pending)
    if (r.load != l) [keep addObject:r];
  self.pending = keep;
}

- (void)answer:(int32_t)rid data:(const uint8_t *)bytes length:(long long)n total:(double)total {
  MBRead *r = self.taken[@(rid)];
  if (!r) return;
  [self.taken removeObjectForKey:@(rid)];
  MBLoad *l = r.load;
  if (total == -2) {
    vlog(@"view %d: read at %lld failed", self.vid, r.off);
    self.failed = YES;
    for (MBLoad *x in [self.loads copy]) [self end:x error:YES];
    [self.pending removeAllObjects];
    return;
  }
  if (total >= 0) self.total = (long long)total;
  self.answered += n;
  self.nanswers++;
  if (self.nanswers <= 4 || self.answered >= self.logNext) {
    vlog(@"view %d: read at %lld: %lld bytes (%.0f in all, of %lld)", self.vid, r.off, n, self.answered,
         self.total);
    while (self.logNext <= self.answered) self.logNext += kMaxRead;
  }
  if (l.gone) return;
  if (!l.hasData) {
    if (self.total < 0) {
      vlog(@"view %d: the file's size not told", self.vid);
      [self end:l error:YES];
      return;
    }
    [self advance:l];
    return;
  }
  if (n == 0) {  // the file's end: none before it (else the load fails, not asked again forever)
    if (self.total < 0) self.total = l.next;
    if (self.total > l.next) {
      vlog(@"view %d: no bytes at %lld, before the end (%lld)", self.vid, l.next, self.total);
      [self end:l error:YES];
      return;
    }
    [self advance:l];
    return;
  }
  long long end = l.end >= 0 ? l.end : LLONG_MAX;
  if (self.total >= 0 && end > self.total) end = self.total;
  long long skip = l.next - r.off;  // answered from where it was asked: l.next
  if (skip < 0 || skip >= n) {
    [self advance:l];
    return;
  }
  long long give = MIN(n - skip, end - l.next);
  if (give <= 0) {
    [self advance:l];
    return;
  }
  NSData *d = [NSData dataWithBytes:bytes + skip length:(NSUInteger)give];
  l.next += give;
  BOOL info = l.wantsInfo && !l.infoSent && self.total >= 0;
  if (info) l.infoSent = YES;
  NSString *uti = self.uti;
  long long tot = self.total;
  dispatch_async(self.lq, ^{
    if (l.cancelled) return;
    if (info) fill_info(l.req, uti, tot);
    [l.req.dataRequest respondWithData:d];
  });
  [self advance:l];
}

// ---- a player's state ----

- (void)observeValueForKeyPath:(NSString *)path
                      ofObject:(id)o
                        change:(NSDictionary *)change
                       context:(void *)ctx {
  if (ctx != kStatus && ctx != kReady) {
    [super observeValueForKeyPath:path ofObject:o change:change context:ctx];
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.closed) return;
    [self logState];
    mb_host_request_frame();
  });
}

- (void)logState {
  if (self.item.status == AVPlayerItemStatusReadyToPlay && !self.readyLogged) {
    self.readyLogged = YES;
    CGSize s = self.item.presentationSize;
    vlog(@"view %d: ready, %.0f ms, %.0fx%.0f", self.vid, [self durationMs], s.width, s.height);
  }
  if (self.item.status == AVPlayerItemStatusFailed && !self.failed) {
    self.failed = YES;
    vlog(@"view %d: failed: %@", self.vid, self.item.error.localizedDescription);
  }
  if (self.playerLayer.readyForDisplay && !self.frameLogged) {
    self.frameLogged = YES;
    vlog(@"view %d: first frame shown", self.vid);
  }
}

- (double)durationMs {
  CMTime d = self.item.duration;
  if (!CMTIME_IS_NUMERIC(d)) return -1;
  return CMTimeGetSeconds(d) * 1000.0;
}

- (void)stopObserving {
  if (!self.observing) return;
  self.observing = NO;
  [self.item removeObserver:self forKeyPath:@"status" context:kStatus];
  [self.playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:kReady];
}

// The frame showing now, for snapshots (the last one copied when no new one came); retained, or NULL.
- (CGImageRef)copyFrame {
  CMTime t = self.item.currentTime;
  CVPixelBufferRef pb = [self.output copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
  if (pb) {
    if (self.lastFrame) CVPixelBufferRelease(self.lastFrame);
    self.lastFrame = pb;
  }
  pb = self.lastFrame;
  if (!pb) return NULL;
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef c = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), w, h, 8, CVPixelBufferGetBytesPerRow(pb),
                                         cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
  CGImageRef img = c ? CGBitmapContextCreateImage(c) : NULL;
  if (c) CGContextRelease(c);
  CGColorSpaceRelease(cs);
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  return img;
}

// ---- a page's ----

- (void)webView:(WKWebView *)wv
    decidePolicyForNavigationAction:(WKNavigationAction *)a
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decide {
  // only the page given (about:blank, and its frames' about:srcdoc): no link followed, nothing else loaded
  BOOL ok = [a.request.URL.scheme isEqualToString:@"about"];
  if (!ok) vlog(@"view %d: navigation to %@ cancelled", self.vid, a.request.URL.absoluteString);
  decide(ok ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)n {
  if (self.closed || self.loaded) return;
  self.loaded = YES;
  vlog(@"view %d: page loaded", self.vid);
  [self refreshSnap];
  mb_host_request_frame();
}

- (void)pageFailed:(NSError *)e {
  if (self.loaded || self.closed) return;
  self.failed = YES;
  vlog(@"view %d: page failed: %@", self.vid, e.localizedDescription);
  mb_host_request_frame();
}
- (void)webView:(WKWebView *)wv didFailNavigation:(WKNavigation *)n withError:(NSError *)e {
  [self pageFailed:e];
}
- (void)webView:(WKWebView *)wv didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)e {
  [self pageFailed:e];
}

// The page's picture for snapshots (taking one is asynchronous: the latest kept).
- (void)refreshSnap {
  if (!self.loaded || self.w <= 0 || self.h <= 0) return;
  __weak MBNative *me = self;
  [self.web takeSnapshotWithConfiguration:nil
                        completionHandler:^(PImage *img, NSError *e) {
                          if (img) me.snap = img;
                        }];
}

- (CGImageRef)copySnap {
  if (!self.snap) return NULL;
#if TARGET_OS_OSX
  CGImageRef c = [self.snap CGImageForProposedRect:NULL context:nil hints:nil];
#else
  CGImageRef c = self.snap.CGImage;
#endif
  return c ? CGImageRetain(c) : NULL;
}

@end

// ---------------------------------------------------------------------------
// The host API MoonBit calls

static NSString *uti_for(NSString *mime, NSString **ext) {
  NSString *m = [[mime componentsSeparatedByString:@";"].firstObject
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
  NSDictionary<NSString *, NSArray *> *map = @{
    @"video/mp4" : @[ AVFileTypeMPEG4, @"mp4" ],
    @"video/quicktime" : @[ AVFileTypeQuickTimeMovie, @"mov" ],
    @"video/x-m4v" : @[ AVFileTypeAppleM4V, @"m4v" ],
    @"video/3gpp" : @[ AVFileType3GPP, @"3gp" ],
    @"video/3gpp2" : @[ AVFileType3GPP2, @"3g2" ],
    @"audio/mp4" : @[ AVFileTypeAppleM4A, @"m4a" ],
    @"audio/m4a" : @[ AVFileTypeAppleM4A, @"m4a" ],
    @"audio/x-m4a" : @[ AVFileTypeAppleM4A, @"m4a" ],
    @"audio/mpeg" : @[ AVFileTypeMPEGLayer3, @"mp3" ],
    @"audio/mp3" : @[ AVFileTypeMPEGLayer3, @"mp3" ],
    @"audio/aac" : @[ @"public.aac-audio", @"aac" ],
    @"audio/wav" : @[ AVFileTypeWAVE, @"wav" ],
    @"audio/x-wav" : @[ AVFileTypeWAVE, @"wav" ],
    @"audio/wave" : @[ AVFileTypeWAVE, @"wav" ],
    @"audio/aiff" : @[ AVFileTypeAIFF, @"aiff" ],
    @"audio/x-aiff" : @[ AVFileTypeAIFF, @"aiff" ],
    @"audio/flac" : @[ @"org.xiph.flac", @"flac" ],
  };
  NSArray *e = map[m] ?: @[ AVFileTypeMPEG4, @"mp4" ];
  *ext = e[1];
  return e[0];
}

static MBNative *open_video(int32_t vid, NSString *mime) {
  MBNative *v = [MBNative new];
  NSString *ext;
  v.uti = uti_for(mime, &ext);
  v.total = -1;
  v.speed = 1;
  v.logNext = kMaxRead;
  v.pending = [NSMutableArray new];
  v.taken = [NSMutableDictionary new];
  v.loads = [NSMutableArray new];
  v.lq = dispatch_queue_create("mbui.view.loader", DISPATCH_QUEUE_SERIAL);
  v.loader = [MBLoader new];
  v.loader.view = v;
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"mbview://%d/file.%@", vid, ext]];
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
  [asset.resourceLoader setDelegate:v.loader queue:v.lq];
  v.item = [AVPlayerItem playerItemWithAsset:asset];
  v.output = [[AVPlayerItemVideoOutput alloc]
      initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)}];
  [v.item addOutput:v.output];
  v.player = [AVPlayer playerWithPlayerItem:v.item];
  v.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
  MBPlayerView *pv = [[MBPlayerView alloc] initWithFrame:CGRectZero];
#if TARGET_OS_IOS
  pv.userInteractionEnabled = NO;
#endif
  v.playerLayer = (AVPlayerLayer *)pv.layer;
  v.playerLayer.player = v.player;
  v.playerLayer.videoGravity = AVLayerVideoGravityResize;  // the app gives the picture's own rect
  v.playerLayer.backgroundColor = black_color();
  v.content = pv;
  [v.item addObserver:v forKeyPath:@"status" options:0 context:kStatus];
  [v.playerLayer addObserver:v forKeyPath:@"readyForDisplay" options:0 context:kReady];
  v.observing = YES;
  vlog(@"view %d: open video (%@, %@)", vid, mime, v.uti);
  return v;
}

static MBNative *open_web(int32_t vid, NSString *html) {
  MBNative *v = [MBNative new];
  WKWebViewConfiguration *c = [WKWebViewConfiguration new];
  c.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
  c.defaultWebpagePreferences.allowsContentJavaScript = YES;
#if TARGET_OS_IOS
  c.allowsInlineMediaPlayback = YES;
#endif
  WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectZero configuration:c];
  wv.navigationDelegate = v;
#if TARGET_OS_OSX
  if (@available(macOS 12.0, *)) wv.underPageBackgroundColor = NSColor.whiteColor;
#else
  wv.opaque = YES;
  wv.backgroundColor = UIColor.whiteColor;
  wv.scrollView.backgroundColor = UIColor.whiteColor;
#endif
  v.web = wv;
  v.content = wv;
  v.htmlLen = (int)[html lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  [wv loadHTMLString:html baseURL:nil];
  vlog(@"view %d: open web page (%d bytes)", vid, v.htmlLen);
  return v;
}

int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  if (kind != 1 && kind != 2) return 0;
  if (!views) views = [NSMutableDictionary new];
  int32_t vid = ++next_vid;
  NSString *a = mb_ns_from_string(arg);
  MBNative *v = kind == 1 ? open_video(vid, a) : open_web(vid, a);
  v.vid = vid;
  v.kind = kind;
  v.box = new_box();
  [v.box addSubview:v.content];
  v.box.hidden = YES;
  views[@(vid)] = v;
  return vid;
}

void mb_host_view_place(int32_t vid, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, int32_t shown) {
  MBNative *v = views[@(vid)];
  if (!v) return;
  BOOL s = shown != 0;
  if (v.placed && v.shown == s && v.x == x && v.y == y && v.w == w && v.h == h && v.cx0 == cx0 && v.cy0 == cy0 &&
      v.cx1 == cx1 && v.cy1 == cy1)
    return;
  BOOL resized = !v.placed || v.w != w || v.h != h;
  v.placed = YES;
  v.shown = s;
  v.x = x; v.y = y; v.w = w; v.h = h;
  v.cx0 = cx0; v.cy0 = cy0; v.cx1 = cx1; v.cy1 = cy1;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (!v.box.superview && views_root) [views_root addSubview:v.box];
  v.box.hidden = !s;
  v.box.frame = CGRectMake(cx0, cy0, fmax(0, cx1 - cx0), fmax(0, cy1 - cy0));
  v.content.frame = CGRectMake(x - cx0, y - cy0, fmax(0, w), fmax(0, h));
  [CATransaction commit];
  if (resized && v.kind == 2) [v refreshSnap];
}

void mb_host_view_close(int32_t vid) {
  MBNative *v = views[@(vid)];
  if (!v) return;
  [views removeObjectForKey:@(vid)];
  v.closed = YES;
  if (v.kind == 1) {
    [v stopObserving];
    [v.player pause];
    for (MBLoad *l in [v.loads copy]) [v end:l error:YES];
    [v.pending removeAllObjects];
    [v.taken removeAllObjects];
    [v.player replaceCurrentItemWithPlayerItem:nil];
    v.playerLayer.player = nil;
    vlog(@"view %d: closed (%.0f bytes read)", vid, v.answered);
  } else {
    [v.web stopLoading];
    v.web.navigationDelegate = nil;
    vlog(@"view %d: closed", vid);
  }
  [v.box removeFromSuperview];
}

void mb_host_view_control(int32_t vid, int32_t op, double value) {
  MBNative *v = views[@(vid)];
  if (!v || v.kind != 1) return;
  switch (op) {
    case 1:
      [v.player play];
      if (v.speed != 1) v.player.rate = (float)v.speed;
      break;
    case 2: [v.player pause]; break;
    case 3: {
      __weak MBNative *wv = v;
      [v.player seekToTime:CMTimeMake((int64_t)llround(value), 1000)
           toleranceBefore:kCMTimeZero
            toleranceAfter:kCMTimeZero
         completionHandler:^(BOOL done) {
           dispatch_async(dispatch_get_main_queue(), ^{
             if (wv) mb_host_request_frame();
           });
         }];
      break;
    }
    case 4:
      if (value <= 0) break;
      v.speed = value;
      if (v.player.rate > 0) v.player.rate = (float)value;
      break;
  }
}

int32_t mb_host_view_info(int32_t vid, double *out) {
  for (int i = 0; i < 8; i++) out[i] = 0;
  out[0] = -1;
  MBNative *v = views[@(vid)];
  if (!v) return -1;
  if (v.kind == 2) {
    out[5] = v.htmlLen;
    out[6] = v.loaded ? 1 : 0;
    return v.failed ? -1 : v.loaded ? 1 : 0;
  }
  [v logState];
  AVPlayerItem *it = v.item;
  out[0] = [v durationMs];
  CMTime t = v.player.currentTime;
  out[1] = CMTIME_IS_NUMERIC(t) ? CMTimeGetSeconds(t) * 1000.0 : 0;
  out[2] = v.player.rate > 0 ? 1 : 0;
  CGSize s = it.presentationSize;
  out[3] = s.width;
  out[4] = s.height;
  out[5] = v.answered;
  out[6] = v.playerLayer.readyForDisplay ? 1 : 0;
  BOOL waiting = v.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
  out[7] = (waiting || (v.player.rate > 0 && !it.playbackLikelyToKeepUp)) ? 1 : 0;
  if (v.failed || it.status == AVPlayerItemStatusFailed) return -1;
  return it.status == AVPlayerItemStatusReadyToPlay ? 1 : 0;
}

int32_t mb_host_view_read_next(int32_t vid, double *out) {
  MBNative *v = views[@(vid)];
  while (v.pending.count) {
    MBRead *r = v.pending.firstObject;
    [v.pending removeObjectAtIndex:0];
    if (r.load.gone) continue;
    v.taken[@(r.rid)] = r;
    out[0] = (double)r.off;
    out[1] = (double)r.len;
    return r.rid;
  }
  return 0;
}

void mb_host_view_read_answer(int32_t vid, int32_t req, moonbit_bytes_t data, double total) {
  MBNative *v = views[@(vid)];
  if (!v) return;
  [v answer:req data:(const uint8_t *)data length:Moonbit_array_length(data) total:total];
}

// ---- for the canvas's view and the renderer ----

int mb_views_pass_through(double x, double y) {
  for (MBNative *v in views.allValues) {
    if (v.kind != 2 || !v.shown || !v.placed) continue;
    double x0 = fmax(v.cx0, v.x), y0 = fmax(v.cy0, v.y);
    double x1 = fmin(v.cx1, v.x + v.w), y1 = fmin(v.cy1, v.y + v.h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return 1;
  }
  return 0;
}

int mb_views_count(void) { return (int)views.count; }

void mb_views_draw_under(CGContextRef ctx, double scale) {
  size_t H = CGBitmapContextGetHeight(ctx);
  NSArray *ids = [views.allKeys sortedArrayUsingSelector:@selector(compare:)];  // as they are stacked
  for (NSNumber *k in ids) {
    MBNative *v = views[k];
    if (!v.shown || !v.placed || v.w <= 0 || v.h <= 0) continue;
    CGContextSaveGState(ctx);
    // the app's coordinates: points from the top left
    CGContextTranslateCTM(ctx, 0, H);
    CGContextScaleCTM(ctx, scale, -scale);
    CGContextClipToRect(ctx, CGRectMake(v.cx0, v.cy0, fmax(0, v.cx1 - v.cx0), fmax(0, v.cy1 - v.cy0)));
    CGRect r = CGRectMake(v.x, v.y, v.w, v.h);
    if (v.kind == 1) CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    else CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, r);
    CGImageRef img = v.kind == 1 ? [v copyFrame] : [v copySnap];
    if (img) {
      // upright in its rect
      CGContextTranslateCTM(ctx, r.origin.x, r.origin.y + r.size.height);
      CGContextScaleCTM(ctx, 1, -1);
      CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
      CGContextDrawImage(ctx, CGRectMake(0, 0, r.size.width, r.size.height), img);
      CGImageRelease(img);
    }
    CGContextRestoreGState(ctx);
  }
}

// ---------------------------------------------------------------------------
// Files saved (host_native.mbt's save_file): macOS into ~/Downloads, iOS into
// the app's Documents (MBUI_DOWNLOADS_DIR instead, for tests); a name taken
// gets " (2)", " (3)"… before its extension.

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  NSString *n = mb_ns_from_string(name).lastPathComponent;
  n = [[n stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":"
                                                                                               withString:@"_"];
  if (n.length == 0 || [n isEqualToString:@"."] || [n isEqualToString:@".."]) n = @"file";
  NSFileManager *fm = NSFileManager.defaultManager;
  const char *over = getenv("MBUI_DOWNLOADS_DIR");
#if TARGET_OS_OSX
  NSSearchPathDirectory where = NSDownloadsDirectory;
#else
  NSSearchPathDirectory where = NSDocumentDirectory;
#endif
  NSString *dir = over && *over ? @(over) : [fm URLsForDirectory:where inDomains:NSUserDomainMask].firstObject.path;
  if (!dir) return 0;
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSData *d = [NSData dataWithBytes:data length:Moonbit_array_length(data)];
  NSString *base = n.stringByDeletingPathExtension, *ext = n.pathExtension;
  for (int i = 1; i < 10000; i++) {
    NSString *fn = i == 1         ? n
                   : ext.length ? [NSString stringWithFormat:@"%@ (%d).%@", base, i, ext]
                                : [NSString stringWithFormat:@"%@ (%d)", base, i];
    NSString *p = [dir stringByAppendingPathComponent:fn];
    if ([fm fileExistsAtPath:p]) continue;
    NSError *e = nil;
    if ([d writeToFile:p options:NSDataWritingWithoutOverwriting error:&e]) {
      vlog(@"saved %@ (%lu bytes)", p, (unsigned long)d.length);
      return 1;
    }
    if (![fm fileExistsAtPath:p]) {
      vlog(@"save %@ failed: %@", p, e.localizedDescription);
      return 0;
    }
  }
  return 0;
}
