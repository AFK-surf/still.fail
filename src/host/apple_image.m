// Images on macOS and iOS: ImageIO decodes on a background queue straight
// to the size asked for (its thumbnail path reads JPEG and HEIC at reduced
// resolution, and applies the EXIF orientation), into a premultiplied RGBA
// Metal texture the renderer draws.
#import "apple.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

void mb_host_request_frame(void);

@interface MBImage : NSObject
@property int state; // 0 decoding, 1 ready, -1 failed
@property int w, h, ow, oh;
@property id<MTLTexture> tex;
@end
@implementation MBImage
@end

static NSMutableDictionary<NSNumber *, MBImage *> *images;
static int next_id;
static dispatch_queue_t decode_q;
// at most this many decodes at once, so a grid scrolled fast doesn't start
// a hundred and keep every core busy with ones already off screen
static dispatch_semaphore_t decode_slots;

static void setup(void) {
  if (images) return;
  images = [NSMutableDictionary new];
  decode_q = dispatch_queue_create("mbui.images", DISPATCH_QUEUE_CONCURRENT);
  decode_slots = dispatch_semaphore_create(3);
}

static void finish(int iid, int state, int w, int h, int ow, int oh, id<MTLTexture> tex) {
  dispatch_async(dispatch_get_main_queue(), ^{
    MBImage *im = images[@(iid)];
    if (!im) return; // freed meanwhile
    im.w = w; im.h = h; im.ow = ow; im.oh = oh;
    im.tex = tex;
    im.state = state;
    mb_host_request_frame();
  });
}

static void decode(int iid, CGImageSourceRef src, int max_px) {
  if (!src) {
    finish(iid, -1, 0, 0, 0, 0, nil);
    return;
  }
  int ow = 0, oh = 0;
  CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
  if (props) {
    NSDictionary *p = (__bridge NSDictionary *)props;
    ow = [p[(id)kCGImagePropertyPixelWidth] intValue];
    oh = [p[(id)kCGImagePropertyPixelHeight] intValue];
    int orient = [p[(id)kCGImagePropertyOrientation] intValue];
    if (orient >= 5 && orient <= 8) { int t = ow; ow = oh; oh = t; }
    CFRelease(props);
  }
  NSDictionary *opt = @{
    (id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (id)kCGImageSourceShouldCacheImmediately : @YES,
    (id)kCGImageSourceThumbnailMaxPixelSize : @(max_px),
  };
  CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
  CFRelease(src);
  if (!img) {
    finish(iid, -1, 0, 0, 0, 0, nil);
    return;
  }
  int w = (int)CGImageGetWidth(img), h = (int)CGImageGetHeight(img);
  if (ow == 0) { ow = w; oh = h; }
  size_t bpr = (size_t)w * 4;
  void *px = calloc(bpr, h);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, bpr, cs,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  CGImageRelease(img);
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
  td.usage = MTLTextureUsageShaderRead;
  id<MTLTexture> tex = [mb_render_device() newTextureWithDescriptor:td];
  [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:px bytesPerRow:bpr];
  free(px);
  finish(iid, 1, w, h, ow, oh, tex);
}

static int start(void (^load)(int iid)) {
  setup();
  int iid = ++next_id;
  MBImage *im = [MBImage new];
  images[@(iid)] = im;
  dispatch_async(decode_q, ^{
    dispatch_semaphore_wait(decode_slots, DISPATCH_TIME_FOREVER);
    @autoreleasepool { load(iid); }
    dispatch_semaphore_signal(decode_slots);
  });
  return iid;
}

int32_t mb_host_image_load(moonbit_string_t s, int32_t max_px) {
  NSString *src = mb_ns_from_string(s);
  if ([src hasPrefix:@"http://"] || [src hasPrefix:@"https://"]) {
    NSURL *url = [NSURL URLWithString:src];
    setup();
    int iid = ++next_id;
    images[@(iid)] = [MBImage new];
    [[[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
          dispatch_async(decode_q, ^{
            dispatch_semaphore_wait(decode_slots, DISPATCH_TIME_FOREVER);
            @autoreleasepool {
              decode(iid, data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL, max_px);
            }
            dispatch_semaphore_signal(decode_slots);
          });
        }] resume];
    return iid;
  }
  NSURL *url = [src hasPrefix:@"file://"] ? [NSURL URLWithString:src] : [NSURL fileURLWithPath:src];
  return start(^(int iid) {
    decode(iid, CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL), max_px);
  });
}

int32_t mb_host_image_load_bytes(moonbit_bytes_t data, int32_t max_px) {
  NSData *d = [NSData dataWithBytes:data length:Moonbit_array_length(data)];
  return start(^(int iid) {
    decode(iid, CGImageSourceCreateWithData((__bridge CFDataRef)d, NULL), max_px);
  });
}

int32_t mb_host_image_info(int32_t iid, double *out) {
  MBImage *im = images[@(iid)];
  if (!im) return -1;
  if (im.state == 1) {
    out[0] = im.w; out[1] = im.h; out[2] = im.ow; out[3] = im.oh;
  }
  return im.state;
}

void mb_host_image_free(int32_t iid) { [images removeObjectForKey:@(iid)]; }

id<MTLTexture> mb_image_texture(int iid) {
  MBImage *im = images[@(iid)];
  return im.state == 1 ? im.tex : nil;
}
