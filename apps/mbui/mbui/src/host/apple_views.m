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
#import <objc/message.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
typedef NSView PView;
typedef NSImage PImage;
#else
#import <Photos/Photos.h>
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
// How much past where it is must have come for it to play on (ms): a stretch, not the next frame alone, so playing
// on a slow network goes on for a while each time rather than a frame at a time.
static const double kPlayAhead = 1000;

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

// A stream's (kind 4): its own layer what its frames are put on (their IOSurfaces: apple_stream.m).
@interface MBStreamView : MBFlipView
@end
@implementation MBStreamView
- (instancetype)initWithFrame:(NSRect)f {
  self = [super initWithFrame:f];
  self.wantsLayer = YES;
  // (its layer's contents the stream's, never drawn by the view)
  self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
  return self;
}
- (NSView *)hitTest:(NSPoint)p { return nil; }  // a picture takes no input: the app's gestures over it
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
@interface MBStreamView : UIView
@end
@implementation MBStreamView
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
@property(nonatomic) long long got;  // its bytes answered so far (it is answered as they come)
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
@property(nonatomic) double x, y, w, h, cx0, cy0, cx1, cy1;
@property(nonatomic) double r0, r1, r2, r3;  // its corners (top left, then round it)
@property(nonatomic) BOOL shown, placed, failed, closed;
// where it is stacked: over those of a lower z (opened later, or raised later: view_tell 5)
@property(nonatomic) int64_t z;
// a player's
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) AVPlayerItemVideoOutput *output;
// a stream's (kind 4): the stream whose frames its layer shows
@property(nonatomic) int32_t streamSid;
@property(nonatomic, strong) MBLoader *loader;
@property(nonatomic, strong) dispatch_queue_t lq;
@property(nonatomic, copy) NSString *uti;
@property(nonatomic) long long total;  // the file's size, -1 not known yet
@property(nonatomic) double answered;  // bytes given
@property(nonatomic) int nanswers;
@property(nonatomic) double logNext;  // the next count of bytes to log a read at
@property(nonatomic) int32_t nextRid;
@property(nonatomic) double speed;
// a seek on its way (to seekMs), and the one asked meanwhile to go to once it is done (chaseMs), if any
@property(nonatomic) BOOL seeking, chasing;
@property(nonatomic) int seekGen;  // the seek on its way (one let go of for another: not this one's completion)
@property(nonatomic) double seekMs, chaseMs;
@property(nonatomic) BOOL chaseNear;  // the one asked meanwhile is to go about there (seekTo:near:)
@property(nonatomic) BOOL observing, readyLogged, frameLogged;
@property(nonatomic, strong) NSMutableArray<MBRead *> *pending;                  // not yet taken
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, MBRead *> *taken;  // taken, not answered to its end
@property(nonatomic, strong) NSMutableArray<NSNumber *> *lettingGo;  // taken, then let go of: not told yet
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
// how it stands (mb_host_view_info) as the app was last told (stood); a player's clock's observer (stood as it plays)
@property(nonatomic) BOOL stoodTold;
@property(nonatomic) int32_t stoodState;
@property(nonatomic, strong) id ticks;
// a site's
@property(nonatomic, strong) MBSiteHandler *handler;
@property(nonatomic, strong) NSMutableArray<NSString *> *said;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, MBSiteReq *> *reqs;
@property(nonatomic) int32_t nextReq;
@property(nonatomic) double scale;
// a page's and a site's: the scripts the app sent (view_tell 1), waiting for the page there (loaded, or said something
// since it started); who takes a finger on it (view_tell 2: "all", "through", "pinch", "vertical") and the slop; how
// long a site's request waits for its head before the app is told (view_tell 3); where the app draws what takes a press
// over it (view_tell 4: x0 y0 x1 y1 …, points; a finger there is the canvas's)
@property(nonatomic, strong) NSMutableArray<NSString *> *scripts;
@property(nonatomic, copy) NSArray<NSNumber *> *covers;
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
- (void)seekTo:(double)ms;
- (void)seekTo:(double)ms near:(BOOL)near;
- (BOOL)hasAt:(double)ms;
- (void)playWhatCame;
- (CGImageRef)copyFrame;
- (void)stood;
@end

int32_t mb_host_view_info(int32_t vid, double *out);

static NSMutableDictionary<NSNumber *, MBNative *> *views;
// a site's own scheme: nothing else answers it
static NSString *const kSiteScheme = @"stillfail-preview";
static int32_t next_vid;
static int64_t next_z;  // the z the next view opened or raised takes: over all the others
// a view put elsewhere on the screen since the canvas's last frame was presented (moved, shown, hidden, closed): that
// frame is presented in the transaction that puts it there (apple.h mb_views_take_moved)
static int views_moved;
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

@implementation MBNative {
  double _stoodSaid[10];  // mb_host_view_info's numbers as the app was last told (stood)
}

// How it stands (mb_host_view_info) may have changed: the app told where it did (apple.h's mb_host_outside: kind 13,
// src/ui/hostcall.mbt's outside_stood), which reads it then, not each frame. Asked as anything changes (its player's
// state, its clock as it plays, a seek, its bytes, a page loaded): told only where something did.
- (void)stood {
  if (self.closed) return;
  double now[10];
  int32_t st = mb_host_view_info(self.vid, now);
  if (self.stoodTold && st == self.stoodState && !memcmp(now, _stoodSaid, sizeof now)) return;
  self.stoodTold = YES;
  self.stoodState = st;
  memcpy(_stoodSaid, now, sizeof now);
  mb_host_outside(MB_OUTSIDE_STOOD, self.vid, 0);
}

// To `ms`, exactly (or `near`: about there, the player's own choice of where it gets to at once), one seek at a time
// (Apple's QA1820, chasing the time): asked again while one is on its way, the last asked goes once it is done and
// those between are skipped, so a finger along the timeline sees each frame it gets to (AVPlayer gives up a seek on
// its way for the next, and while the finger moves none would show).
- (void)seekTo:(double)ms {
  [self seekTo:ms near:NO];
}

