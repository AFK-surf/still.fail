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
#import <ImageIO/ImageIO.h>
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

@class MBSiteHandler;

// One request of a site's page (kind 3): its scheme task, answered by the app.
@interface MBSiteReq : NSObject
@property(nonatomic) int32_t rid;
@property(nonatomic, strong) id<WKURLSchemeTask> task;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, strong) NSData *body;
@property(nonatomic) BOOL headed, gone;
@end
@implementation MBSiteReq
@end

@interface MBNative : NSObject <WKNavigationDelegate>
@property(nonatomic) int32_t vid, kind;
@property(nonatomic, strong) PView *box;      // clips: at the clip rect
@property(nonatomic, strong) PView *content;  // in it: at the view's rect
@property(nonatomic) double x, y, w, h, cx0, cy0, cx1, cy1, radius;
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
// its frames' times (ms, comma between: nil not read yet) and a frame grabbed (PNG; stillState 1 grabbing, 2 here,
// -1 failed)
@property(nonatomic, copy) NSString *frames;
@property(nonatomic) BOOL framesAsked;
@property(nonatomic, strong) NSData *still;
@property(nonatomic) int stillState;
// a page's
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic) BOOL loaded;
@property(nonatomic) int htmlLen;
@property(nonatomic, strong) PImage *snap;
@property(nonatomic) BOOL snapping;  // a picture of it being taken (refreshSnap)
@property(nonatomic) BOOL told;      // its readiness told to the app (mb_host_outside)
// a site's
@property(nonatomic, strong) MBSiteHandler *handler;
@property(nonatomic, strong) NSMutableArray<NSString *> *said;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, MBSiteReq *> *reqs;
@property(nonatomic) int32_t nextReq;
@property(nonatomic) double scale;
// a page's and a site's: the scripts the app sent (view_tell 1), waiting for the page there (loaded, or said something
// since it started); who takes a finger on it (view_tell 2: "all", "through", "pinch", "vertical") and the slop; how
// long a site's request waits for its head before the app is told (view_tell 3)
@property(nonatomic, strong) NSMutableArray<NSString *> *scripts;
@property(nonatomic) BOOL there;
@property(nonatomic, copy) NSString *touchMode;
@property(nonatomic) double slop;
@property(nonatomic) double headWaitMs;
- (void)say:(NSDictionary *)event;
- (void)runScripts;
- (void)grabPage;
- (void)advance:(MBLoad *)l;
- (void)drop:(MBLoad *)l;
- (void)end:(MBLoad *)l error:(BOOL)err;
- (void)logState;
- (void)refreshSnap;
@end

static NSMutableDictionary<NSNumber *, MBNative *> *views;
// a site's own scheme: nothing else answers it
static NSString *const kSiteScheme = @"stillfail-preview";
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
// The video track's frames' times (its samples' presentation times, through a sample cursor: the index only), on a
// queue of its own; said once read.
- (void)readFrames {
  if (self.framesAsked) return;
  self.framesAsked = YES;
  if (@available(macOS 12.0, iOS 16.0, *)) {
    AVAsset *asset = self.item.asset;
    __weak MBNative *wv = self;
    int32_t vid = self.vid;
    [asset loadTracksWithMediaType:AVMediaTypeVideo
                 completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
                   NSMutableArray<NSNumber *> *times = [NSMutableArray new];
                   AVAssetTrack *track = tracks.firstObject;
                   {
                     if (track.canProvideSampleCursors) {
                       AVSampleCursor *cur = [track makeSampleCursorAtFirstSampleInDecodeOrder];
                       while (cur) {
                         CMTime t = cur.presentationTimeStamp;
                         if (CMTIME_IS_NUMERIC(t)) [times addObject:@(CMTimeGetSeconds(t) * 1000.0)];
                         if ([cur stepInDecodeOrderByCount:1] != 1) break;
                       }
                     }
                   }
                   [times sortUsingSelector:@selector(compare:)];
                   NSMutableArray<NSString *> *words = [NSMutableArray new];
                   for (NSNumber *n in times) [words addObject:[NSString stringWithFormat:@"%.3f", n.doubleValue]];
                   NSString *joined = [words componentsJoinedByString:@","];
                   dispatch_async(dispatch_get_main_queue(), ^{
                     vlog(@"view %d: %lu frames read%@", vid, (unsigned long)times.count,
                          error ? [@": " stringByAppendingString:error.localizedDescription] : @"");
                     if (wv) wv.frames = joined;
                     mb_host_request_frame();
                   });
                 }];
  } else {
    self.frames = @"";
  }
}

// The frame showing at `ms` at its own size, the closest (no tolerance), as a PNG.
- (void)grabAt:(double)ms {
  if (@available(macOS 13.0, iOS 16.0, *)) {
    self.stillState = 1;
    self.still = nil;
    AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.item.asset];
    g.appliesPreferredTrackTransform = YES;
    g.requestedTimeToleranceBefore = kCMTimeZero;
    g.requestedTimeToleranceAfter = kCMTimeZero;
    __weak MBNative *wv = self;
    int32_t vid = self.vid;
    [g generateCGImageAsynchronouslyForTime:CMTimeMake((int64_t)llround(ms), 1000)
                          completionHandler:^(CGImageRef img, CMTime actual, NSError *error) {
                            NSMutableData *png = nil;
                            if (img) {
                              png = [NSMutableData new];
                              CGImageDestinationRef dst =
                                  CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
                              if (dst) {
                                CGImageDestinationAddImage(dst, img, NULL);
                                if (!CGImageDestinationFinalize(dst)) png = nil;
                                CFRelease(dst);
                              } else {
                                png = nil;
                              }
                            }
                            dispatch_async(dispatch_get_main_queue(), ^{
                              vlog(@"view %d: frame at %.0f ms %@", vid, ms,
                                   png ? [NSString stringWithFormat:@"grabbed (%lu bytes)", (unsigned long)png.length]
                                       : [@"not grabbed: " stringByAppendingString:error.localizedDescription ?: @"?"]);
                              if (wv) {
                                wv.still = png;
                                wv.stillState = png ? 2 : -1;
                              }
                              mb_host_outside(MB_OUTSIDE_GRAB, vid, png ? 1 : -1);
                              mb_host_request_frame();
                            });
                          }];
  } else {
    self.stillState = -1;
  }
}


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
  // the player waits on the app's bytes now: not the host's work until they come (apple.h's mb_host_outside, 0)
  mb_host_outside(MB_OUTSIDE_VIEW, self.vid, 0);
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
    [self tell:-1];
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
    // a player is ready for the app once its first frame can be shown (a video), or once it can play at all with
    // no picture to show (a sound: its presentation size 0 × 0); or it failed
    BOOL can = self.item.status == AVPlayerItemStatusReadyToPlay;
    CGSize ps = self.item.presentationSize;
    if (self.playerLayer.readyForDisplay || (can && ps.width == 0 && ps.height == 0)) [self tell:1];
    else if (self.failed) [self tell:-1];
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
  [self.player removeObserver:self forKeyPath:@"timeControlStatus" context:kStatus];
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
  if (self.kind == 3) {
    // a site: its own scheme, and any frame in it; a link elsewhere is said to the app, not followed
    NSString *sc = a.request.URL.scheme;
    BOOL main = a.targetFrame == nil || a.targetFrame.isMainFrame;
    BOOL mine = [sc isEqualToString:kSiteScheme] || [sc isEqualToString:@"about"];
    if (!mine && main && ![sc isEqualToString:@"data"] && ![sc isEqualToString:@"blob"] &&
        ![sc isEqualToString:@"javascript"] && a.request.URL.absoluteString)
      [self say:@{@"leave" : a.request.URL.absoluteString}];
    decide(mine || !main ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
    return;
  }
  // only the page given (about:blank, and its frames' about:srcdoc): no link followed, nothing else loaded
  BOOL ok = [a.request.URL.scheme isEqualToString:@"about"];
  if (!ok) vlog(@"view %d: navigation to %@ cancelled", self.vid, a.request.URL.absoluteString);
  decide(ok ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)say:(NSDictionary *)event {
  NSData *d = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
  if (!d) return;
  [self.said addObject:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]];
  mb_host_request_frame();
}

