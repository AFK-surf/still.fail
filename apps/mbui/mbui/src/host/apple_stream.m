// Streams on macOS and iOS (src/hostapi/stream.mbt, @ui's Stream): a picture decoded frame by frame, drawn by the app as
// an image. As still.fail's Android app decodes a remote screen (its remote/Decoders.kt), with what is shown said by
// the app.
//
// H.264 by VideoToolbox: a decompression session made from the config's avcC (its parameter sets, its NAL length:
// avc.h), each access unit handed over as it came (AVCC), once known sound; frames decoded into Metal-compatible BGRA
// pixel buffers, each kept until the app shows it (or a later one) and told it ("f TS W H"). JPEG by ImageIO on a queue
// of the stream's own, into a texture, kept the same way. The app shows a frame (`stream_show`, on the main thread, as
// its frame takes the event): the stream's texture from then on (a pixel buffer's through a CVMetalTextureCache), what
// the renderer draws its instances with (apple_render.m: image MB_STREAM_TEX + its id).
//
// Frames let go ("d TS": no session or not past a key frame, one that is not sound AVCC, the older of two it holds,
// those inside it as it starts anew, one the decoder drops, a JPEG that does not decode) and the decoder broken ("b": an
// error, a session the system invalidated, as iOS does in the background) are told the same way; each event asks for
// a frame. The session's work runs on the stream's own serial queue; its output comes back to it. Its sound plays from
// a queue of its own.
//
// Routed (mb_stream_route_take, @hostapi.stream_direct): where an app's engine reads a remote screen itself (its shell),
// the frames and sound of the view the app routed to a stream come here from the engine's thread, not through the
// app's queue: fed to the decoder as they come, each decoded one shown at once (on the main thread, nothing of the app's
// run) and acknowledged to its sender (mb_stream_route_acks), one let go acknowledged too, the sound played. The app is
// told what came so in one event when it next reads the stream's ("D TS N BYTES": the last shown, how many frames came
// and their bytes since it was last told). A config (or the sound's) stops the route until the app has taken it and
// routes it again, so what it says of it is in order with what the decoder is fed.
#import "apple.h"
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#include <os/lock.h>
#include "avc.h"

// (linked wherever this is, whatever the app's own link flags say)
__asm__(".linker_option \"-framework\", \"VideoToolbox\"");
__asm__(".linker_option \"-framework\", \"CoreMedia\"");
__asm__(".linker_option \"-framework\", \"CoreVideo\"");

__asm__(".linker_option \"-framework\", \"AVFoundation\"");

void mb_host_request_frame(void);

// A frame decoded, kept until shown or passed over: a pixel buffer (H.264) or a texture (JPEG).
@interface MBStreamFrame : NSObject
@property double ts;
@property int w, h;
@property CVPixelBufferRef pixels;  // retained
@property id<MTLTexture> tex;
@end
@implementation MBStreamFrame
- (void)dealloc {
  if (_pixels) CVPixelBufferRelease(_pixels);
}
@end

@interface MBStream : NSObject
@property int sid;
@property dispatch_queue_t queue, jpegQueue;
// what it says, oldest first (under @synchronized(self)), and the frames decoded and not shown yet
@property NSMutableArray<NSString *> *events;
@property NSMutableArray<MBStreamFrame *> *decoded;
// what it is drawn with now (main thread): its texture, and (H.264) the CVMetalTexture under it, and those let go
// lately, kept while a frame in flight may still draw them
@property id<MTLTexture> tex;
@property NSMutableArray *retired;
// a frame shown in wider colours than sRGB's (a Display P3 stream's: `gamut: "p3"`, asked where frames go on the
// system video layer, which shows them as tagged), its texture not made yet: made in sRGB only if the app draws it (a
// faded or ended view's picture), with the transfer session and pool that convert it (main thread)
@property MBStreamFrame *wide;
@property VTPixelTransferSessionRef toSRGB;
@property CVPixelBufferPoolRef srgbPool;
@property int srgbW, srgbH;
// the decoder (its queue): the config's format, its NAL length size and picture size, the session and its generation
// (the output of an older one is not this one's), whether it waits for a key frame, the frames inside it
@property CMVideoFormatDescriptionRef format;
@property int lengthSize, w, h;
@property VTDecompressionSessionRef session;
@property AVAudioEngine *audioEngine;
@property AVAudioPlayerNode *audioPlayer;
@property NSUInteger audioQueued, audioGeneration;
@property uint32_t generation;
@property BOOL needKey, closed;
@property NSMutableArray<NSNumber *> *inside;
// the system video layer its frames are put on as they are shown (a native view's of kind 4: apple_views.m), if any;
// the picture's format there, made again as its size changes
@property(weak) CALayer *display;
// its sound (on audioQueue, the player's state there too)
@property dispatch_queue_t audioQueue;
// the frames fed it from a route (mb_stream_route_take), on its queue: by time, their bytes until their fate is known,
// -1 once let go (acknowledged, its picture not shown if it still comes); the route they came by
@property NSMutableDictionary<NSNumber *, NSNumber *> *direct;
@property uint64_t directRoute;
// (main thread) the last of them shown, and what the app was told of them ("D …": mb_host_stream_next)
@property double directAt, directToldAt;
@property long directToldFrames, directToldBytes;
// (under @synchronized(self), from the engine's thread) how many came that way, and their bytes
@property long directFrames, directBytes;
@property CVPixelBufferRef displayed;  // retained: the last shown, put on a layer attached later
@property NSMutableArray *onLayer;     // the pixel buffers last put on it (display)
// a pointer over its picture on that layer (@hostapi.stream_pointer): its own sublayer, its picture and size (points),
// its hot spot, where it points (0..1 of the layer's bounds) and whether it shows
@property CALayer *pointer;
@property(strong) id pointerImage;  // a CGImage
@property double pointerW, pointerH, pointerHx, pointerHy, pointerX, pointerY;
// the layer's size as its view was last placed (points; 0: its bounds'), what AppKit may give its layer later
@property double placedW, placedH;
@property BOOL pointerShown;
@end
@implementation MBStream
@end