- (void)seekTo:(double)ms near:(BOOL)near {
  // (one on its way to what is here, or the item not ready for one yet: this one next, once it is; one on its way to
  // what has not come waits on the network, not on decoding, and the next goes at once in its place)
  if ((self.seeking && [self hasAt:self.seekMs]) || self.item.status != AVPlayerItemStatusReadyToPlay) {
    self.chasing = YES;
    self.chaseMs = ms;
    self.chaseNear = near;
    [self stood];
    return;
  }
  self.seeking = YES;
  self.chasing = NO;
  self.seekMs = ms;
  [self stood];
  int gen = ++self.seekGen;
  __weak MBNative *wv = self;
  // (to the µs: a frame's start, said with its fraction of a ms, is that frame's, not the one before)
  CMTime slack = near ? kCMTimePositiveInfinity : kCMTimeZero;
  [self.player seekToTime:CMTimeMake((int64_t)llround(ms * 1000.0), 1000000)
          toleranceBefore:slack
           toleranceAfter:slack
        completionHandler:^(BOOL done) {
          dispatch_async(dispatch_get_main_queue(), ^{
            MBNative *v = wv;
            if (!v || v.seekGen != gen) return;
            v.seeking = NO;
            if (v.chasing && !v.closed) {
              v.chasing = NO;
              [v seekTo:v.chaseMs near:v.chaseNear];
            }
            [v playWhatCame];
            [v stood];
            mb_host_request_frame();
          });
        }];
}

// Whether what plays at `ms` has come (a range the item has loaded holds it).
- (BOOL)hasAt:(double)ms {
  for (NSValue *r in self.item.loadedTimeRanges) {
    CMTimeRange tr = r.CMTimeRangeValue;
    double a = CMTimeGetSeconds(tr.start) * 1000.0, b = CMTimeGetSeconds(CMTimeRangeGetEnd(tr)) * 1000.0;
    if (a <= ms + 1 && ms < b) return YES;
  }
  return NO;
}

// Played, waiting only for what has not come: AVPlayer, left to itself, waits until it reckons the rest will come
// before it is played (AVPlayerWaitingToMinimizeStallsReason), on a slow network all of it; what has come plays at
// once, and where it runs out it waits again (the player's own waiting for bytes) until the next has come.
- (void)playWhatCame {
  if (self.seeking || self.chasing || self.player.rate <= 0) return;
  if (self.player.timeControlStatus != AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) return;
  if (![self.player.reasonForWaitingToPlay isEqualToString:AVPlayerWaitingToMinimizeStallsReason]) return;
  CMTime t = self.player.currentTime;
  if (!CMTIME_IS_NUMERIC(t)) return;
  double now = CMTimeGetSeconds(t) * 1000.0, dur = [self durationMs];
  // (up to its end: its last stretch is shorter)
  if ([self hasAt:dur > 0 ? fmin(now + kPlayAhead, dur - 1) : now + kPlayAhead]) [self.player playImmediatelyAtRate:self.player.rate];
}

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


// The frame showing now (the player's picture, copyFrame's), at most `side` pixels on its longer side, as a JPEG:
// what a viewer closing into its thumbnail goes with (native.mbt grab_shown).
- (void)grabShown:(double)side {
  self.stillState = 1;
  self.still = nil;
  CGImageRef img = [self copyFrame];
  NSMutableData *jpeg = nil;
  if (img) {
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    double k = fmin(1.0, side / (double)MAX(w, h));
    size_t tw = MAX((size_t)1, (size_t)llround(w * k)), th = MAX((size_t)1, (size_t)llround(h * k));
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(NULL, tw, th, 8, 0, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    CGImageRef small = NULL;
    if (c) {
      CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
      CGContextDrawImage(c, CGRectMake(0, 0, tw, th), img);
      small = CGBitmapContextCreateImage(c);
      CGContextRelease(c);
    }
    CGImageRelease(img);
    if (small) {
      jpeg = [NSMutableData new];
      CGImageDestinationRef dst =
          CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg, CFSTR("public.jpeg"), 1, NULL);
      if (dst) {
        CGImageDestinationAddImage(dst, small, (__bridge CFDictionaryRef) @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality : @0.9});
        if (!CGImageDestinationFinalize(dst)) jpeg = nil;
        CFRelease(dst);
      } else {
        jpeg = nil;
      }
      CGImageRelease(small);
    }
  }
  vlog(@"view %d: the frame shown %@", self.vid,
       jpeg ? [NSString stringWithFormat:@"grabbed (%lu bytes)", (unsigned long)jpeg.length] : @"not grabbed");
  self.still = jpeg;
  self.stillState = jpeg ? 2 : -1;
  mb_host_outside(MB_OUTSIDE_GRAB, self.vid, jpeg ? 1 : -1);
  mb_host_request_frame();
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
  [self stood];
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

// The player gave the load up: its reads not asked any more, those under way let go of (the app stops them), their
// answers dropped.
- (void)drop:(MBLoad *)l {
  l.gone = YES;
  [self.loads removeObject:l];
  NSMutableArray *keep = [NSMutableArray new];
  for (MBRead *r in self.pending)
    if (r.load != l) [keep addObject:r];
  self.pending = keep;
  for (NSNumber *rid in self.taken.allKeys) {
    if (self.taken[rid].load != l) continue;
    [self.taken removeObjectForKey:rid];
    if (!self.lettingGo) self.lettingGo = [NSMutableArray new];
    [self.lettingGo addObject:rid];
  }
  if (self.lettingGo.count) mb_host_request_frame();
}