- (void)webView:(WKWebView *)wv didStartProvisionalNavigation:(WKNavigation *)n {
  mb_host_request_frame();
}

// A new document: scripts wait for it.
- (void)webView:(WKWebView *)wv didCommitNavigation:(WKNavigation *)n {
  self.there = NO;
}

- (void)runScripts {
  if (!self.there || !self.web || self.closed) return;
  for (NSString *js in self.scripts) [self.web evaluateJavaScript:js completionHandler:nil];
  [self.scripts removeAllObjects];
}

// What its page shows now, at its view's size in device pixels, as a PNG (`still`), told as a grab is.
- (void)grabPage {
  self.stillState = 1;
  self.still = nil;
  if (!self.web || self.w <= 0 || self.h <= 0) {
    self.stillState = -1;
    mb_host_outside(MB_OUTSIDE_GRAB, self.vid, -1);
    return;
  }
  __weak MBNative *me = self;
  [self.web takeSnapshotWithConfiguration:nil
                        completionHandler:^(PImage *img, NSError *e) {
                          MBNative *v = me;
                          if (!v) return;
#if TARGET_OS_OSX
                          CGImageRef cg = [img CGImageForProposedRect:NULL context:nil hints:nil];
#else
                          CGImageRef cg = img.CGImage;
#endif
                          NSMutableData *png = [NSMutableData new];
                          CGImageDestinationRef d =
                              cg ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL) : NULL;
                          if (d) {
                            CGImageDestinationAddImage(d, cg, NULL);
                            if (!CGImageDestinationFinalize(d)) png = nil;
                            CFRelease(d);
                          }
                          if (d && png.length) {
                            v.still = png;
                            v.stillState = 2;
                            vlog(@"view %d: page grabbed (%lu bytes)", v.vid, (unsigned long)png.length);
                          } else {
                            v.stillState = -1;
                            vlog(@"view %d: page not grabbed: %@", v.vid, e.localizedDescription);
                          }
                          mb_host_outside(MB_OUTSIDE_GRAB, v.vid, v.stillState == 2 ? 1 : -1);
                        }];
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)n {
  self.there = YES;
  [self runScripts];
  if (self.kind == 3) {
    [self refreshSnap];
    mb_host_request_frame();
    if (!self.loaded) vlog(@"view %d: site page loaded (%@)", self.vid, wv.URL.path);
  }
  if (self.kind == 3) [self tell:1];
  if (self.closed || self.loaded) return;
  self.loaded = YES;
  vlog(@"view %d: page loaded", self.vid);
  // ready for the app (its picture for snapshots is the host's own business: mb_views_snap_all, at a snapshot)
  [self tell:1];
  [self refreshSnap];
  mb_host_request_frame();
}

// Its readiness told to the app (apple.h's mb_host_outside: kind 2), as it comes: ready (a page loaded and its picture
// taken, a player's first frame), or failed.
- (void)tell:(int)state {
  if (self.told && state > 0) return;
  self.told = state > 0;
  mb_host_outside(MB_OUTSIDE_VIEW, self.vid, state);
}

