// Streams on macOS and iOS (src/host/stream.mbt, @ui's Stream): a picture decoded frame by frame, drawn by the app as
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
// a frame. The session's work runs on the stream's own serial queue; its output comes back to it.
#import "apple.h"
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#include "avc.h"

// (linked wherever this is, whatever the app's own link flags say)
__asm__(".linker_option \"-framework\", \"VideoToolbox\"");
__asm__(".linker_option \"-framework\", \"CoreMedia\"");
__asm__(".linker_option \"-framework\", \"CoreVideo\"");

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
// the decoder (its queue): the config's format, its NAL length size and picture size, the session and its generation
// (the output of an older one is not this one's), whether it waits for a key frame, the frames inside it
@property CMVideoFormatDescriptionRef format;
@property int lengthSize, w, h;
@property VTDecompressionSessionRef session;
@property uint32_t generation;
@property BOOL needKey, closed;
@property NSMutableArray<NSNumber *> *inside;
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

static void say(MBStream *s, NSString *e) {
  @synchronized(s) {
    if (s.closed) return;
    [s.events addObject:e];
  }
  dispatch_async(dispatch_get_main_queue(), ^{ mb_host_request_frame(); });
}

static MBStream *stream_of(int32_t sid) { return streams[@(sid)]; }

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
  dispatch_async(dispatch_get_main_queue(), ^{
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
          say(s, [@"d " stringByAppendingString:num(ts)]);
          return;
        }
        NSLog(@"stream %d: the H.264 decoder failed (%d)", s.sid, (int)status);
        say(s, [@"d " stringByAppendingString:num(ts)]);
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
      @synchronized(s) {
        [s.decoded addObject:f];
      }
      say(s, [NSString stringWithFormat:@"f %@ %d %d", num(ts), f.w, f.h]);
    });
  });
}

// What was inside the decoder let go (taken, as far as the sender is concerned), the session gone.
static void stop(MBStream *s) {
  if (s.session) {
    VTDecompressionSessionInvalidate(s.session);
    CFRelease(s.session);
    s.session = NULL;
  }
  s.generation++;
  double max = -INFINITY;
  for (NSNumber *t in s.inside) max = fmax(max, t.doubleValue);
  [s.inside removeAllObjects];
  if (max != -INFINITY) say(s, [@"d " stringByAppendingString:num(max)]);
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

static void feed(MBStream *s, NSData *data, BOOL key, double ts) {
  if (!s.session || (s.needKey && !key)) {
    say(s, [@"d " stringByAppendingString:num(ts)]);
    return;
  }
  s.needKey = NO;
  if (mb_avc_annexb_size(data.bytes, data.length, s.lengthSize) < 0) {
    // not a frame it can take: the next key frame asked for
    say(s, [@"d " stringByAppendingString:num(ts)]);
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
    say(s, [@"d " stringByAppendingString:num(ts)]);
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
    say(s, [@"d " stringByAppendingString:num(old)]);
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
  s.needKey = YES;
  streams[@(s.sid)] = s;
  return s.sid;
}

void mb_host_stream_h264(int32_t sid, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  NSData *d = [NSData dataWithBytes:avcc length:(NSUInteger)Moonbit_array_length(avcc)];
  dispatch_async(s.queue, ^{ configure(s, d, w, h); });
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
    @synchronized(s) {
      if (s.events.count > 0) {
        e = s.events[0];
        [s.events removeObjectAtIndex:0];
      }
    }
  }
  return mb_string_from_ns(e ?: @"");
}

void mb_host_stream_show(int32_t sid, double ts) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  MBStreamFrame *f = nil;
  @synchronized(s) {
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
  id held = nil;
  id<MTLTexture> tex = f.tex;
  if (f.pixels) {
    if (!texture_cache && CVMetalTextureCacheCreate(NULL, NULL, mb_render_device(), NULL, &texture_cache) != kCVReturnSuccess) return;
    CVMetalTextureRef mt = NULL;
    if (CVMetalTextureCacheCreateTextureFromImage(NULL, texture_cache, f.pixels, NULL, MTLPixelFormatBGRA8Unorm,
                                                  (size_t)f.w, (size_t)f.h, 0, &mt) != kCVReturnSuccess || !mt) {
      return;
    }
    tex = CVMetalTextureGetTexture(mt);
    // (the CVMetalTexture and its pixel buffer kept as long as the texture is drawn)
    held = @[ (__bridge_transfer id)mt, f ];
  }
  if (!tex) return;
  // what was drawn until now, kept while the frames in flight may draw it (at most three: apple_render.m's ring)
  [s.retired addObject:(held ?: (id)tex)];
  while (s.retired.count > 4) [s.retired removeObjectAtIndex:0];
  s.tex = tex;
  if (texture_cache) CVMetalTextureCacheFlush(texture_cache, 0);
}

void mb_host_stream_close(int32_t sid) {
  MBStream *s = stream_of(sid);
  if (!s) return;
  @synchronized(s) {
    s.closed = YES;
    [s.events removeAllObjects];
    [s.decoded removeAllObjects];
  }
  [streams removeObjectForKey:@(sid)];
  dispatch_async(s.queue, ^{
    stop(s);
    if (s.format) CFRelease(s.format);
    s.format = NULL;
  });
}

// VideoToolbox decodes H.264 on every Mac and iPhone (in hardware, else in software).
int32_t mb_host_h264_here(void) { return 1; }

id<MTLTexture> mb_stream_texture(int sid) {
  MBStream *s = stream_of(sid);
  return s ? s.tex : nil;
}