// Read `rid`'s next bytes (after those it was answered before), as the app has them: given to the load as they come,
// its next read asked once it has had its last answer (`more` NO).
- (void)answer:(int32_t)rid data:(const uint8_t *)bytes length:(long long)n total:(double)total more:(BOOL)more {
  MBRead *r = self.taken[@(rid)];
  if (!r) return;
  if (!more || total == -2) [self.taken removeObjectForKey:@(rid)];
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
  long long at = r.off + r.got;  // where these bytes are in the file
  r.got += n;
  self.answered += n;
  [self stood];
  if (n > 0) {
    self.nanswers++;
    if (self.nanswers <= 4 || self.answered >= self.logNext) {
      vlog(@"view %d: read at %lld: %lld of %lld bytes%s (%.0f in all, of %lld)", self.vid, r.off, r.got, r.len,
           more ? "" : ", its last", self.answered, self.total);
      while (self.logNext <= self.answered) self.logNext += kMaxRead;
    }
  }
  if (l.gone) return;
  if (!l.hasData) {
    if (more) return;
    if (self.total < 0) {
      vlog(@"view %d: the file's size not told", self.vid);
      [self end:l error:YES];
      return;
    }
    [self advance:l];
    return;
  }
  long long end = l.end >= 0 ? l.end : LLONG_MAX;
  if (self.total >= 0 && end > self.total) end = self.total;
  long long skip = l.next - at;  // given on from where the load is: l.next
  long long give = skip >= 0 && skip < n ? MIN(n - skip, end - l.next) : 0;
  if (give > 0) {
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
  }
  if (more) return;
  if (r.got == 0) {  // the file's end: none before it (else the load fails, not asked again forever)
    if (self.total < 0) self.total = l.next;
    if (self.total > l.next) {
      vlog(@"view %d: no bytes at %lld, before the end (%lld)", self.vid, l.next, self.total);
      [self end:l error:YES];
      return;
    }
  }
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
    // a seek asked before it was ready (where it was left, opened again): taken up now
    if (self.chasing && !self.seeking && self.item.status == AVPlayerItemStatusReadyToPlay) {
      self.chasing = NO;
      [self seekTo:self.chaseMs near:self.chaseNear];
    }
    // a player is ready for the app once its first frame can be shown (a video), or once it can play at all with
    // no picture to show (a sound: its presentation size 0 × 0); or it failed
    BOOL can = self.item.status == AVPlayerItemStatusReadyToPlay;
    CGSize ps = self.item.presentationSize;
    if (self.playerLayer.readyForDisplay || (can && ps.width == 0 && ps.height == 0)) [self tell:1];
    else if (self.failed) [self tell:-1];
    [self playWhatCame];
    [self stood];
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
  [self.item removeObserver:self forKeyPath:@"loadedTimeRanges" context:kStatus];
  [self.playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:kReady];
  [self.player removeObserver:self forKeyPath:@"timeControlStatus" context:kStatus];
  if (self.ticks) [self.player removeTimeObserver:self.ticks];
  self.ticks = nil;
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
  [self stood];
  // ready for the app once it is drawn (its picture for snapshots is the host's own business: mb_views_snap_all, at a
  // snapshot)
  [self tellDrawn];
  [self refreshSnap];
  mb_host_request_frame();
}

// A page's readiness, once what it loaded is on the screen (WebKit's next presentation update, as Android waits on
// WebView's visual state): told at its load, the app took away what covers it before the page's first frame was there,
// and the empty view showed for a frame or more. At once where it does not show (nothing of it to wait for) or where
// WebKit has no such call (_doAfterNextPresentationUpdate:, WKWebViewPrivate).
- (void)tellDrawn {
  SEL after = NSSelectorFromString(@"_doAfterNextPresentationUpdate:");
  if (!self.placed || !self.shown || self.w <= 0 || self.h <= 0 || ![self.web respondsToSelector:after]) {
    [self tell:1];
    return;
  }
  __weak MBNative *me = self;
  void (^drawn)(void) = ^{
    MBNative *v = me;
    if (!v || v.closed) return;
    [v tell:1];
    mb_host_request_frame();
  };
  ((void (*)(id, SEL, id))objc_msgSend)(self.web, after, drawn);
}

// Its readiness told to the app (apple.h's mb_host_outside: kind 2), as it comes: ready (a page loaded and its picture
// taken, a player's first frame), or failed.
- (void)tell:(int)state {
  if (self.told && state > 0) return;
  self.told = state > 0;
  mb_host_outside(MB_OUTSIDE_VIEW, self.vid, state);
  [self stood];
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
  [v.item addObserver:v forKeyPath:@"loadedTimeRanges" options:0 context:kStatus];
  [v.playerLayer addObserver:v forKeyPath:@"readyForDisplay" options:0 context:kReady];
  // playing, waiting for what it needs, paused: a frame as that changes (the app draws a playing one's time; one that
  // waits moves on its own no more until this says so)
  [v.player addObserver:v forKeyPath:@"timeControlStatus" options:0 context:kStatus];
  // where it is as it plays, on its own clock (60 a second, and as it jumps): the app told (stood), which shows it
  __weak MBNative *wt = v;
  v.ticks = [v.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 60)
                                                   queue:dispatch_get_main_queue()
                                              usingBlock:^(CMTime t) {
                                                (void)t;
                                                [wt stood];
                                              }];
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

// A page's (kind 2: a visualization) data, one store for them all, kept across runs: what they load from the CDNs
// (a chart's library, mermaid, fonts) loaded once, from its cache after. A store of its own for each, as a site's, kept
// nothing even from one page to the next: each page loaded its libraries anew from the network as it opened. Nothing
// else of theirs is kept there: their documents have no origin of their own to keep cookies or storage for, and ask
// nothing of a server (their CSP's connect-src 'none').
static WKWebsiteDataStore *page_store(void) {
  static WKWebsiteDataStore *store;
  if (!store) store = [WKWebsiteDataStore defaultDataStore];
  return store;
}