static NSMutableDictionary<NSNumber *, MBStream *> *streams;
static int next_stream;
static CVMetalTextureCacheRef texture_cache;

static NSString *num(double v) {
  if (v == floor(v) && fabs(v) < 1e15) return [NSString stringWithFormat:@"%lld", (long long)v];
  return [NSString stringWithFormat:@"%.17g", v];
}

static MBStream *stream_of(int32_t sid);

static void say(MBStream *s, NSString *e) {
  @synchronized(s) {
    if (s.closed) return;
    [s.events addObject:e];
  }
  int32_t sid = s.sid;
  // shown by its system video layer: the app told (ui's streams_said), a frame asked for only where what it said
  // changes what is drawn; else a frame, which takes it
  dispatch_async(dispatch_get_main_queue(), ^{
    MBStream *live = stream_of(sid);
    if (live && live.display) mb_host_outside(MB_OUTSIDE_STREAMED, sid, 0);
    else mb_host_request_frame();
  });
}

// (from any thread: the decoder's output looks its stream up where it comes, not on the main thread)
static NSLock *streams_lock;
static MBStream *stream_of(int32_t sid) {
  [streams_lock lock];
  MBStream *s = streams[@(sid)];
  [streams_lock unlock];
  return s;
}
static void display(MBStream *s, CVPixelBufferRef px);
static BOOL wider_than_srgb(CVPixelBufferRef px);
static void use_texture(MBStream *s, CVPixelBufferRef px, id<MTLTexture> tex, id keep);

// ---- routes: a remote screen's frames straight from an app's engine ----

// A route (the app's call a view is) and the streams its frames and sound go to (0: the app's to take), with the number
// of the last record offered by it (the app routes it only as it has taken that one: nothing of it left in its queue).
typedef struct {
  uint64_t route, seq, used;
  int32_t video, audio;
} mb_route;
#define MB_ROUTES 8
static mb_route routes[MB_ROUTES];
static uint64_t routes_used;
static os_unfair_lock routes_lock = OS_UNFAIR_LOCK_INIT;
static int (*route_ack)(double route, double ts);

// (under routes_lock) route's entry; made where `make` (in a free one, else one routing nothing used least lately)
static mb_route *route_at(uint64_t route, BOOL make) {
  mb_route *empty = NULL, *old = NULL;
  for (int i = 0; i < MB_ROUTES; i++) {
    mb_route *r = &routes[i];
    if (r->route == route && route) {
      r->used = ++routes_used;
      return r;
    }
    if (!r->route) {
      if (!empty) empty = r;
    } else if (!r->video && !r->audio && (!old || r->used < old->used)) {
      old = r;
    }
  }
  if (!make || !route) return NULL;
  mb_route *r = empty ?: old;
  if (r) *r = (mb_route){route, 0, ++routes_used, 0, 0};
  return r;
}

// Whether route's frames go to stream sid now.
static BOOL routed(uint64_t route, int32_t sid) {
  os_unfair_lock_lock(&routes_lock);
  mb_route *r = route_at(route, NO);
  BOOL on = r && r->video == sid;
  os_unfair_lock_unlock(&routes_lock);
  return on;
}

// (main thread) frame ts of route taken, as far as its sender is concerned
static void route_acked(uint64_t route, double ts) {
  if (route_ack) route_ack((double)route, ts);
}

void mb_stream_route_acks(int (*ack)(double route, double ts)) { route_ack = ack; }

// Frame ts let go (the stream's queue): one fed from a route acknowledged to its sender here, else said.
static void let_go(MBStream *s, double ts) {
  NSNumber *d = s.direct[@(ts)];
  if (d) {
    if (d.longValue >= 0) {
      s.direct[@(ts)] = @(-1);
      uint64_t route = s.directRoute;
      dispatch_async(dispatch_get_main_queue(), ^{ route_acked(route, ts); });
    }
    return;
  }
  say(s, [@"d " stringByAppendingString:num(ts)]);
}

static void show_frame(MBStream *s, MBStreamFrame *f);
static void unroute(int32_t sid, int what);
static void audio_stop(MBStream *s);

// A frame fed from a route decoded (main thread): shown and acknowledged here while the route still goes to it, nothing
// of the app's run; else said, as the app's are.
static void direct_shown(MBStream *s, MBStreamFrame *f, uint64_t route) {
  if (s.closed) return;
  if (!routed(route, s.sid)) {
    @synchronized(s) {
      [s.decoded addObject:f];
    }
    say(s, [NSString stringWithFormat:@"f %@ %d %d", num(f.ts), f.w, f.h]);
    return;
  }
  // (what the app said decoded before it and has not shown yet: passed over)
  @synchronized(s) {
    NSMutableArray *left = [NSMutableArray new];
    for (MBStreamFrame *g in s.decoded) {
      if (g.ts > f.ts) [left addObject:g];
    }
    s.decoded = left;
  }
  show_frame(s, f);
  s.directAt = f.ts;
  route_acked(route, f.ts);
}

