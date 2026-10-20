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
    mb_host_outside(MB_OUTSIDE_IMAGE, iid, state);
    mb_host_request_frame();
  });
}

// A premultiplied RGBA bitmap (sRGB) of w by h to draw an image into; its
// pixels in *px, for finish_rgba.
static CGContextRef rgba_context(int w, int h, void **px) {
  size_t bpr = (size_t)w * 4;
  *px = calloc(bpr, h);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = CGBitmapContextCreate(*px, w, h, 8, bpr, cs,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(cs);
  return ctx;
}

// The bitmap drawn (rgba_context's pixels, freed here) as the image's
// texture: the image ready.
static void finish_rgba(int iid, void *px, int w, int h, int ow, int oh) {
  size_t bpr = (size_t)w * 4;
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
  td.usage = MTLTextureUsageShaderRead;
  id<MTLTexture> tex = [mb_render_device() newTextureWithDescriptor:td];
  [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:px bytesPerRow:bpr];
  free(px);
  finish(iid, 1, w, h, ow, oh, tex);
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
  void *px;
  CGContextRef ctx = rgba_context(w, h, &px);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
  CGContextRelease(ctx);
  CGImageRelease(img);
  finish_rgba(iid, px, w, h, ow, oh);
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

// ---------------------------------------------------------------------------
// PDFs (host_native.mbt's pdf_*): Core Graphics' CGPDF, a page drawn on white
// off the main thread into an image of the table above (image_info,
// image_free and the renderer's textures take it as any other).

@interface MBPdf : NSObject
@property(nonatomic) CGPDFDocumentRef doc; // NULL: the bytes were no PDF it could open
@end
@implementation MBPdf
- (void)dealloc {
  if (_doc) CGPDFDocumentRelease(_doc);
}
@end

static NSMutableDictionary<NSNumber *, MBPdf *> *pdfs;
static int next_pdf;

int32_t mb_host_pdf_open(moonbit_bytes_t data) {
  if (!pdfs) pdfs = [NSMutableDictionary new];
  NSData *d = [NSData dataWithBytes:data length:Moonbit_array_length(data)];
  CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)d);
  MBPdf *p = [MBPdf new];
  p.doc = prov ? CGPDFDocumentCreateWithProvider(prov) : NULL;
  if (prov) CGDataProviderRelease(prov);
  // encrypted with an empty password (only printing, copying forbidden): opened
  if (p.doc && CGPDFDocumentIsEncrypted(p.doc) && !CGPDFDocumentIsUnlocked(p.doc))
    CGPDFDocumentUnlockWithPassword(p.doc, "");
  if (p.doc && !CGPDFDocumentIsUnlocked(p.doc)) {
    CGPDFDocumentRelease(p.doc);
    p.doc = NULL;
  }
  int32_t id = ++next_pdf;
  pdfs[@(id)] = p;
  return id;
}

int32_t mb_host_pdf_pages(int32_t doc) {
  MBPdf *p = pdfs[@(doc)];
  return p.doc ? (int32_t)CGPDFDocumentGetNumberOfPages(p.doc) : -1;
}

// the page's crop box and its rotation (0, 90, 180, 270: clockwise); NULL past the pages
static CGPDFPageRef pdf_page(MBPdf *p, int page, CGRect *box, int *rot) {
  if (!p.doc || page < 0 || page >= (int)CGPDFDocumentGetNumberOfPages(p.doc)) return NULL;
  CGPDFPageRef pg = CGPDFDocumentGetPage(p.doc, page + 1);
  if (!pg) return NULL;
  *box = CGPDFPageGetBoxRect(pg, kCGPDFCropBox);
  *rot = ((CGPDFPageGetRotationAngle(pg) % 360) + 360) % 360;
  return pg;
}

void mb_host_pdf_page_size(int32_t doc, int32_t page, double *out) {
  out[0] = 0;
  out[1] = 0;
  MBPdf *p = pdfs[@(doc)];
  CGRect box;
  int rot;
  @synchronized(p) {
    if (!pdf_page(p, page, &box, &rot)) return;
  }
  BOOL turned = rot == 90 || rot == 270;
  out[0] = turned ? box.size.height : box.size.width;
  out[1] = turned ? box.size.width : box.size.height;
}

int32_t mb_host_pdf_page_load(int32_t doc, int32_t page, int32_t max_px) {
  MBPdf *p = pdfs[@(doc)];
  int lim = max_px > 0 ? (max_px < 8192 ? max_px : 8192) : 1024;
  return start(^(int iid) {
    // one page at a time of a document (CGPDF is not drawn from two threads at once)
    @synchronized(p) {
      CGRect box;
      int rot;
      CGPDFPageRef pg = pdf_page(p, page, &box, &rot);
      if (!pg || box.size.width <= 0 || box.size.height <= 0) {
        finish(iid, -1, 0, 0, 0, 0, nil);
        return;
      }
      BOOL turned = rot == 90 || rot == 270;
      double pw = turned ? box.size.height : box.size.width;
      double ph = turned ? box.size.width : box.size.height;
      double scale = lim / fmax(pw, ph);
      int w = (int)fmax(1, round(pw * scale)), h = (int)fmax(1, round(ph * scale));
      void *px;
      CGContextRef ctx = rgba_context(w, h, &px);
      CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
      CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
      CGContextScaleCTM(ctx, (double)w / pw, (double)h / ph);
      // the box turned as the page is shown (y up): (u, v) from its corner
      double bw = box.size.width, bh = box.size.height;
      CGAffineTransform t = rot == 90    ? CGAffineTransformMake(0, -1, 1, 0, 0, bw)
                            : rot == 180 ? CGAffineTransformMake(-1, 0, 0, -1, bw, bh)
                            : rot == 270 ? CGAffineTransformMake(0, 1, -1, 0, bh, 0)
                                         : CGAffineTransformIdentity;
      CGContextConcatCTM(ctx, t);
      CGContextTranslateCTM(ctx, -box.origin.x, -box.origin.y);
      CGContextClipToRect(ctx, box);
      CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
      CGContextSetRenderingIntent(ctx, kCGRenderingIntentDefault);
      CGContextDrawPDFPage(ctx, pg);
      CGContextRelease(ctx);
      finish_rgba(iid, px, w, h, (int)round(pw), (int)round(ph));
    }
  });
}

void mb_host_pdf_close(int32_t doc) { [pdfs removeObjectForKey:@(doc)]; }