static MBNative *open_web(int32_t vid, NSString *html) {
  MBNative *v = [MBNative new];
  WKWebViewConfiguration *c = page_config(v);
  c.websiteDataStore = page_store();
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
  // (placed by the app, clear of the screen's edges as it lays it out: no inset of the system's safe area again, a
  // white band under the page where the screen's foot is near)
  wv.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
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
  CFTimeInterval made_from = CACurrentMediaTime();
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
  // (placed by the app, clear of the screen's edges as it lays it out: no inset of the system's safe area again, a
  // white band under the page where the screen's foot is near)
  wv.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#endif
  v.web = wv;
  v.content = wv;
  NSString *s = start.length ? start : @"/";
  [wv loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://svc%@", kSiteScheme, s]]]];
  vlog(@"view %d: open site at %@ (%.0f ms)", vid, s, (CACurrentMediaTime() - made_from) * 1000);
  return v;
}

// A stream's picture (kind 4, `sid` its stream's id: @hostapi.stream_layers): a layer whose contents are the frame the
// app shows (its decoded IOSurface, apple_stream.m), stretched to the rect the app gives; ready at once.
static MBNative *open_stream_view(int32_t vid, int32_t sid) {
  MBNative *v = [MBNative new];
  MBStreamView *sv = [[MBStreamView alloc] initWithFrame:CGRectZero];
#if TARGET_OS_IOS
  sv.userInteractionEnabled = NO;
#endif
  CALayer *layer = sv.layer;
  layer.contentsGravity = kCAGravityResize;  // the app gives the picture's own rect
  layer.backgroundColor = black_color();
  v.content = sv;
  v.streamSid = sid;
  mb_stream_attach_layer(sid, layer);
  vlog(@"view %d: open stream %d's layer", vid, sid);
  // (told as the app has its ticket: after it opened it)
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!v.closed) [v tell:1];
  });
  return v;
}

static BOOL is_page(MBNative *v) { return v.kind == 2 || v.kind == 3; }

int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  if (kind < 1 || kind > 4) return 0;
  if (!views) views = [NSMutableDictionary new];
  int32_t vid = ++next_vid;
  NSString *a = mb_ns_from_string(arg);
  MBNative *v = kind == 1 ? open_video(vid, a) : kind == 2 ? open_web(vid, a) : kind == 3 ? open_site(vid, a)
                                                                                        : open_stream_view(vid, a.intValue);
  v.vid = vid;
  v.kind = kind;
  v.z = ++next_z;
  v.box = new_box();
  [v.box addSubview:v.content];
  v.box.hidden = YES;
  views[@(vid)] = v;
  return vid;
}

// Its box put among the others' in views_root as its z says: under the lowest of those over it, else over them all.
static void stack(MBNative *v) {
  if (!views_root) return;
  MBNative *over = nil;
  for (MBNative *o in views.allValues)
    if (o != v && o.box.superview == views_root && o.z > v.z && (!over || o.z < over.z)) over = o;
#if TARGET_OS_OSX
  [views_root addSubview:v.box positioned:over ? NSWindowBelow : NSWindowAbove relativeTo:over.box];
#else
  if (over) [views_root insertSubview:v.box belowSubview:over.box];
  else if (v.box.superview == views_root) [views_root bringSubviewToFront:v.box];
  else [views_root addSubview:v.box];
#endif
}

// How much further in than a circle a capsule's end lies, in r, u r from its tip (mbui's capsule_ease, src/paint/
// smooth.mbt, and corner.sl's mb_capsule_ease): 0 but from 0.3 to 1 + k.
static double capsule_ease(double u, double k) {
  double e = 1 + k;
  if (k <= 0 || u <= 0.3 || u >= e) return 0;
  double h = e - 0.3, t = (u - 0.3) / h, t2 = t * t, t3 = t2 * t;
  double w0 = 1 - t3 * (10 - 15 * t + 6 * t2), w1 = t - t3 * (6 - 8 * t + 3 * t2),
         w2 = t2 * (0.5 - t * (1.5 - t * (1.5 - 0.5 * t)));
  double eased = 0.285857157145715 * w0 - 0.9801960588196068 * h * w1 + 2.7456472235843328 * h * h * w2;
  return eased - (u < 1 ? 1 - sqrt(u * (2 - u)) : 0);
}

// How far a corner of R (given r, s smooth) eases into the edge along a side of half `ha`, the other `hc` (mbui's
// capsule_tail's weight, its share k of the room it needs in *k): as far as it has no room across and room along.
static double ease_weight(double r, double R, double s, double ha, double hc, double *k) {
  *k = R > 0 ? fmin((ha - R) / R, 1) : 0;
  double tight = 1 - (R <= 0 ? 0 : fmin(1, fmax(0, (hc - R) / (0.25 * R))));
  return s >= 1 || *k <= 0 || tight <= 0 ? 0 : (1 - s) * tight * *k;
}

static void corner_point(CGMutablePathRef p, double x, double y) {
  if (CGPathIsEmpty(p)) CGPathMoveToPoint(p, NULL, x, y);
  else CGPathAddLineToPoint(p, NULL, x, y);
}