- (void)pageFailed:(NSError *)e {
  if (self.loaded || self.closed) return;
  self.failed = YES;
  [self tell:-1];
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
  self.snapping = YES;
  [self.web takeSnapshotWithConfiguration:nil
                        completionHandler:^(PImage *img, NSError *e) {
                          if (img) me.snap = img;
                          me.snapping = NO;
                          mb_host_request_frame();
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
  // playing, waiting for what it needs, paused: a frame as that changes (the app draws a playing one's time; one that
  // waits moves on its own no more until this says so)
  [v.player addObserver:v forKeyPath:@"timeControlStatus" options:0 context:kStatus];
  v.observing = YES;
  vlog(@"view %d: open video (%@, %@)", vid, mime, v.uti);
  return v;
}

// What a page's scripts say to the app (`mbuiHost.post(text)`, in the page and its frames): said as `{"said":…}`,
// and the page there for the scripts that wait. (A handler the controller keeps, the view by a weak reference.)
@interface MBPageSays : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) MBNative *view;
@end
@implementation MBPageSays
- (void)userContentController:(WKUserContentController *)uc didReceiveScriptMessage:(WKScriptMessage *)m {
  MBNative *v = self.view;
  if (!v || v.closed || ![m.body isKindOfClass:NSString.class]) return;
  [v say:@{@"said" : m.body}];
  v.there = YES;
  [v runScripts];
}
@end

// The page's way to the app, first in every frame of it.
static NSString *const kHostScript =
    @"window.mbuiHost={post:function(t){window.webkit.messageHandlers.mbui.postMessage(String(t))}};";

// A page's configuration, its scripts able to speak to the app.
static WKWebViewConfiguration *page_config(MBNative *v) {
  WKWebViewConfiguration *c = [WKWebViewConfiguration new];
  MBPageSays *h = [MBPageSays new];
  h.view = v;
  [c.userContentController addScriptMessageHandler:h name:@"mbui"];
  [c.userContentController addUserScript:[[WKUserScript alloc] initWithSource:kHostScript
                                                                injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                             forMainFrameOnly:NO]];
  v.scripts = [NSMutableArray new];
  v.said = [NSMutableArray new];
  v.touchMode = @"all";
  v.headWaitMs = 60000;
  return c;
}

static MBNative *open_web(int32_t vid, NSString *html) {
  MBNative *v = [MBNative new];
  WKWebViewConfiguration *c = page_config(v);
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

// ---- a site (kind 3): its own scheme's requests answered by the app ----

@interface MBSiteHandler : NSObject <WKURLSchemeHandler>
@property(nonatomic, weak) MBNative *view;
@end

@implementation MBSiteHandler
- (void)webView:(WKWebView *)wv startURLSchemeTask:(id<WKURLSchemeTask>)task {
  MBNative *v = self.view;
  if (!v || v.closed) {
    [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
    return;
  }
  NSURLRequest *r = task.request;
  MBSiteReq *q = [MBSiteReq new];
  q.rid = ++v.nextReq;
  q.task = task;
  q.url = r.URL;
  NSData *body = r.HTTPBody;
  if (!body && r.HTTPBodyStream) {
    NSMutableData *all = [NSMutableData new];
    NSInputStream *in = r.HTTPBodyStream;
    [in open];
    uint8_t buf[16384];
    NSInteger n;
    while ((n = [in read:buf maxLength:sizeof buf]) > 0) [all appendBytes:buf length:(NSUInteger)n];
    [in close];
    body = all;
  }
  q.body = body ?: [NSData data];
  v.reqs[@(q.rid)] = q;
  NSURLComponents *c = [NSURLComponents componentsWithURL:r.URL resolvingAgainstBaseURL:NO];
  NSString *path = c.percentEncodedPath.length ? c.percentEncodedPath : @"/";
  if (c.percentEncodedQuery) path = [NSString stringWithFormat:@"%@?%@", path, c.percentEncodedQuery];
  NSMutableArray *hs = [NSMutableArray new];
  BOOL page = r.mainDocumentURL && [r.mainDocumentURL isEqual:r.URL];
  [r.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *val, BOOL *stop) {
    [hs addObject:@[ k, val ]];
  }];
  NSString *accept = [r valueForHTTPHeaderField:@"Accept"];
  if ([accept hasPrefix:@"text/html"]) page = YES;
  [v say:@{@"req" : @(q.rid), @"method" : r.HTTPMethod ?: @"GET", @"path" : path, @"headers" : hs, @"page" : @(page)}];
  // the site waits on the app's answer now (apple.h's mb_host_outside, 0)
  mb_host_outside(MB_OUTSIDE_VIEW, v.vid, 0);
  // no head after headWaitMs: the app told (it answers it), the request still waiting
  __weak MBNative *wv2 = v;
  __weak MBSiteReq *wq = q;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(v.headWaitMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
    MBNative *vv = wv2;
    MBSiteReq *qq = wq;
    if (vv && qq && !vv.closed && !qq.headed && !qq.gone && vv.reqs[@(qq.rid)] == qq) [vv say:@{@"late" : @(qq.rid)}];
  });
}

- (void)webView:(WKWebView *)wv stopURLSchemeTask:(id<WKURLSchemeTask>)task {
  MBNative *v = self.view;
  for (NSNumber *k in v.reqs.allKeys) {
    MBSiteReq *q = v.reqs[k];
    if (q.task != task) continue;
    q.gone = YES;
    [v.reqs removeObjectForKey:k];
    [v say:@{@"gone" : k}];
  }
}
@end

static MBNative *open_site(int32_t vid, NSString *start) {
  MBNative *v = [MBNative new];
  WKWebViewConfiguration *c = page_config(v);
  v.reqs = [NSMutableDictionary new];
  v.scale = 1;
  v.handler = [MBSiteHandler new];
  v.handler.view = v;
  c.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
  c.defaultWebpagePreferences.allowsContentJavaScript = YES;
  [c setURLSchemeHandler:v.handler forURLScheme:kSiteScheme];
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
  NSString *s = start.length ? start : @"/";
  [wv loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://svc%@", kSiteScheme, s]]]];
  vlog(@"view %d: open site at %@", vid, s);
  return v;
}

int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  if (kind < 1 || kind > 3) return 0;
  if (!views) views = [NSMutableDictionary new];
  int32_t vid = ++next_vid;
  NSString *a = mb_ns_from_string(arg);
  MBNative *v = kind == 1 ? open_video(vid, a) : kind == 2 ? open_web(vid, a) : open_site(vid, a);
  v.vid = vid;
  v.kind = kind;
  v.box = new_box();
  [v.box addSubview:v.content];
  v.box.hidden = YES;
  views[@(vid)] = v;
  return vid;
}

void mb_host_view_place(int32_t vid, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, double radius, int32_t shown) {
  MBNative *v = views[@(vid)];
  if (!v) return;
  BOOL s = shown != 0;
  if (v.placed && v.shown == s && v.x == x && v.y == y && v.w == w && v.h == h && v.cx0 == cx0 && v.cy0 == cy0 &&
      v.cx1 == cx1 && v.cy1 == cy1 && v.radius == radius)
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
  // its corners round (as the hole the app paints for it): its own layer cut to them, what it holds with it
  if (radius > 0 || v.radius > 0) {
#if TARGET_OS_OSX
    v.content.wantsLayer = YES;
#endif
    v.content.layer.cornerRadius = fmax(0, radius);
    v.content.layer.masksToBounds = radius > 0;
  }
  v.radius = radius;
  [CATransaction commit];
  // where it is now, in device pixels: its content and its clip (scripts/host_contract.sh HOST views compares it with
  // what the app told: VIEWTOLD)
  if (s) {
#if TARGET_OS_OSX
    double px = views_root.window ? views_root.window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor;
#else
    double px = UIScreen.mainScreen.scale;
#endif
    CGRect b = v.box.frame, c = v.content.frame;
    vlog(@"VIEWAT %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", vid, (b.origin.x + c.origin.x) * px,
         (b.origin.y + c.origin.y) * px, c.size.width * px, c.size.height * px, b.origin.x * px, b.origin.y * px,
         (b.origin.x + b.size.width) * px, (b.origin.y + b.size.height) * px, v.content.layer.cornerRadius * px);
  }
  if (resized && v.kind >= 2) [v refreshSnap];
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
    for (MBSiteReq *q in v.reqs.allValues) q.gone = YES;
    [v.reqs removeAllObjects];
    vlog(@"view %d: closed", vid);
  }
  [v.box removeFromSuperview];
}