// ---- H.264 (the stream's queue) ----

static void stop(MBStream *s);
static BOOL start(MBStream *s);

// the session's output, on VideoToolbox's thread: handed to the stream's queue
static void decoded(void *out_ref, void *frame_ref, OSStatus status, VTDecodeInfoFlags flags, CVImageBufferRef image,
                    CMTime pts, CMTime dur) {
  uint64_t key = (uint64_t)(uintptr_t)out_ref;
  int32_t sid = (int32_t)(key >> 32);
  uint32_t gen = (uint32_t)key;
  double ts;
  uint64_t bits = (uint64_t)(uintptr_t)frame_ref;
  memcpy(&ts, &bits, sizeof ts);
  if (image) CVPixelBufferRetain(image);
  // (to the stream's queue at once: not by way of the main thread, which has frames to draw)
  {
    MBStream *s = stream_of(sid);
    if (!s) {
      if (image) CVPixelBufferRelease(image);
      return;
    }
    dispatch_async(s.queue, ^{
      if (s.generation != gen || s.closed) {
        if (image) CVPixelBufferRelease(image);
        return;
      }
      if (status != noErr || !image) {
        if (image) CVPixelBufferRelease(image);
        [s.inside removeObject:@(ts)];
        if (flags & kVTDecodeInfo_FrameDropped) {
          let_go(s, ts);
          return;
        }
        NSLog(@"stream %d: the H.264 decoder failed (%d)", s.sid, (int)status);
        let_go(s, ts);
        // anew, from the next key frame
        if (start(s)) say(s, @"b");
        return;
      }
      while (s.inside.count > 0 && s.inside[0].doubleValue <= ts) [s.inside removeObjectAtIndex:0];
      MBStreamFrame *f = [MBStreamFrame new];
      f.ts = ts;
      f.w = (int)CVPixelBufferGetWidth(image);
      f.h = (int)CVPixelBufferGetHeight(image);
      f.pixels = image;
      // one fed from a route: shown there (none let go already); those before it are done with
      NSNumber *direct = s.direct[@(ts)];
      if (direct) {
        for (NSNumber *t in s.direct.allKeys) {
          if (t.doubleValue <= ts) [s.direct removeObjectForKey:t];
        }
        if (direct.longValue < 0) return;
        uint64_t route = s.directRoute;
        dispatch_async(dispatch_get_main_queue(), ^{ direct_shown(s, f, route); });
        return;
      }
      @synchronized(s) {
        [s.decoded addObject:f];
      }
      say(s, [NSString stringWithFormat:@"f %@ %d %d", num(ts), f.w, f.h]);
    });
  }
}

// What was inside the decoder let go (taken, as far as the sender is concerned), the session gone.
static void stop(MBStream *s) {
  if (s.session) {
    VTDecompressionSessionInvalidate(s.session);
    CFRelease(s.session);
    s.session = NULL;
  }
  s.generation++;
  // (the app's said let go up to the newest; a route's acknowledged)
  double max = -INFINITY, routed_max = -INFINITY;
  for (NSNumber *t in s.inside) {
    NSNumber *d = s.direct[t];
    if (!d) max = fmax(max, t.doubleValue);
    else if (d.longValue >= 0) routed_max = fmax(routed_max, t.doubleValue);
  }
  [s.inside removeAllObjects];
  [s.direct removeAllObjects];
  if (max != -INFINITY) say(s, [@"d " stringByAppendingString:num(max)]);
  if (routed_max != -INFINITY) {
    uint64_t route = s.directRoute;
    dispatch_async(dispatch_get_main_queue(), ^{ route_acked(route, routed_max); });
  }
  s.needKey = YES;
}

// A session for the config there is (none without one): whether there is one now.
static BOOL start(MBStream *s) {
  stop(s);
  if (!s.format || s.closed) return NO;
  NSDictionary *pixels = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
  };
  VTDecompressionOutputCallbackRecord cb = {decoded, (void *)(uintptr_t)(((uint64_t)(uint32_t)s.sid << 32) | s.generation)};
  VTDecompressionSessionRef made = NULL;
  OSStatus st = VTDecompressionSessionCreate(NULL, s.format, NULL, (__bridge CFDictionaryRef)pixels, &cb, &made);
  if (st != noErr || !made) {
    NSLog(@"stream %d: no H.264 decoder (%d)", s.sid, (int)st);
    return NO;
  }
  VTSessionSetProperty(made, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
  s.session = made;
  s.needKey = YES;
  return YES;
}

static void configure(MBStream *s, NSData *avcc, int w, int h) {
  mb_avc_config c;
  if (!mb_avc_parse(avcc.bytes, avcc.length, &c)) {
    NSLog(@"stream %d: an avcC that is not one (%lu bytes)", s.sid, (unsigned long)avcc.length);
    if (s.format) CFRelease(s.format);
    s.format = NULL;
    stop(s);
    return;
  }
  const uint8_t *sets[2 * MB_AVC_SETS];
  size_t sizes[2 * MB_AVC_SETS];
  int n = 0;
  for (int i = 0; i < c.nsps; i++, n++) { sets[n] = c.sps[i]; sizes[n] = c.sps_len[i]; }
  for (int i = 0; i < c.npps; i++, n++) { sets[n] = c.pps[i]; sizes[n] = c.pps_len[i]; }
  CMVideoFormatDescriptionRef f = NULL;
  OSStatus st = CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, (size_t)n, sets, sizes, c.length_size, &f);
  if (s.format) CFRelease(s.format);
  s.format = st == noErr ? f : NULL;
  if (st != noErr) NSLog(@"stream %d: parameter sets not taken (%d)", s.sid, (int)st);
  s.lengthSize = c.length_size;
  s.w = w;
  s.h = h;
  // the sender's next frame after a config is a key frame
  start(s);
}