// One corner of mbui's (src/ui/smooth.mbt, src/host/corner.sl mb_sd_corner) on path p: |x|^n + |y|^n = R^n about its
// centre (cx, cy), the quarter towards (sx, sy), from its end along x (`from_x`) or along y, as the hole's is drawn;
// a capsule's end eased into its long edges (hx, hy the box's half sides): moved in as far as the ease says there, and
// on along the edge until the ease is done.
static void smooth_corner(CGMutablePathRef p, double r, double room, double hx, double hy, double cx, double cy,
                          double sx, double sy, BOOL from_x) {
  double s = r <= 0 ? 0 : fmin(1, fmax(0, (room - r) / (0.25 * r)));
  double R = fmin(r * (1 + 0.25 * s), room), n = 2 + 0.8284271247461903 * s;
  double kx, ky;
  double wx = ease_weight(r, R, s, hx, hy, &kx), wy = ease_weight(r, R, s, hy, hx, &ky);
  const int steps = 24, on = 12;
  // (the way it goes: along the edge at x's end towards the corner, round it, along the edge at y's end away; or back)
  for (int part = 0; part < 3; part++) {
    int which = from_x ? part : 2 - part;
    for (int j = 0; j <= (which == 1 ? steps : on); j++) {
      double x, y;
      if (which == 1) {
        double t = (from_x ? j : steps - j) * M_PI_2 / steps;
        x = R * pow(fmax(0, cos(t)), 2 / n);
        y = R * pow(fmax(0, sin(t)), 2 / n);
        // (in along the round corner's normal, as the distance is)
        double ux = 1 - x / R, uy = 1 - y / R;
        double ex = wx * capsule_ease(ux, kx) * R, ey = wy * capsule_ease(uy, ky) * R;
        x -= ey * x / R;
        y -= ex * y / R;
      } else if (which == 0) {
        // along the edge at x's end (the side running along y), from where the ease ends to the corner, or back
        if (wy <= 0) continue;
        double u = 1 + ky * (from_x ? 1 - (double)j / on : (double)j / on);
        x = R - wy * capsule_ease(u, ky) * R;
        y = R - u * R;
      } else {
        if (wx <= 0) continue;
        double u = 1 + kx * (from_x ? (double)j / on : 1 - (double)j / on);
        x = R - u * R;
        y = R - wx * capsule_ease(u, kx) * R;
      }
      corner_point(p, cx + sx * x, cy + sy * y);
    }
  }
}

// A view's corners round (a native view's content, as the hole the app paints for it; a frost, as its glass), each its
// own (top left, then round it), smooth as mbui's are (a circle's arc cut the page short of the hole along each corner,
// its ground showing in between): a mask of that shape on its layer, laid along the layer's y as it runs (a Mac's view
// not flipped: up).
static void round_layer(PView *c, double r0, double r1, double r2, double r3) {
  CALayer *l = c.layer;
  l.cornerRadius = 0;
  l.masksToBounds = NO;
  if (r0 <= 0 && r1 <= 0 && r2 <= 0 && r3 <= 0) {
    if ([l.mask isKindOfClass:CAShapeLayer.class]) l.mask = nil;
    return;
  }
  CGRect b = l.bounds;
  double w = b.size.width, h = b.size.height, most = fmin(w, h) / 2;
  // the corners at the layer's y 0 first (left, right), then those at its height (right, left)
  double a0 = r0, a1 = r1, a2 = r2, a3 = r3;
#if TARGET_OS_OSX
  NSPoint top = [c convertPointToLayer:NSMakePoint(0, c.isFlipped ? 0 : c.bounds.size.height)];
  if (top.y > h / 2) {
    a0 = r3; a1 = r2; a2 = r1; a3 = r0;
  }
#endif
  a0 = fmax(0, fmin(a0, most)); a1 = fmax(0, fmin(a1, most));
  a2 = fmax(0, fmin(a2, most)); a3 = fmax(0, fmin(a3, most));
  CGMutablePathRef p = CGPathCreateMutable();
  // (each corner about its centre its R in from both edges: round the box from the first's end along the left edge)
  double k[4] = {a0, a1, a2, a3};
  double R[4];
  for (int i = 0; i < 4; i++) {
    double s = k[i] <= 0 ? 0 : fmin(1, fmax(0, (most - k[i]) / (0.25 * k[i])));
    R[i] = fmin(k[i] * (1 + 0.25 * s), most);
  }
  smooth_corner(p, a0, most, w / 2, h / 2, R[0], R[0], -1, -1, YES);
  smooth_corner(p, a1, most, w / 2, h / 2, w - R[1], R[1], 1, -1, NO);
  smooth_corner(p, a2, most, w / 2, h / 2, w - R[2], h - R[2], 1, 1, YES);
  smooth_corner(p, a3, most, w / 2, h / 2, R[3], h - R[3], -1, 1, NO);
  CGPathCloseSubpath(p);
  CAShapeLayer *m = [l.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)l.mask : [CAShapeLayer layer];
  m.frame = b;
  m.path = p;
  CGPathRelease(p);
  l.mask = m;
}

void mb_host_view_place(int32_t vid, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, double r0, double r1, double r2, double r3, int32_t shown) {
  MBNative *v = views[@(vid)];
  if (!v) return;
  BOOL s = shown != 0;
  if (v.placed && v.shown == s && v.x == x && v.y == y && v.w == w && v.h == h && v.cx0 == cx0 && v.cy0 == cy0 &&
      v.cx1 == cx1 && v.cy1 == cy1 && v.r0 == r0 && v.r1 == r1 && v.r2 == r2 && v.r3 == r3)
    return;
  BOOL resized = !v.placed || v.w != w || v.h != h;
  views_moved = 1;
  v.placed = YES;
  v.shown = s;
  v.x = x; v.y = y; v.w = w; v.h = h;
  v.cx0 = cx0; v.cy0 = cy0; v.cx1 = cx1; v.cy1 = cy1;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (!v.box.superview) stack(v);
  v.box.hidden = !s;
  v.box.frame = CGRectMake(cx0, cy0, fmax(0, cx1 - cx0), fmax(0, cy1 - cy0));
  v.content.frame = CGRectMake(x - cx0, y - cy0, fmax(0, w), fmax(0, h));
  // (a stream's pointer on its layer where it points on it now)
  if (v.kind == 4) mb_stream_layout(v.streamSid, fmax(0, w), fmax(0, h));
  // its corners round (as the hole the app paints for it): its own layer cut to them, what it holds with it
  if (r0 > 0 || r1 > 0 || r2 > 0 || r3 > 0 || v.r0 > 0 || v.r1 > 0 || v.r2 > 0 || v.r3 > 0) {
#if TARGET_OS_OSX
    v.content.wantsLayer = YES;
#endif
    round_layer(v.content, r0, r1, r2, r3);
  }
  v.r0 = r0; v.r1 = r1; v.r2 = r2; v.r3 = r3;
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
    // (its corners as put: the layer's, else its mask's, as told)
    BOOL masked = [v.content.layer.mask isKindOfClass:CAShapeLayer.class];
    double k0 = masked ? v.r0 : v.content.layer.cornerRadius, k1 = masked ? v.r1 : k0, k2 = masked ? v.r2 : k0,
           k3 = masked ? v.r3 : k0;
    vlog(@"VIEWAT %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", vid,
         (b.origin.x + c.origin.x) * px, (b.origin.y + c.origin.y) * px, c.size.width * px, c.size.height * px,
         b.origin.x * px, b.origin.y * px, (b.origin.x + b.size.width) * px, (b.origin.y + b.size.height) * px,
         fmax(fmax(k0, k1), fmax(k2, k3)) * px, k0 * px, k1 * px, k2 * px, k3 * px);
  }
  if (resized && is_page(v)) [v refreshSnap];
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
  } else if (v.kind == 4) {
    mb_stream_attach_layer(v.streamSid, nil);
    vlog(@"view %d: closed", vid);
  } else {
    [v.web stopLoading];
    v.web.navigationDelegate = nil;
    for (MBSiteReq *q in v.reqs.allValues) q.gone = YES;
    [v.reqs removeAllObjects];
    vlog(@"view %d: closed", vid);
  }
  if (v.box.superview && !v.box.hidden) views_moved = 1;
  [v.box removeFromSuperview];
}