void mb_host_view_control(int32_t vid, int32_t op, double value) {
  MBNative *v = views[@(vid)];
  if (v && v.kind >= 2 && op == 21) {
    [v grabPage];
    return;
  }
  if (v && v.kind == 3) {
    switch (op) {
      case 5: if (v.web.canGoBack) [v.web goBack]; break;
      case 6: if (v.web.canGoForward) [v.web goForward]; break;
      case 7: [v.web reload]; break;
      case 8:
        // laid out at its rect over the scale (CSS pixels the bigger), drawn at the scale
        if (value > 0) {
          v.scale = value;
          if (@available(macOS 11.0, iOS 14.0, *)) v.web.pageZoom = value;
        }
        break;
    }
    return;
  }
  if (!v || v.kind != 1) return;
  switch (op) {
    case 1: {
      // played again from its end: from the start, as the Android host's player does
      double dur = [v durationMs];
      CMTime t = v.player.currentTime;
      if (dur > 0 && CMTIME_IS_NUMERIC(t) && CMTimeGetSeconds(t) * 1000.0 >= dur - 50) [v.player seekToTime:kCMTimeZero];
      [v.player play];
      if (v.speed != 1) v.player.rate = (float)v.speed;
      break;
    }
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
    case 20: [v readFrames]; break;
    case 21: [v grabAt:value]; break;
  }
}

// A video's frames' times and a frame grabbed (native.mbt `frames`, `grabbed`).
moonbit_string_t mb_host_view_text(int32_t vid, int32_t what) {
  MBNative *v = views[@(vid)];
  if (v && v.kind >= 2 && what == 2) return mb_string_from_ns([NSString stringWithFormat:@"%d", v.stillState]);
  if (!v || v.kind != 1) return moonbit_make_string_raw(0);
  return mb_string_from_ns(what == 1 ? (v.frames ?: @"") : [NSString stringWithFormat:@"%d", v.stillState]);
}

int32_t mb_host_view_text_known(int32_t vid, int32_t what) {
  MBNative *v = views[@(vid)];
  if (v && v.kind >= 2 && what == 2) return 1;
  if (!v || v.kind != 1) return 0;
  return what == 1 ? (v.frames != nil) : 1;
}

moonbit_bytes_t mb_host_view_still(int32_t vid) {
  MBNative *v = views[@(vid)];
  NSData *d = v.still ?: [NSData data];
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)d.length, 0);
  memcpy(out, d.bytes, d.length);
  v.still = nil;
  if (v.stillState == 2) v.stillState = 0;
  return out;
}

int32_t mb_host_view_info(int32_t vid, double *out) {
  for (int i = 0; i < 10; i++) out[i] = 0;
  out[0] = -1;
  MBNative *v = views[@(vid)];
  if (!v) return -1;
  if (v.kind == 3) {
    out[6] = v.loaded ? 1 : 0;
    return v.failed ? -1 : v.loaded ? 1 : 0;
  }
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
  // how far on it has what it needs: the end of the loaded range the playhead is in
  double now = out[1];
  for (NSValue *r in it.loadedTimeRanges) {
    CMTimeRange tr = r.CMTimeRangeValue;
    double a = CMTimeGetSeconds(tr.start) * 1000.0, b = CMTimeGetSeconds(CMTimeRangeGetEnd(tr)) * 1000.0;
    if (a <= now + 1 && b > out[8]) out[8] = b;
  }
  // at its end and stopped there
  out[9] = (v.player.rate == 0 && out[0] > 0 && out[1] >= out[0] - 50) ? 1 : 0;
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

// ---- a site's API ----

moonbit_string_t mb_host_view_site_next(int32_t vid) {
  MBNative *v = views[@(vid)];
  if (!v || v.kind < 2 || v.said.count == 0) return mb_string_from_ns(@"");
  NSString *e = v.said.firstObject;
  [v.said removeObjectAtIndex:0];
  return mb_string_from_ns(e);
}

moonbit_bytes_t mb_host_view_site_body(int32_t vid, int32_t req) {
  MBNative *v = views[@(vid)];
  NSData *d = v.reqs[@(req)].body;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)d.length, 0);
  if (d.length) memcpy(out, d.bytes, d.length);
  return out;
}

void mb_host_view_site_head(int32_t vid, int32_t req, int32_t status, moonbit_string_t headers) {
  MBNative *v = views[@(vid)];
  MBSiteReq *q = v.reqs[@(req)];
  if (!q || q.gone || q.headed) return;
  q.headed = YES;
  NSData *d = [mb_ns_from_string(headers) dataUsingEncoding:NSUTF8StringEncoding];
  NSArray *a = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
  NSMutableDictionary *hs = [NSMutableDictionary new];
  for (NSArray *h in [a isKindOfClass:NSArray.class] ? a : @[]) {
    if (h.count != 2) continue;
    NSString *k = h[0], *val = h[1];
    hs[k] = hs[k] ? [NSString stringWithFormat:@"%@, %@", hs[k], val] : val;
  }
  NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:q.url statusCode:status HTTPVersion:@"HTTP/1.1"
                                                   headerFields:hs];
  [q.task didReceiveResponse:r];
}

void mb_host_view_site_chunk(int32_t vid, int32_t req, moonbit_bytes_t data) {
  MBNative *v = views[@(vid)];
  MBSiteReq *q = v.reqs[@(req)];
  if (!q || q.gone || !q.headed) return;
  [q.task didReceiveData:[NSData dataWithBytes:data length:Moonbit_array_length(data)]];
}

void mb_host_view_site_end(int32_t vid, int32_t req, moonbit_string_t error) {
  MBNative *v = views[@(vid)];
  MBSiteReq *q = v.reqs[@(req)];
  if (!q) return;
  [v.reqs removeObjectForKey:@(req)];
  if (q.gone) return;
  NSString *e = mb_ns_from_string(error);
  if (e.length == 0 && q.headed) {
    [q.task didFinish];
  } else if (!q.headed) {
    // no head: a page that says why, as the Android host's
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:q.url statusCode:502 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{@"Content-Type" : @"text/plain; charset=utf-8"}];
    [q.task didReceiveResponse:r];
    [q.task didReceiveData:[(e.length ? e : @"no answer") dataUsingEncoding:NSUTF8StringEncoding]];
    [q.task didFinish];
  } else {
    [q.task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost
                                             userInfo:@{NSLocalizedDescriptionKey : e}]];
  }
}