// H.265: an hvcC's (ISO/IEC 14496-15 8.3.3) VPS, SPS and PPS, into a format as configure's (its access units are fed
// as H.264's are: each NAL after its length).
static void configure_hevc(MBStream *s, NSData *hvcc, int w, int h) {
  const uint8_t *b = hvcc.bytes;
  size_t n = hvcc.length;
  const uint8_t *sets[3 * MB_AVC_SETS];
  size_t sizes[3 * MB_AVC_SETS];
  int count = 0, length_size = 0, sound = n >= 23 && b[0] == 1;
  if (sound) length_size = (b[21] & 3) + 1;
  int arrays = sound ? b[22] : 0;
  size_t at = 23;
  for (int a = 0; sound && a < arrays; a++) {
    if (at + 3 > n) { sound = 0; break; }
    int type = b[at] & 0x3f, units = (b[at + 1] << 8) | b[at + 2];
    at += 3;
    for (int i = 0; sound && i < units; i++) {
      size_t len = at + 2 <= n ? (((size_t)b[at] << 8) | b[at + 1]) : 0;
      at += 2;
      if (len == 0 || at + len > n) { sound = 0; break; }
      if (type >= 32 && type <= 34) {
        if (count == 3 * MB_AVC_SETS) { sound = 0; break; }
        sets[count] = b + at;
        sizes[count++] = len;
      }
      at += len;
    }
  }
  CMVideoFormatDescriptionRef f = NULL;
  OSStatus st = sound && length_size != 3 && count >= 3
    ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(NULL, (size_t)count, sets, sizes, length_size, NULL, &f)
    : kCMFormatDescriptionError_InvalidParameter;
  if (s.format) CFRelease(s.format);
  s.format = st == noErr ? f : NULL;
  if (st != noErr) NSLog(@"stream %d: an hvcC not taken (%d, %lu bytes)", s.sid, (int)st, (unsigned long)n);
  s.lengthSize = length_size;
  s.w = w;
  s.h = h;
  if (s.format) start(s);
  else stop(s);
}

static void feed(MBStream *s, NSData *data, BOOL key, double ts) {
  if (!s.session || (s.needKey && !key)) {
    let_go(s, ts);
    return;
  }
  s.needKey = NO;
  if (mb_avc_annexb_size(data.bytes, data.length, s.lengthSize) < 0) {
    // not a frame it can take: the next key frame asked for
    let_go(s, ts);
    s.needKey = YES;
    say(s, @"b");
    return;
  }
  CMBlockBufferRef block = NULL;
  OSStatus st = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, data.length, NULL, NULL, 0, data.length,
                                                   kCMBlockBufferAssureMemoryNowFlag, &block);
  if (st == noErr) st = CMBlockBufferReplaceDataBytes(data.bytes, block, 0, data.length);
  CMSampleBufferRef sample = NULL;
  size_t size = data.length;
  CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMake((int64_t)ts, 1000), kCMTimeInvalid};
  if (st == noErr) st = CMSampleBufferCreateReady(NULL, block, s.format, 1, 1, &timing, 1, &size, &sample);
  if (block) CFRelease(block);
  if (st != noErr) {
    let_go(s, ts);
    return;
  }
  if (key) {
    CFArrayRef att = CMSampleBufferGetSampleAttachmentsArray(sample, YES);
    if (att && CFArrayGetCount(att) > 0) {
      CFMutableDictionaryRef d = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(att, 0);
      CFDictionarySetValue(d, kCMSampleAttachmentKey_NotSync, kCFBooleanFalse);
    }
  }
  [s.inside addObject:@(ts)];
  uint64_t bits;
  memcpy(&bits, &ts, sizeof bits);
  VTDecodeInfoFlags info = 0;
  st = VTDecompressionSessionDecodeFrame(s.session, sample,
                                         kVTDecodeFrame_EnableAsynchronousDecompression | kVTDecodeFrame_1xRealTimePlayback,
                                         (void *)(uintptr_t)bits, &info);
  CFRelease(sample);
  if (st != noErr) {
    // the session gone (iOS in the background invalidates it), or failed: anew, from the next key frame
    NSLog(@"stream %d: a frame not taken (%d)", s.sid, (int)st);
    if (start(s)) say(s, @"b");
    return;
  }
  // a decoder that holds frames back would wait for more while the sender waits for an acknowledgement: with two
  // inside, the older one counts as taken
  if (s.inside.count >= 2) {
    double old = s.inside[0].doubleValue;
    [s.inside removeObjectAtIndex:0];
    let_go(s, old);
  }
}

// ---- JPEG (the stream's JPEG queue) ----