void mb_host_view_control(int32_t vid, int32_t op, double value) {
  MBNative *v = views[@(vid)];
  if (v && is_page(v) && op == 21) {
    [v grabPage];
    return;
  }
  if (v && is_page(v) && op == 8) {
    // The page's own scale and the window's content zoom have already been composed by the UI.
    if (value > 0) {
      v.scale = value;
      if (@available(macOS 11.0, iOS 14.0, *)) v.web.pageZoom = value;
    }
    return;
  }
  if (v && v.kind == 3) {
    switch (op) {
      case 5: if (v.web.canGoBack) [v.web goBack]; break;
      case 6: if (v.web.canGoForward) [v.web goForward]; break;
      case 7: [v.web reload]; break;
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
      [v stood];
      break;
    }
    case 2:
      [v.player pause];
      [v stood];
      break;
    case 3: [v seekTo:value]; break;
    case 11: [v seekTo:value near:YES]; break;
    case 4:
      if (value <= 0) break;
      v.speed = value;
      if (v.player.rate > 0) v.player.rate = (float)value;
      break;
    // how loud, 0 to 1 (NativeView::volume)
    case 10: v.player.volume = (float)fmax(0.0, fmin(1.0, value)); break;
    case 20: [v readFrames]; break;
    case 21: [v grabAt:value]; break;
    case 22: [v grabShown:value]; break;
  }
}

// A video's frames' times and a frame grabbed (native.mbt `frames`, `grabbed`).
moonbit_string_t mb_host_view_text(int32_t vid, int32_t what) {
  MBNative *v = views[@(vid)];
  if (v && is_page(v) && what == 2) return mb_string_from_ns([NSString stringWithFormat:@"%d", v.stillState]);
  if (!v || v.kind != 1) return moonbit_make_string_raw(0);
  return mb_string_from_ns(what == 1 ? (v.frames ?: @"") : [NSString stringWithFormat:@"%d", v.stillState]);
}