moonbit_string_t mb_host_view_site_state(int32_t vid) {
  MBNative *v = views[@(vid)];
  if (!v || v.kind != 3) return mb_string_from_ns(@"");
  NSURL *u = v.web.URL;
  NSString *path = @"";
  if ([u.scheme isEqualToString:kSiteScheme]) {
    NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
    path = c.percentEncodedPath.length ? c.percentEncodedPath : @"/";
    if (c.percentEncodedQuery) path = [NSString stringWithFormat:@"%@?%@", path, c.percentEncodedQuery];
  } else if (u.absoluteString) {
    path = u.absoluteString;
  }
  NSDictionary *st = @{
    @"path" : path,
    @"back" : @(v.web.canGoBack),
    @"forward" : @(v.web.canGoForward),
    @"loading" : @(v.web.isLoading),
    @"title" : v.web.title ?: @""
  };
  NSData *d = [NSJSONSerialization dataWithJSONObject:st options:0 error:nil];
  return mb_string_from_ns(d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"");
}

void mb_host_view_site_load(int32_t vid, moonbit_string_t path) {
  MBNative *v = views[@(vid)];
  if (!v || v.kind != 3) return;
  NSString *p = mb_ns_from_string(path);
  NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"%@://svc%@", kSiteScheme, p.length ? p : @"/"]];
  if (u) [v.web loadRequest:[NSURLRequest requestWithURL:u]];
}

// ---- for the canvas's view and the renderer ----