static void jpeg(MBStream *s, NSData *data, double ts) {
  @autoreleasepool {
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef img = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
    if (src) CFRelease(src);
    if (!img) {
      say(s, [@"d " stringByAppendingString:num(ts)]);
      return;
    }
    int w = (int)CGImageGetWidth(img), h = (int)CGImageGetHeight(img);
    size_t bpr = (size_t)w * 4;
    void *px = calloc(bpr, (size_t)h);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(px, (size_t)w, (size_t)h, 8, bpr, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);
    CGImageRelease(img);
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                  width:(NSUInteger)w
                                                                                 height:(NSUInteger)h
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [mb_render_device() newTextureWithDescriptor:td];
    [tex replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)w, (NSUInteger)h) mipmapLevel:0 withBytes:px bytesPerRow:bpr];
    free(px);
    MBStreamFrame *f = [MBStreamFrame new];
    f.ts = ts;
    f.w = w;
    f.h = h;
    f.tex = tex;
    @synchronized(s) {
      if (s.closed) return;
      [s.decoded addObject:f];
    }
    say(s, [NSString stringWithFormat:@"f %@ %d %d", num(ts), w, h]);
  }
}

// ---- the host's calls (main thread) ----

int32_t mb_host_stream_open(void) {
  if (!streams) streams = [NSMutableDictionary new];
  MBStream *s = [MBStream new];
  s.sid = ++next_stream;
  s.queue = dispatch_queue_create("mbui.stream", DISPATCH_QUEUE_SERIAL);
  s.jpegQueue = dispatch_queue_create("mbui.stream.jpeg", DISPATCH_QUEUE_SERIAL);
  s.events = [NSMutableArray new];
  s.decoded = [NSMutableArray new];
  s.retired = [NSMutableArray new];
  s.inside = [NSMutableArray new];
  s.onLayer = [NSMutableArray new];
  s.audioQueue = dispatch_queue_create("mbui.stream.audio", DISPATCH_QUEUE_SERIAL);
  s.direct = [NSMutableDictionary new];
  s.directAt = s.directToldAt = -1;
  s.needKey = YES;
  if (!streams_lock) streams_lock = [NSLock new];
  [streams_lock lock];
  streams[@(s.sid)] = s;
  [streams_lock unlock];
  return s.sid;
}

void mb_host_stream_h264(int32_t sid, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  NSData *d = [NSData dataWithBytes:avcc length:(NSUInteger)Moonbit_array_length(avcc)];
  // (the frames after it the app's to show, whatever their times)
  s.directAt = -1;
  dispatch_async(s.queue, ^{ configure(s, d, w, h); });
}

void mb_host_stream_hevc(int32_t sid, moonbit_bytes_t hvcc, int32_t w, int32_t h) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  NSData *d = [NSData dataWithBytes:hvcc length:(NSUInteger)Moonbit_array_length(hvcc)];
  s.directAt = -1;
  dispatch_async(s.queue, ^{ configure_hevc(s, d, w, h); });
}

void mb_host_stream_frame(int32_t sid, moonbit_bytes_t data, int32_t key, double ts) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  NSData *d = [NSData dataWithBytes:data length:(NSUInteger)Moonbit_array_length(data)];
  dispatch_async(s.queue, ^{ feed(s, d, key != 0, ts); });
}

void mb_host_stream_jpeg(int32_t sid, moonbit_bytes_t data, double ts) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  NSData *d = [NSData dataWithBytes:data length:(NSUInteger)Moonbit_array_length(data)];
  dispatch_async(s.jpegQueue, ^{ jpeg(s, d, ts); });
}

moonbit_string_t mb_host_stream_next(int32_t sid) {
  MBStream *s = stream_of(sid);
  NSString *e = nil;
  if (s) {
    long frames = 0, bytes = 0;
    @synchronized(s) {
      if (s.events.count > 0) {
        e = s.events[0];
        [s.events removeObjectAtIndex:0];
      }
      frames = s.directFrames;
      bytes = s.directBytes;
    }
    // what came by its route since it was last told, after all else it said
    if (!e && (s.directAt != s.directToldAt || frames != s.directToldFrames)) {
      e = [NSString stringWithFormat:@"D %@ %ld %ld", num(s.directAt), frames - s.directToldFrames, bytes - s.directToldBytes];
      s.directToldAt = s.directAt;
      s.directToldFrames = frames;
      s.directToldBytes = bytes;
    }
  }
  return mb_string_from_ns(e ?: @"");
}

void mb_host_stream_show(int32_t sid, double ts) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  MBStreamFrame *f = nil;
  @synchronized(s) {
    // (one older than a frame of its route shown since: passed over)
    if (ts < s.directAt) {
      NSMutableArray *left = [NSMutableArray new];
      for (MBStreamFrame *g in s.decoded) {
        if (g.ts > ts) [left addObject:g];
      }
      s.decoded = left;
      return;
    }
    // it, and those decoded before it passed over
    NSUInteger at = NSNotFound;
    for (NSUInteger i = 0; i < s.decoded.count; i++) {
      if (s.decoded[i].ts == ts) at = i;
    }
    if (at == NSNotFound) return;
    f = s.decoded[at];
    NSMutableArray *left = [NSMutableArray new];
    for (MBStreamFrame *g in s.decoded) {
      if (g.ts > ts) [left addObject:g];
    }
    s.decoded = left;
  }
  show_frame(s, f);
}

// Frame f shown from now (main thread): on its system video layer and as its texture.
static void show_frame(MBStream *s, MBStreamFrame *f) {
  // on its system video layer (if it has one) as well: what shows there
  if (f.pixels) {
    if (s.displayed) CVPixelBufferRelease(s.displayed);
    s.displayed = CVPixelBufferRetain(f.pixels);
    display(s, f.pixels);
  }
  s.wide = nil;
  // Wider than sRGB: its texture (sRGB's, as the app draws) made only when drawn (mb_stream_texture).
  if (f.pixels && wider_than_srgb(f.pixels)) {
    s.wide = f;
    s.tex = nil;
    return;
  }
  use_texture(s, f.pixels, f.tex, f);
}