int32_t mb_host_view_text_known(int32_t vid, int32_t what) {
  MBNative *v = views[@(vid)];
  if (v && is_page(v) && what == 2) return 1;
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
  if (v.kind == 4) return 1;
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
  // seeking (or a seek waiting for it to be ready): where it was last asked to go
  if (v.seeking || v.chasing) out[1] = v.chasing ? v.chaseMs : v.seekMs;
  out[2] = v.player.rate > 0 ? 1 : 0;
  CGSize s = it.presentationSize;
  out[3] = s.width;
  out[4] = s.height;
  out[5] = v.answered;
  out[6] = v.playerLayer.readyForDisplay ? 1 : 0;
  // buffering only while a read of the app's bytes is under way: a seek within what the player has already (a finger
  // along the timeline over what has played) waits on its own decoding, not on the network
  BOOL waiting = v.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
  BOOL reading = v.pending.count > 0 || v.taken.count > 0;
  out[7] = ((waiting || (v.player.rate > 0 && !it.playbackLikelyToKeepUp)) && reading) ? 1 : 0;
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
  if (v.lettingGo.count) {
    int32_t gone = v.lettingGo.firstObject.intValue;
    [v.lettingGo removeObjectAtIndex:0];
    return -gone;
  }
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

void mb_host_view_read_answer(int32_t vid, int32_t req, moonbit_bytes_t data, double total, int32_t more) {
  MBNative *v = views[@(vid)];
  if (!v) return;
  [v answer:req data:(const uint8_t *)data length:Moonbit_array_length(data) total:total more:more != 0];
}

// ---- a site's API ----

moonbit_string_t mb_host_view_site_next(int32_t vid) {
  MBNative *v = views[@(vid)];
  if (!v || !is_page(v) || v.said.count == 0) return mb_string_from_ns(@"");
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
  if (v && what == 5) {
    // raised over all the others (the app paints it after them)
    v.z = ++next_z;
    if (v.box.superview) {
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      stack(v);
      [CATransaction commit];
      views_moved = 1;
    }
    // how they are stacked, the lowest first (scripts/host_contract.sh HOST views: as the app told, VIEWSTACKTOLD)
    NSArray<MBNative *> *order = [views.allValues sortedArrayUsingComparator:^NSComparisonResult(MBNative *a, MBNative *b) {
      return a.z < b.z ? NSOrderedAscending : a.z > b.z ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableString *line = [NSMutableString stringWithString:@"VIEWSTACK"];
    for (MBNative *o in order) [line appendFormat:@" %d", o.vid];
    vlog(@"%@", line);
    return;
  }
  if (!v || !is_page(v)) return;
  NSString *t = mb_ns_from_string(text);
  if (what == 1) {
    [v.scripts addObject:t];
    [v runScripts];
  } else if (what == 2) {
    NSArray<NSString *> *p = [t componentsSeparatedByString:@" "];
    v.touchMode = p.firstObject ?: @"all";
    v.slop = p.count > 1 ? p[1].doubleValue : 0;
  } else if (what == 4) {
    NSMutableArray<NSNumber *> *r = [NSMutableArray array];
    if (t.length)
      for (NSString *s in [t componentsSeparatedByString:@" "]) [r addObject:@(s.doubleValue)];
    v.covers = r;
  } else if (what == 3) {
    NSDictionary *o = [NSJSONSerialization JSONObjectWithData:[t dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([o isKindOfClass:NSDictionary.class] && [o[@"head_wait_ms"] isKindOfClass:NSNumber.class])
      v.headWaitMs = [o[@"head_wait_ms"] doubleValue];
  }
}

// Whether the app draws something that takes a press over the view at the point (view_tell 4).
static BOOL covered_at(MBNative *v, double x, double y) {
  NSArray<NSNumber *> *r = v.covers;
  for (NSUInteger j = 0; j + 3 < r.count; j += 4)
    if (x >= r[j].doubleValue && x < r[j + 2].doubleValue && y >= r[j + 1].doubleValue && y < r[j + 3].doubleValue)
      return YES;
  return NO;
}

// The page's view a point is on (shown, placed, not under what the app draws over it that takes a press), or nil.
// (the one stacked over the others where several are)
static MBNative *page_at(double x, double y) {
  MBNative *top = nil;
  for (MBNative *v in views.allValues) {
    if (top && top.z > v.z) continue;
    if (!is_page(v) || !v.shown || !v.placed || covered_at(v, x, y)) continue;
    double x0 = fmax(v.cx0, v.x), y0 = fmax(v.cy0, v.y);
    double x1 = fmin(v.cx1, v.x + v.w), y1 = fmin(v.cy1, v.y + v.h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) top = v;
  }
  return top;
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
    if (!is_page(v) || !v.shown || !v.placed) continue;
    // (a page that takes no finger: the canvas's)
    if ([v.touchMode isEqualToString:@"through"] || covered_at(v, x, y)) continue;
    double x0 = fmax(v.cx0, v.x), y0 = fmax(v.cy0, v.y);
    double x1 = fmin(v.cx1, v.x + v.w), y1 = fmin(v.cy1, v.y + v.h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return 1;
  }
  return 0;
}

int mb_views_count(void) { return (int)views.count; }

int mb_views_take_moved(void) {
  int m = views_moved;
  views_moved = 0;
  return m;
}

// ---- frost: glass over the views (apple.h mb_views_frost, apple_render.m glass_through) ----
// Each a box (clips: what of its glass shows) holding its content (at the glass's rect, its corners: round_layer),
// whose backdrop, grown by the blur's reach and cut by the content's corners, blurs and saturates what the views under
// it show: Core Animation's CABackdropLayer and its filters, which AppKit's and UIKit's own blur are made of (looked
// up by name: where the system has none, there is no frost and the glass is as before). It takes no input. Put among
// the views just over the one it frosts.

#if TARGET_OS_OSX
@interface MBFrostView : MBFlipView
@end
@implementation MBFrostView
- (NSView *)hitTest:(NSPoint)p { return nil; }
@end
#endif

@interface MBFrost : NSObject {
 @public
  double told[MB_FROST_N];  // as it was put (apple.h)
}
@property(nonatomic, strong) PView *box, *content;
@property(nonatomic, strong) CALayer *backdrop;
@end
@implementation MBFrost
@end

static NSMutableArray<MBFrost *> *frosts;
static Class backdrop_class, filter_class;
static int frost_can = -1;

static int frost_able(void) {
  if (frost_can < 0) {
    backdrop_class = NSClassFromString(@"CABackdropLayer");
    filter_class = NSClassFromString(@"CAFilter");
    frost_can = backdrop_class && filter_class &&
                [filter_class respondsToSelector:NSSelectorFromString(@"filterWithType:")];
  }
  return frost_can;
}

static id frost_filter(NSString *type) {
  return ((id (*)(id, SEL, id))objc_msgSend)(filter_class, NSSelectorFromString(@"filterWithType:"), type);
}

static MBFrost *new_frost(void) {
  MBFrost *f = [MBFrost new];
#if TARGET_OS_OSX
  MBFrostView *b = [[MBFrostView alloc] initWithFrame:NSZeroRect];
  b.wantsLayer = YES;
  b.layer.masksToBounds = YES;
  MBFrostView *c = [[MBFrostView alloc] initWithFrame:NSZeroRect];
  c.wantsLayer = YES;
#else
  UIView *b = new_box();
  b.userInteractionEnabled = NO;
  UIView *c = [[UIView alloc] initWithFrame:CGRectZero];
  c.userInteractionEnabled = NO;
#endif
  [b addSubview:c];
  CALayer *l = [backdrop_class layer];
  // (blurred at a quarter of its pixels, as the system's own: the blur is wide)
  if ([l respondsToSelector:NSSelectorFromString(@"setScale:")]) [l setValue:@0.25 forKey:@"scale"];
  [c.layer addSublayer:l];
  f.box = b;
  f.content = c;
  f.backdrop = l;
  for (int i = 0; i < MB_FROST_N; i++) f->told[i] = NAN;
  return f;
}

// Frost f put as d says (apple.h), in the frame's transaction.
static void put_frost(MBFrost *f, const double *d) {
  f.box.frame = CGRectMake(d[0], d[1], fmax(0, d[2] - d[0]), fmax(0, d[3] - d[1]));
  f.content.frame = CGRectMake(d[4] - d[0], d[5] - d[1], fmax(0, d[6]), fmax(0, d[7]));
#if TARGET_OS_OSX
  f.box.alphaValue = d[14];
#else
  f.box.alpha = d[14];
#endif
  round_layer(f.content, d[8], d[9], d[10], d[11]);
  if (d[8] <= 0 && d[9] <= 0 && d[10] <= 0 && d[11] <= 0) f.content.layer.masksToBounds = YES;
  // (what it blurs reaches past its edge, as the glass's copy does)
  double reach = 3 * d[12];
  f.backdrop.frame = CGRectInset(f.content.layer.bounds, -reach, -reach);
  if (d[12] != f->told[12] || d[13] != f->told[13]) {
    id blur = frost_filter(@"gaussianBlur");
    [blur setValue:@(d[12]) forKey:@"inputRadius"];
    [blur setValue:@YES forKey:@"inputNormalizeEdges"];
    if (d[13] != 1) {
      id sat = frost_filter(@"colorSaturate");
      [sat setValue:@(d[13]) forKey:@"inputAmount"];
      f.backdrop.filters = @[ blur, sat ];
    } else {
      f.backdrop.filters = @[ blur ];
    }
  }
  memcpy(f->told, d, sizeof f->told);
}

int mb_views_frost(int n, const double *d) {
  if (!frosts) frosts = [NSMutableArray new];
  int can = frost_able() && views_root;
  if (!can) n = 0;
  if (!n && !frosts.count) return can;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  PView *last = nil;
  int32_t last_under = 0;
  for (int i = 0; i < n; i++) {
    const double *e = d + i * MB_FROST_N;
    if (i >= (int)frosts.count) [frosts addObject:new_frost()];
    MBFrost *f = frosts[i];
    int32_t vid = (int32_t)e[15];
    MBNative *under = views[@(vid)];
    if (!under || under.box.superview != views_root) {
      if (f.box.superview) views_moved = 1;
      [f.box removeFromSuperview];
      continue;
    }
    if (memcmp(f->told, e, sizeof f->told) != 0) {
      put_frost(f, e);
      views_moved = 1;
    }
    // just over the view it frosts, over the frosts of that view before it
    PView *below = last && last_under == vid ? last : under.box;
    NSArray<PView *> *sv = views_root.subviews;
    NSUInteger k = [sv indexOfObjectIdenticalTo:f.box];
    if (k == NSNotFound || k == 0 || sv[k - 1] != below) {
#if TARGET_OS_OSX
      [views_root addSubview:f.box positioned:NSWindowAbove relativeTo:below];
#else
      [views_root insertSubview:f.box aboveSubview:below];
#endif
      views_moved = 1;
    }
    last = f.box;
    last_under = vid;
  }
  for (int i = n; i < (int)frosts.count; i++) {
    MBFrost *f = frosts[i];
    if (f.box.superview) views_moved = 1;
    [f.box removeFromSuperview];
  }
  if ((int)frosts.count > n) [frosts removeObjectsInRange:NSMakeRange((NSUInteger)n, frosts.count - (NSUInteger)n)];
  [CATransaction commit];
  return can;
}

// Whether a page's picture for snapshots is being taken (apple.h).
int mb_views_snapping(void) {
  for (MBNative *v in views.allValues)
    if (v.snapping && !v.closed) return 1;
  return 0;
}

// A snapshot is about to be taken: every page loaded and placed has its picture taken anew (apple.h).
void mb_views_snap_all(void) {
  for (MBNative *v in views.allValues)
    if (is_page(v) && !v.closed && v.loaded) [v refreshSnap];
}

void mb_views_draw_under(CGContextRef ctx, double scale) {
  size_t H = CGBitmapContextGetHeight(ctx);
  // as they are stacked: the one over the others drawn last
  NSArray<MBNative *> *order = [views.allValues sortedArrayUsingComparator:^NSComparisonResult(MBNative *a, MBNative *b) {
    return a.z < b.z ? NSOrderedAscending : a.z > b.z ? NSOrderedDescending : NSOrderedSame;
  }];
  for (MBNative *v in order) {
    if (!v.shown || !v.placed || v.w <= 0 || v.h <= 0) continue;
    CGContextSaveGState(ctx);
    // the app's coordinates: points from the top left
    CGContextTranslateCTM(ctx, 0, H);
    CGContextScaleCTM(ctx, scale, -scale);
    CGContextClipToRect(ctx, CGRectMake(v.cx0, v.cy0, fmax(0, v.cx1 - v.cx0), fmax(0, v.cy1 - v.cy0)));
    CGRect r = CGRectMake(v.x, v.y, v.w, v.h);
    if (!is_page(v)) CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    else CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, r);
    CGImageRef img = v.kind == 1 ? [v copyFrame] : v.kind == 4 ? NULL : [v copySnap];
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

// A picture or a film into Photos: the system asks once whether the app may add to it
// (NSPhotoLibraryAddUsageDescription), then it is added from its part file (a film by its name's .mp4, .m4v or .mov);
// not allowed, or not one Photos takes: failed.
static void keep_photos(MBKeep *k) {
  NSURL *u = [NSURL fileURLWithPath:k.part];
  BOOL film = [@[ @"mp4", @"m4v", @"mov" ] containsObject:k.name.pathExtension.lowercaseString];
  void (^answer)(BOOL) = ^(BOOL ok) {
    dispatch_async(dispatch_get_main_queue(), ^{ keep_answer(k, ok ? 1 : -1, ok ? @"Photos" : nil); });
  };
  [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
    if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
      vlog(@"keep %@: not allowed into Photos (%ld)", k.name, (long)st);
      answer(NO);
      return;
    }
    [PHPhotoLibrary.sharedPhotoLibrary
        performChanges:^{
          if (film) [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:u];
          else [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:u];
        }
     completionHandler:^(BOOL ok, NSError *e) {
       if (ok) vlog(@"keep %@: into Photos", k.name);
       else vlog(@"keep %@ into Photos: %@", k.name, e.localizedDescription);
       answer(ok);
     }];
  }];
}

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
  if (k.way == 3) {
    keep_photos(k);
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