// What the app tells a view beyond its controls (host_native.mbt view_tell): a script for its page, who takes a
// finger on it, a site's settings.
void mb_host_view_tell(int32_t vid, int32_t what, moonbit_string_t text) {
  MBNative *v = views[@(vid)];
  if (!v || v.kind < 2) return;
  NSString *t = mb_ns_from_string(text);
  if (what == 1) {
    [v.scripts addObject:t];
    [v runScripts];
  } else if (what == 2) {
    NSArray<NSString *> *p = [t componentsSeparatedByString:@" "];
    v.touchMode = p.firstObject ?: @"all";
    v.slop = p.count > 1 ? p[1].doubleValue : 0;
  } else if (what == 3) {
    NSDictionary *o = [NSJSONSerialization JSONObjectWithData:[t dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([o isKindOfClass:NSDictionary.class] && [o[@"head_wait_ms"] isKindOfClass:NSNumber.class])
      v.headWaitMs = [o[@"head_wait_ms"] doubleValue];
  }
}

// The page's view a point is on (shown, placed), or nil.
static MBNative *page_at(double x, double y) {
  for (MBNative *v in views.allValues) {
    if (v.kind < 2 || !v.shown || !v.placed) continue;
    double x0 = fmax(v.cx0, v.x), y0 = fmax(v.cy0, v.y);
    double x1 = fmin(v.cx1, v.x + v.w), y1 = fmin(v.cy1, v.y + v.h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return v;
  }
  return nil;
}

// Who takes a finger (or the mouse) at a point over a page: its mode ("all", "through", "pinch", "vertical") and its
// slop, or NULL where no page is.
const char *mb_views_touch_at(double x, double y, double *slop) {
  MBNative *v = page_at(x, y);
  if (!v) return NULL;
  if (slop) *slop = v.slop;
  return (v.touchMode ?: @"all").UTF8String;
}

int mb_views_pass_through(double x, double y) {
  for (MBNative *v in views.allValues) {
    if (v.kind < 2 || !v.shown || !v.placed) continue;
    // (a page that takes no finger: the canvas's)
    if ([v.touchMode isEqualToString:@"through"]) continue;
    double x0 = fmax(v.cx0, v.x), y0 = fmax(v.cy0, v.y);
    double x1 = fmin(v.cx1, v.x + v.w), y1 = fmin(v.cy1, v.y + v.h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return 1;
  }
  return 0;
}

int mb_views_count(void) { return (int)views.count; }

// Whether a page's picture for snapshots is being taken (apple.h).
int mb_views_snapping(void) {
  for (MBNative *v in views.allValues)
    if (v.snapping && !v.closed) return 1;
  return 0;
}

// A snapshot is about to be taken: every page loaded and placed has its picture taken anew (apple.h).
void mb_views_snap_all(void) {
  for (MBNative *v in views.allValues)
    if (v.kind >= 2 && !v.closed && v.loaded) [v refreshSnap];
}

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

// Marks drawn onto an image (marks.mbt), as still.fail's Android app's ImageMarks.kt draws them: decoded by ImageIO,
// drawn in a bitmap context of its size (flipped: the marks' y down), round-capped strokes, a box's rounded corners,
// an arrow's barbs, a hand-drawn line through its midpoints, words edged in their halo (Core Text), the numbered
// marks' pins; PNG out. On a queue of its own; each job's state 0 drawing, 1 made, -1 failed.

@interface MBMarksJob : NSObject
@property(nonatomic) int state;
@property(nonatomic, strong) NSData *png;
@end
@implementation MBMarksJob
@end

static NSMutableDictionary<NSNumber *, MBMarksJob *> *mark_jobs;
static int32_t next_mark_job = 1;

static CGColorRef mk_color(NSDictionary *m, NSString *k) {
  NSNumber *n = m[k];
  uint32_t c = n ? (uint32_t)n.unsignedLongLongValue : 0xE5704AFF;
  CGFloat comps[4] = {((c >> 24) & 0xFF) / 255.0, ((c >> 16) & 0xFF) / 255.0, ((c >> 8) & 0xFF) / 255.0, (c & 0xFF) / 255.0};
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGColorRef out = CGColorCreate(cs, comps);
  CGColorSpaceRelease(cs);
  return out;
}

static void mk_text(CGContextRef ctx, NSString *text, double size, double weight, CGColorRef color, double x, double base,
                    double stroke, BOOL centred) {
  CTFontRef font = mb_platform_font(size, (int)weight, 0);
  NSDictionary *attrs = @{
    (__bridge NSString *)kCTFontAttributeName : (__bridge id)font,
    (__bridge NSString *)kCTForegroundColorAttributeName : (__bridge id)color,
    (__bridge NSString *)kCTStrokeColorAttributeName : (__bridge id)color,
    (__bridge NSString *)kCTStrokeWidthAttributeName : @(stroke > 0 ? stroke / size * 100.0 : 0),
  };
  NSAttributedString *a = [[NSAttributedString alloc] initWithString:text attributes:attrs];
  CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)a);
  double w = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
  CGContextSaveGState(ctx);
  // (Core Text draws with y up: undo the context's flip about the baseline)
  CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
  CGContextTranslateCTM(ctx, centred ? x - w / 2 : x, base);
  CGContextScaleCTM(ctx, 1, -1);
  CGContextSetLineJoin(ctx, kCGLineJoinRound);
  CGContextSetTextPosition(ctx, 0, 0);
  CTLineDraw(line, ctx);
  CGContextRestoreGState(ctx);
  CFRelease(line);
  CFRelease(font);
}

static void mk_pin_path(CGContextRef ctx, double x, double y, double size, double inset, double r, double point) {
  double l = x + inset, t = y + inset, rr = x + size - inset, b = y + size - inset;
  CGContextBeginPath(ctx);
  CGContextMoveToPoint(ctx, l + r, t);
  CGContextAddArcToPoint(ctx, rr, t, rr, b, r);
  CGContextAddArcToPoint(ctx, rr, b, l, b, r);
  CGContextAddArcToPoint(ctx, l, b, l, t, point);
  CGContextAddArcToPoint(ctx, l, t, rr, t, r);
  CGContextClosePath(ctx);
}

static NSData *mk_draw(NSData *image, NSDictionary *v) {
  CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)image, NULL);
  if (!src) return nil;
  NSDictionary *opts = @{(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform : @YES,
                         (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
                         (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize : @(1 << 15)};
  CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
  CFRelease(src);
  if (!img) return nil;
  size_t W = CGImageGetWidth(img), H = CGImageGetHeight(img);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(cs);
  if (!ctx) {
    CGImageRelease(img);
    return nil;
  }
  CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), img);
  CGImageRelease(img);
  // y down, in the marks' own size
  double nw = [v[@"w"] doubleValue] ?: W, nh = [v[@"h"] doubleValue] ?: H;
  CGContextTranslateCTM(ctx, 0, H);
  CGContextScaleCTM(ctx, W / nw, -(H / nh));
  CGContextSetLineCap(ctx, kCGLineCapRound);
  CGContextSetLineJoin(ctx, kCGLineJoinRound);
  NSArray *marks = v[@"marks"];
  for (NSDictionary *m in marks) {
    NSString *kind = m[@"kind"];
    double w = [m[@"w"] doubleValue];
    NSArray<NSNumber *> *p = m[@"pts"];
    CGColorRef color = mk_color(m, @"color"), halo = mk_color(m, @"halo");
    if ([kind isEqualToString:@"words"] && p.count >= 2) {
      NSString *text = m[@"text"] ?: @"";
      double base = p[1].doubleValue + w * 0.98;
      mk_text(ctx, text, w, 600, halo, p[0].doubleValue, base, w * 0.22, NO);
      mk_text(ctx, text, w, 600, color, p[0].doubleValue, base, 0, NO);
    } else if (p.count >= 2) {
      CGContextSetStrokeColorWithColor(ctx, color);
      CGContextSetLineWidth(ctx, w);
      CGContextBeginPath(ctx);
      if ([kind isEqualToString:@"box"] && p.count >= 4) {
        double ax = p[0].doubleValue, ay = p[1].doubleValue, bx = p[2].doubleValue, by = p[3].doubleValue;
        CGRect r = CGRectMake(MIN(ax, bx), MIN(ay, by), fabs(bx - ax), fabs(by - ay));
        double rad = MIN(w * 1.5, MIN(r.size.width / 2, r.size.height / 2));
        CGPathRef path = CGPathCreateWithRoundedRect(r, rad, rad, NULL);
        CGContextAddPath(ctx, path);
        CGPathRelease(path);
      } else if ([kind isEqualToString:@"arrow"] && p.count >= 4) {
        double ax = p[0].doubleValue, ay = p[1].doubleValue, bx = p[2].doubleValue, by = p[3].doubleValue;
        double dx = bx - ax, dy = by - ay, len = hypot(dx, dy);
        if (len <= 0) len = 1;
        double ux = dx / len, uy = dy / len, size = MIN(w * 5, len * 0.6), spread = 0.5;
        double backX = bx - ux * size, backY = by - uy * size;
        CGContextMoveToPoint(ctx, ax, ay);
        CGContextAddLineToPoint(ctx, bx, by);
        CGContextMoveToPoint(ctx, backX - uy * size * spread, backY + ux * size * spread);
        CGContextAddLineToPoint(ctx, bx, by);
        CGContextAddLineToPoint(ctx, backX + uy * size * spread, backY - ux * size * spread);
      } else {
        NSUInteger n = p.count / 2;
        CGContextMoveToPoint(ctx, p[0].doubleValue, p[1].doubleValue);
        if (n < 3) {
          for (NSUInteger k = 1; k < n; k++) CGContextAddLineToPoint(ctx, p[2 * k].doubleValue, p[2 * k + 1].doubleValue);
        } else {
          for (NSUInteger k = 1; k < n - 1; k++) {
            double x = p[2 * k].doubleValue, y = p[2 * k + 1].doubleValue;
            double nx = p[2 * k + 2].doubleValue, ny = p[2 * k + 3].doubleValue;
            CGContextAddQuadCurveToPoint(ctx, x, y, (x + nx) / 2, (y + ny) / 2);
          }
          CGContextAddLineToPoint(ctx, p[2 * n - 2].doubleValue, p[2 * n - 1].doubleValue);
        }
      }
      CGContextStrokePath(ctx);
    }
    CGColorRelease(color);
    CGColorRelease(halo);
  }
  // the numbered marks' pins, over them all
  for (NSDictionary *m in marks) {
    int n = [m[@"n"] intValue];
    NSArray<NSNumber *> *p = m[@"pts"];
    if (n <= 0 || p.count < 2) continue;
    double k = [m[@"w"] doubleValue] / 3.0;
    double px = p[0].doubleValue, py = p[1].doubleValue;
    if ([m[@"kind"] isEqualToString:@"box"] && p.count >= 4) {
      px = MIN(px, p[2].doubleValue);
      py = MIN(py, p[3].doubleValue);
    }
    px = MAX(2 * k, MIN(MAX(2 * k, nw - 22 * k), px));
    py = MAX(22 * k, MIN(MAX(22 * k, nh - 2 * k), py));
    double x = px - 2 * k, y = py - 22 * k, size = 24 * k;
    CGColorRef color = mk_color(m, @"color"), halo = mk_color(m, @"halo");
    CGContextSaveGState(ctx);
    CGColorRef shadow = mk_color(@{@"c" : @(0x00000038)}, @"c");
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -2 * k), 3 * k, shadow);
    CGColorRelease(shadow);
    CGContextSetFillColorWithColor(ctx, halo);
    mk_pin_path(ctx, x, y, size, 0, 12 * k, 3 * k);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);
    CGContextSetFillColorWithColor(ctx, color);
    mk_pin_path(ctx, x, y, size, 2 * k, 10 * k, 1.5 * k);
    CGContextFillPath(ctx);
    mk_text(ctx, [NSString stringWithFormat:@"%d", n], 11 * k, 650, halo, x + size / 2, y + size / 2 + 11 * k * 0.36, 0, YES);
    CGColorRelease(color);
    CGColorRelease(halo);
  }
  CGImageRef out = CGBitmapContextCreateImage(ctx);
  CGContextRelease(ctx);
  if (!out) return nil;
  NSMutableData *png = [NSMutableData new];
  CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
  BOOL ok = NO;
  if (dst) {
    CGImageDestinationAddImage(dst, out, NULL);
    ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
  }
  CGImageRelease(out);
  return ok ? png : nil;
}