// Whether pixel buffer `px` is in wider colours than sRGB's: its primaries said and not BT.709's (sRGB's).
static BOOL wider_than_srgb(CVPixelBufferRef px) {
  CFTypeRef primaries = CVBufferCopyAttachment(px, kCVImageBufferColorPrimariesKey, NULL);
  BOOL is = primaries && !CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_709_2);
  if (primaries) CFRelease(primaries);
  return is;
}

// What the app draws stream s with from now on: pixel buffer `px`'s texture (BGRA, kept with `keep`), or `tex`.
static void use_texture(MBStream *s, CVPixelBufferRef px, id<MTLTexture> tex, id keep) {
  id held = nil;
  if (px) {
    if (!texture_cache && CVMetalTextureCacheCreate(NULL, NULL, mb_render_device(), NULL, &texture_cache) != kCVReturnSuccess) return;
    CVMetalTextureRef mt = NULL;
    if (CVMetalTextureCacheCreateTextureFromImage(NULL, texture_cache, px, NULL, MTLPixelFormatBGRA8Unorm,
                                                  CVPixelBufferGetWidth(px), CVPixelBufferGetHeight(px), 0, &mt) != kCVReturnSuccess || !mt) {
      return;
    }
    tex = CVMetalTextureGetTexture(mt);
    // (the CVMetalTexture and its pixel buffer kept as long as the texture is drawn)
    held = @[ (__bridge_transfer id)mt, keep ];
  }
  if (!tex) return;
  // what was drawn until now, kept while the frames in flight may draw it (at most three: apple_render.m's ring)
  [s.retired addObject:(held ?: (id)tex)];
  while (s.retired.count > 4) [s.retired removeObjectAtIndex:0];
  s.tex = tex;
  if (texture_cache) CVMetalTextureCacheFlush(texture_cache, 0);
}

// A wide frame's texture in sRGB (the app's canvas is sRGB: P3's numbers drawn as they are would come out washed
// out): converted by VideoToolbox's pixel transfer into a buffer of its own, once, when the app draws it.
static void texture_in_srgb(MBStream *s) {
  MBStreamFrame *f = s.wide;
  s.wide = nil;
  int w = (int)CVPixelBufferGetWidth(f.pixels), h = (int)CVPixelBufferGetHeight(f.pixels);
  if (!s.toSRGB) {
    VTPixelTransferSessionRef made = NULL;
    if (VTPixelTransferSessionCreate(NULL, &made) != noErr || !made) return;
    VTSessionSetProperty(made, kVTPixelTransferPropertyKey_DestinationColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2);
    VTSessionSetProperty(made, kVTPixelTransferPropertyKey_DestinationTransferFunction, kCVImageBufferTransferFunction_sRGB);
    s.toSRGB = made;
  }
  if (!s.srgbPool || s.srgbW != w || s.srgbH != h) {
    if (s.srgbPool) CVPixelBufferPoolRelease(s.srgbPool);
    s.srgbPool = NULL;
    NSDictionary *attrs = @{
      (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
      (id)kCVPixelBufferWidthKey : @(w),
      (id)kCVPixelBufferHeightKey : @(h),
      (id)kCVPixelBufferMetalCompatibilityKey : @YES,
      (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
    };
    CVPixelBufferPoolRef pool = NULL;
    if (CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)attrs, &pool) != kCVReturnSuccess) return;
    s.srgbPool = pool;
    s.srgbW = w;
    s.srgbH = h;
  }
  CVPixelBufferRef out = NULL;
  if (CVPixelBufferPoolCreatePixelBuffer(NULL, s.srgbPool, &out) != kCVReturnSuccess || !out) return;
  if (VTPixelTransferSessionTransferImage(s.toSRGB, f.pixels, out) == noErr) use_texture(s, out, nil, (__bridge id)out);
  CVPixelBufferRelease(out);
}

// Pixel buffer `px` put on the stream's layer: its IOSurface the layer's contents, in the transaction the frame that
// shows it puts the layer where it goes in (the canvas's hole with it: one refresh, never the new picture where the old
// was), or one of its own between frames. Kept with the last few shown, so their surfaces are not decoded into again
// while the screen may still show them.
static void display(MBStream *s, CVPixelBufferRef px) {
  CALayer *layer = s.display;
  if (!layer || !px) return;
  IOSurfaceRef surface = CVPixelBufferGetIOSurface(px);
  if (!surface) return;
  // (shown in its own colours, a P3 stream's wider than sRGB's: Core Animation matches the surface's colour space,
  // which VideoToolbox's decoded buffer carries from the stream's VUI, Display P3's ICC profile for a P3 stream)
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.contents = (__bridge id)surface;
  [CATransaction commit];
  [s.onLayer addObject:(__bridge id)px];
  while (s.onLayer.count > 3) [s.onLayer removeObjectAtIndex:0];
}

static void pointer_put(MBStream *s);

void mb_stream_attach_layer(int sid, CALayer *layer) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  s.display = layer;
  s.placedW = 0;
  s.placedH = 0;
  pointer_put(s);
  // (what it shows already, at once: not black until the next frame)
  if (s.display && s.displayed) display(s, s.displayed);
}

// A system video layer here (apple_views.m's views of kind 4): what a stream shows put there, nothing drawn of it.
int32_t mb_host_stream_layers(void) { return 1; }