int32_t mb_host_marks_start(moonbit_bytes_t image, moonbit_string_t marks) {
  if (!mark_jobs) mark_jobs = [NSMutableDictionary new];
  int32_t jid = next_mark_job++;
  MBMarksJob *j = [MBMarksJob new];
  mark_jobs[@(jid)] = j;
  NSData *img = [NSData dataWithBytes:image length:Moonbit_array_length(image)];
  NSData *json = [mb_ns_from_string(marks) dataUsingEncoding:NSUTF8StringEncoding];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSDictionary *v = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    NSData *png = [v isKindOfClass:NSDictionary.class] ? mk_draw(img, v) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      vlog(@"marks: %@", png ? [NSString stringWithFormat:@"drawn (%lu bytes)", (unsigned long)png.length] : @"not drawn");
      j.png = png;
      j.state = png ? 1 : -1;
      mb_host_outside(MB_OUTSIDE_MARKS, jid, j.state);
      mb_host_request_frame();
    });
  });
  return jid;
}

int32_t mb_host_marks_state(int32_t jid) {
  MBMarksJob *j = mark_jobs[@(jid)];
  return j ? j.state : -1;
}

moonbit_bytes_t mb_host_marks_png(int32_t jid) {
  MBMarksJob *j = mark_jobs[@(jid)];
  NSData *d = j.png ?: [NSData data];
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)d.length, 0);
  memcpy(out, d.bytes, d.length);
  [mark_jobs removeObjectForKey:@(jid)];
  return out;
}

// Text in a legacy encoding (charset.mbt): the encoding CoreFoundation names by IANA's name, its bytes decoded (a
// byte with no mapping: U+FFFD, through a lossy conversion where the strict one refuses).
static CFStringEncoding cs_of(moonbit_string_t charset) {
  NSString *n = mb_ns_from_string(charset);
  if (!n.length) return kCFStringEncodingInvalidId;
  return CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)n);
}

int32_t mb_host_charset_known(moonbit_string_t charset) {
  CFStringEncoding e = cs_of(charset);
  return e != kCFStringEncodingInvalidId && CFStringIsEncodingAvailable(e) ? 1 : 0;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  CFStringEncoding e = cs_of(charset);
  NSData *d = [NSData dataWithBytesNoCopy:data length:Moonbit_array_length(data) freeWhenDone:NO];
  NSStringEncoding ns = CFStringConvertEncodingToNSStringEncoding(e);
  NSString *s = [[NSString alloc] initWithData:d encoding:ns];
  if (!s) {
    // a few bytes it cannot map (a corrupt file, a character of a newer standard): the rest as it is
    NSString *out = nil;
    BOOL lossy = NO;
    [NSString stringEncodingForData:d
                    encodingOptions:@{
                      NSStringEncodingDetectionSuggestedEncodingsKey : @[ @(ns) ],
                      NSStringEncodingDetectionUseOnlySuggestedEncodingsKey : @YES,
                      NSStringEncodingDetectionAllowLossyKey : @YES
                    }
                    convertedString:&out
                usedLossyConversion:&lossy];
    s = out;
  }
  return mb_string_from_ns(s ?: @"");
}

// a file name of the app's made safe for a folder: its last part, no separators, never empty
static NSString *keep_safe(NSString *n) {
  n = [[n.lastPathComponent stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
      stringByReplacingOccurrencesOfString:@":"
                                withString:@"_"];
  if (n.length == 0 || [n isEqualToString:@"."] || [n isEqualToString:@".."]) n = @"file";
  return n;
}

// `d` written into `dir` as `n`, or `n (2)`… when taken: its path, nil when it could not be written
static NSString *keep_into(NSString *dir, NSString *n, NSData *d) {
  NSFileManager *fm = NSFileManager.defaultManager;
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
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
      return p;
    }
    if (![fm fileExistsAtPath:p]) {
      vlog(@"save %@ failed: %@", p, e.localizedDescription);
      return nil;
    }
  }
  return nil;
}

// where downloads go: MBUI_DOWNLOADS_DIR, else ~/Downloads (macOS) or the app's Documents (iOS)
static NSString *keep_downloads(void) {
  const char *over = getenv("MBUI_DOWNLOADS_DIR");
  if (over && *over) return @(over);
#if TARGET_OS_OSX
  NSSearchPathDirectory where = NSDownloadsDirectory;
#else
  NSSearchPathDirectory where = NSDocumentDirectory;
#endif
  return [NSFileManager.defaultManager URLsForDirectory:where inDomains:NSUserDomainMask].firstObject.path;
}

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  NSString *dir = keep_downloads();
  if (!dir) return 0;
  NSData *d = [NSData dataWithBytes:data length:Moonbit_array_length(data)];
  return keep_into(dir, keep_safe(mb_ns_from_string(name)), d) ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Files kept (keep.mbt): the bytes put into a part file of the temporary
// directory as they come, then, finished, moved to their place. macOS:
// Downloads, nothing asked, or a save panel over the window; iOS: the Files
// sheet either way (UIDocumentPickerViewController exporting a copy).
// MBUI_DOWNLOADS_DIR set (a scripted run), either way the file goes there and
// nothing is asked. All on the main thread but the moves, which go to a queue
// and come back.

@interface MBKeep : NSObject
@property(nonatomic) int32_t kid, way, state;  // state: 0 keeping, 1 kept, 2 called off, -1 failed
@property(nonatomic, copy) NSString *name, *where, *part;
@property(nonatomic, strong) NSFileHandle *out;
@end
@implementation MBKeep
@end

static NSMutableDictionary<NSNumber *, MBKeep *> *keeps;
static int32_t next_keep = 1;

static void keep_drop(MBKeep *k) {
  [k.out closeAndReturnError:nil];
  k.out = nil;
  if (k.part) [NSFileManager.defaultManager removeItemAtPath:k.part.stringByDeletingLastPathComponent error:nil];
}

static void keep_answer(MBKeep *k, int32_t state, NSString *where) {
  keep_drop(k);
  k.where = where ?: @"";
  k.state = state;
  mb_host_request_frame();
}