void mb_host_stream_close(int32_t sid) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  @synchronized(s) {
    s.closed = YES;
    [s.events removeAllObjects];
    [s.decoded removeAllObjects];
  }
  unroute(sid, 3);
  dispatch_async(s.audioQueue, ^{ audio_stop(s); });
  s.display = nil;
  pointer_put(s);
  if (s.displayed) CVPixelBufferRelease(s.displayed);
  s.displayed = NULL;
  [s.onLayer removeAllObjects];
  s.wide = nil;
  if (s.toSRGB) {
    VTPixelTransferSessionInvalidate(s.toSRGB);
    CFRelease(s.toSRGB);
    s.toSRGB = NULL;
  }
  if (s.srgbPool) CVPixelBufferPoolRelease(s.srgbPool);
  s.srgbPool = NULL;
  [streams_lock lock];
  [streams removeObjectForKey:@(sid)];
  [streams_lock unlock];
  dispatch_async(s.queue, ^{
    stop(s);
    if (s.format) CFRelease(s.format);
    s.format = NULL;
  });
}

// ---- its pointer (main thread) ----

// The pointer's sublayer where the stream's layer is (none without one), its picture, at its place: its hot spot at
// (x, y) of the layer's bounds, its size its own whatever the picture's. In a transaction of its own unless one is
// open (the frame's that places the layer: mb_stream_layout), never animated.
static void pointer_put(MBStream *s) {
  CALayer *display = s.display;
  if (!display || !s.pointerImage) {
    [s.pointer removeFromSuperlayer];
    return;
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (!s.pointer) {
    CALayer *l = [CALayer layer];
    l.contentsGravity = kCAGravityResize;
    l.anchorPoint = CGPointZero;
    // over the picture whatever it is given after (its contents are its own)
    l.zPosition = 1;
    s.pointer = l;
  }
  CALayer *l = s.pointer;
  if (l.superlayer != display) [display addSublayer:l];
  if (l.contents != s.pointerImage) {
    l.contents = s.pointerImage;
    size_t pw = CGImageGetWidth((__bridge CGImageRef)s.pointerImage);
    if (s.pointerW > 0 && pw > 0) l.contentsScale = (double)pw / s.pointerW;
  }
  CGRect b = display.bounds;
  if (s.placedW > 0 && s.placedH > 0) b = CGRectMake(0, 0, s.placedW, s.placedH);
  l.bounds = CGRectMake(0, 0, s.pointerW, s.pointerH);
  double top = s.pointerY * b.size.height - s.pointerHy;
#if TARGET_OS_OSX
  // (a Mac's layers count up from their foot unless flipped on the way down to this one: AppKit's flipped view
  // places its own sublayers, not ours)
  BOOL down = NO;
  for (CALayer *k = display; k; k = k.superlayer) down ^= k.geometryFlipped;
  if (!down) top = b.size.height - top - s.pointerH;
#endif
  l.position = CGPointMake(b.origin.x + s.pointerX * b.size.width - s.pointerHx, b.origin.y + top);
  l.hidden = !s.pointerShown;
  [CATransaction commit];
}

void mb_host_stream_pointer(int32_t sid, moonbit_bytes_t png, double w, double h, double hx, double hy) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  CGImageRef img = NULL;
  NSUInteger n = (NSUInteger)Moonbit_array_length(png);
  if (n > 0) {
    NSData *d = [NSData dataWithBytes:png length:n];
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)d, NULL);
    if (src) {
      img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
      CFRelease(src);
    }
  }
  s.pointerImage = img ? (__bridge_transfer id)img : nil;
  s.pointerW = w;
  s.pointerH = h;
  s.pointerHx = hx;
  s.pointerHy = hy;
  pointer_put(s);
}

void mb_host_stream_pointer_at(int32_t sid, double x, double y, int32_t shown) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  s.pointerX = x;
  s.pointerY = y;
  s.pointerShown = shown != 0;
  pointer_put(s);
}

// Stream sid's layer placed anew (apple_views.m, in the frame's transaction): its pointer where it points on it.
void mb_stream_layout(int sid, double w, double h) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  s.placedW = w;
  s.placedH = h;
  if (s.pointer) pointer_put(s);
}

// VideoToolbox decodes H.264 on every Mac and iPhone (in hardware, else in software).
int32_t mb_host_h264_here(void) { return 1; }

// H.265 where this Mac or iPhone decodes it on its hardware (every Apple silicon Mac, iPhone 7 and later).
int32_t mb_host_h265_here(void) { return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) ? 1 : 0; }

// (VideoToolbox decodes here by itself, frame for frame: nothing for the framework to drive, @hostapi.stream_feeds)
int32_t mb_host_stream_feeds(void) { return 0; }
void mb_host_stream_codec(int32_t sid, moonbit_string_t cmd, moonbit_bytes_t data) {}

id<MTLTexture> mb_stream_texture(int sid) {
  MBStream *s = stream_of(sid);
  if (s && s.wide) texture_in_srgb(s);
  return s ? s.tex : nil;
}

// Audio belongs to the stream, not to its video decoder: changing picture size does not interrupt sound. Played on the
// stream's audio queue, the app's packets and its route's alike.
int32_t mb_host_stream_audio_here(void) { return 1; }

// (its audio queue) what is queued let go, the player stopped
static void audio_stop(MBStream *s) {
  [s.audioPlayer stop];
  [s.audioEngine stop];
  s.audioGeneration++;
  s.audioQueued = 0;
}

// (its audio queue) one 20 ms packet played after those queued
static void audio_play(MBStream *s, NSData *data) {
  if (s.closed || data.length != 3840) return;
  const uint8_t *bytes = data.bytes;
  AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
  if (!s.audioEngine) {
    s.audioEngine = [AVAudioEngine new];
    s.audioPlayer = [AVAudioPlayerNode new];
    [s.audioEngine attachNode:s.audioPlayer];
    [s.audioEngine connect:s.audioPlayer to:s.audioEngine.mainMixerNode format:format];
  }
  if (!s.audioEngine.running) {
    [s.audioPlayer stop];
    s.audioGeneration++;
    s.audioQueued = 0;
#if TARGET_OS_IPHONE
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *sessionError = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&sessionError] ||
        ![session setActive:YES error:&sessionError]) return;
#endif
    NSError *error = nil;
    if (![s.audioEngine startAndReturnError:&error]) return;
  }
  // Keep 60 ms of startup jitter reserve, at most 300 ms after a transport stall.
  if (s.audioQueued >= 15) {
    [s.audioPlayer stop];
    s.audioGeneration++;
    s.audioQueued = 0;
  }
  AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:960];
  if (!buffer) return;
  buffer.frameLength = 960;
  float *left = buffer.floatChannelData[0], *right = buffer.floatChannelData[1];
  for (NSUInteger frame = 0; frame < 960; frame++) {
    const uint8_t *p = bytes + frame * 4;
    left[frame] = (float)(int16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8)) / 32768.0f;
    right[frame] = (float)(int16_t)((uint16_t)p[2] | ((uint16_t)p[3] << 8)) / 32768.0f;
  }
  NSUInteger generation = s.audioGeneration;
  s.audioQueued++;
  __weak MBStream *weak = s;
  dispatch_queue_t queue = s.audioQueue;
  [s.audioPlayer scheduleBuffer:buffer completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type) {
    dispatch_async(queue, ^{
      MBStream *live = weak;
      if (live && live.audioGeneration == generation && live.audioQueued > 0) {
        live.audioQueued--;
        // An underrun must refill the same reserve before starting again.
        if (live.audioQueued == 0) [live.audioPlayer stop];
      }
    });
  }];
  if (!s.audioPlayer.playing && s.audioQueued >= 3) [s.audioPlayer play];
}

void mb_host_stream_audio(int32_t sid, moonbit_bytes_t data) {
  MBStream *s = stream_of(sid);
  if (!s || s.closed) return;
  NSUInteger length = (NSUInteger)Moonbit_array_length(data);
  if (length == 0) {
    // (stopped: what its route plays stops with it, until the app routes it again)
    unroute(sid, 2);
    dispatch_async(s.audioQueue, ^{ audio_stop(s); });
    return;
  }
  if (length != 3840) return;
  NSData *d = [NSData dataWithBytes:data length:length];
  dispatch_async(s.audioQueue, ^{ audio_play(s, d); });
}

// ---- routes (an engine's thread; the app's calls on the main thread) ----

// Stream sid no longer where a route's frames (`what` 1) or sound (2) go.
static void unroute(int32_t sid, int what) {
  os_unfair_lock_lock(&routes_lock);
  for (int i = 0; i < MB_ROUTES; i++) {
    if ((what & 1) && routes[i].video == sid) routes[i].video = 0;
    if ((what & 2) && routes[i].audio == sid) routes[i].audio = 0;
  }
  os_unfair_lock_unlock(&routes_lock);
}

int mb_stream_route_take(uint64_t route, int kind, int key, uint64_t seq, uint64_t ts, const uint8_t *bytes, size_t len) {
  int32_t sid = 0;
  os_unfair_lock_lock(&routes_lock);
  mb_route *r = route_at(route, YES);
  if (r) {
    r->seq = seq;
    // (a config: the app's to take, and what follows it, until it routes them again)
    if (kind == 1) r->video = 0;
    else if (kind == 5) r->audio = 0;
    else if (kind == 2) sid = r->video;
    else if (kind == 6 && len == 3840) sid = r->audio;
  }
  os_unfair_lock_unlock(&routes_lock);
  if (!sid) return 0;
  @autoreleasepool {
    MBStream *s = stream_of(sid);
    if (!s || s.closed) return 0;
    NSData *d = [[NSData alloc] initWithBytes:bytes length:len];
    if (kind == 6) {
      dispatch_async(s.audioQueue, ^{ audio_play(s, d); });
      return 1;
    }
    @synchronized(s) {
      s.directFrames += 1;
      s.directBytes += (long)len;
    }
    double t = (double)ts;
    BOOL k = key != 0;
    dispatch_async(s.queue, ^{
      if (s.closed) {
        // (closed meanwhile: taken, as far as its sender is concerned)
        dispatch_async(dispatch_get_main_queue(), ^{ route_acked(route, t); });
        return;
      }
      s.directRoute = route;
      s.direct[@(t)] = @((long)d.length);
      feed(s, d, k, t);
    });
  }
  return 1;
}

// The app's (main thread): stream sid takes route's frames (`what` 1) and sound (2) from now, where the last record
// offered by it is the `after`th (nothing of it left in the app's queue); those not asked no longer.
void mb_host_stream_direct(int32_t sid, double route, double after, int32_t what) {
  unroute(sid, ~what & 3);
  if (!(what & 3) || route < 1) return;
  os_unfair_lock_lock(&routes_lock);
  mb_route *r = route_at((uint64_t)route, NO);
  if (r && (double)r->seq == after) {
    if (what & 1) r->video = sid;
    if (what & 2) r->audio = sid;
  }
  os_unfair_lock_unlock(&routes_lock);
}