// the part file moved into `dir` as its name, or `name (2)`… when taken: the path, nil when it could not be
static NSString *keep_move_into(NSString *dir, MBKeep *k) {
  NSFileManager *fm = NSFileManager.defaultManager;
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *n = k.name, *base = n.stringByDeletingPathExtension, *ext = n.pathExtension;
  for (int i = 1; i < 10000; i++) {
    NSString *fn = i == 1         ? n
                   : ext.length ? [NSString stringWithFormat:@"%@ (%d).%@", base, i, ext]
                                : [NSString stringWithFormat:@"%@ (%d)", base, i];
    NSString *p = [dir stringByAppendingPathComponent:fn];
    if ([fm fileExistsAtPath:p]) continue;
    NSError *e = nil;
    // (a move across volumes is a copy: moveItemAtPath does it, never over a file there)
    if ([fm moveItemAtPath:k.part toPath:p error:&e]) {
      vlog(@"saved %@", p);
      return p;
    }
    if (![fm fileExistsAtPath:p]) {
      vlog(@"save %@ failed: %@", p, e.localizedDescription);
      return nil;
    }
  }
  return nil;
}

#if !TARGET_OS_OSX
@interface MBKeepSheet : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, strong) MBKeep *keep;
@end
static NSMutableSet *keep_sheets;
@implementation MBKeepSheet
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  vlog(@"keep: exported to %@", urls.firstObject.path);
  keep_answer(self.keep, 1, urls.firstObject.lastPathComponent ?: self.keep.name);
  [keep_sheets removeObject:self];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {
  keep_answer(self.keep, 2, nil);
  [keep_sheets removeObject:self];
}
@end

static UIViewController *keep_top(void) {
  UIWindow *w = nil;
  for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
    if ([sc isKindOfClass:UIWindowScene.class])
      for (UIWindow *x in ((UIWindowScene *)sc).windows)
        if (x.isKeyWindow || !w) w = x;
  UIViewController *vc = w.rootViewController;
  while (vc.presentedViewController) vc = vc.presentedViewController;
  return vc;
}
#endif

int32_t mb_host_keep_begin(moonbit_string_t name, moonbit_string_t mime, int32_t way) {
  (void)mime;
  if (!keeps) keeps = [NSMutableDictionary new];
  MBKeep *k = [MBKeep new];
  k.kid = next_keep++;
  k.way = way;
  k.name = keep_safe(mb_ns_from_string(name));
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                              [NSString stringWithFormat:@"mbui-keeping/%@", NSUUID.UUID.UUIDString]];
  NSFileManager *fm = NSFileManager.defaultManager;
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  k.part = [dir stringByAppendingPathComponent:k.name];
  if ([fm createFileAtPath:k.part contents:nil attributes:nil]) k.out = [NSFileHandle fileHandleForWritingAtPath:k.part];
  if (!k.out) {
    vlog(@"keep %@: no part file", k.name);
    k.state = -1;
  }
  keeps[@(k.kid)] = k;
  return k.kid;
}

int32_t mb_host_keep_append(int32_t kid, moonbit_bytes_t data) {
  MBKeep *k = keeps[@(kid)];
  if (!k || !k.out || k.state != 0) return 0;
  NSError *e = nil;
  NSData *d = [NSData dataWithBytesNoCopy:data length:Moonbit_array_length(data) freeWhenDone:NO];
  if (![k.out writeData:d error:&e]) {
    vlog(@"keep %@: %@", k.name, e.localizedDescription);
    keep_answer(k, -1, nil);
    return 0;
  }
  return 1;
}

void mb_host_keep_finish(int32_t kid) {
  MBKeep *k = keeps[@(kid)];
  if (!k || !k.out || k.state != 0) return;
  [k.out closeAndReturnError:nil];
  k.out = nil;
  const char *over = getenv("MBUI_DOWNLOADS_DIR");
  BOOL scripted = over && *over;
#if TARGET_OS_OSX
  if (k.way != 2 || scripted) {
    NSString *dir = keep_downloads();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSString *p = dir ? keep_move_into(dir, k) : nil;
      dispatch_async(dispatch_get_main_queue(), ^{ keep_answer(k, p ? 1 : -1, p); });
    });
    return;
  }
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.nameFieldStringValue = k.name;
  panel.canCreateDirectories = YES;
  NSString *dl = keep_downloads();
  if (dl) panel.directoryURL = [NSURL fileURLWithPath:dl isDirectory:YES];
  void (^done)(NSModalResponse) = ^(NSModalResponse r) {
    if (r != NSModalResponseOK || !panel.URL) {
      keep_answer(k, 2, nil);
      return;
    }
    NSURL *u = panel.URL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *e = nil;
      // the panel asked before a file of that name is replaced
      NSURL *got = nil;
      BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:u.path]
                    ? [NSFileManager.defaultManager replaceItemAtURL:u
                                                       withItemAtURL:[NSURL fileURLWithPath:k.part]
                                                      backupItemName:nil
                                                             options:0
                                                    resultingItemURL:&got
                                                               error:&e]
                    : [NSFileManager.defaultManager moveItemAtURL:[NSURL fileURLWithPath:k.part] toURL:u error:&e];
      if (ok) vlog(@"saved %@", u.path);
      else vlog(@"save %@ failed: %@", u.path, e.localizedDescription);
      dispatch_async(dispatch_get_main_queue(), ^{ keep_answer(k, ok ? 1 : -1, u.path); });
    });
  };
  NSWindow *w = NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
  if (w) [panel beginSheetModalForWindow:w completionHandler:done];
  else [panel beginWithCompletionHandler:done];
#else
  if (scripted) {
    NSString *p = keep_move_into(@(over), k);
    keep_answer(k, p ? 1 : -1, p);
    return;
  }
  UIViewController *top = keep_top();
  if (!top) {
    keep_answer(k, -1, nil);
    return;
  }
  MBKeepSheet *s = [MBKeepSheet new];
  s.keep = k;
  if (!keep_sheets) keep_sheets = [NSMutableSet new];
  [keep_sheets addObject:s];
  UIDocumentPickerViewController *c =
      [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ [NSURL fileURLWithPath:k.part] ] asCopy:YES];
  c.delegate = s;
  [top presentViewController:c animated:YES completion:nil];
#endif
}

int32_t mb_host_keep_state(int32_t kid) {
  MBKeep *k = keeps[@(kid)];
  return k ? k.state : -1;
}

moonbit_string_t mb_host_keep_where(int32_t kid) { return mb_string_from_ns(keeps[@(kid)].where ?: @""); }

void mb_host_keep_end(int32_t kid) {
  MBKeep *k = keeps[@(kid)];
  if (!k) return;
  // one whose bytes are still coming is called off; one being moved or asked about finishes on its own
  if (k.out) keep_drop(k);
  [keeps removeObjectForKey:@(kid)];
}
