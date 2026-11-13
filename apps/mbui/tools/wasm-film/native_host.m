// Node host for mbui's Core Text, image decoder, Metal offscreen renderer and film writer. No browser or window.
#import <Cocoa/Cocoa.h>
#include <node_api.h>
#include <stdlib.h>
#include <string.h>
#include "../../../../libs/mbui/src/host/apple_text.m"
#include "../../../../libs/mbui/src/host/apple_image.m"
#include "../../../../libs/mbui/src/host/apple_film.m"

void mb_host_outside(int32_t kind, int32_t image, int32_t state) { (void)kind; (void)image; (void)state; }
void mb_host_request_frame(void) { }
id<MTLTexture> mb_stream_texture(int id_) { (void)id_; return nil; }
int mb_views_count(void) { return 0; }
void mb_views_draw_under(CGContextRef ctx, double scale) { (void)ctx; (void)scale; }
int mb_views_take_moved(void) { return 0; }
int mb_views_frost(int n, const double *frosts) { (void)n; (void)frosts; return 0; }
CTFontRef mb_platform_font(double size, int weight, int mono) {
  NSFontWeight w = weight >= 700 ? NSFontWeightBold : weight >= 600 ? NSFontWeightSemibold :
      weight >= 500 ? NSFontWeightMedium : NSFontWeightRegular;
  NSFont *f = mono ? [NSFont monospacedSystemFontOfSize:size weight:w] : [NSFont systemFontOfSize:size weight:w];
  return (CTFontRef)CFBridgingRetain(f);
}

void mb_render_init_offscreen(double w, double h, double scale);
int mb_render_snapshot_transparent(const char *path);
void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out);
void mb_host_render_dirty(double x, double y, double w, double h);

static double number(napi_env env, napi_value v) { double d = 0; napi_get_value_double(env, v, &d); return d; }
static napi_value integer(napi_env env, int n) { napi_value v; napi_create_int32(env, n, &v); return v; }
static napi_value undefined(napi_env env) { napi_value v; napi_get_undefined(env, &v); return v; }
static napi_value doubles(napi_env env, const double *values, size_t len) {
  void *data = NULL;
  napi_value buffer, result;
  napi_create_arraybuffer(env, len * sizeof(double), &data, &buffer);
  if (len) memcpy(data, values, len * sizeof(double));
  napi_create_typedarray(env, napi_float64_array, len, buffer, 0, &result);
  return result;
}
static void args(napi_env env, napi_callback_info info, size_t n, napi_value *out) {
  napi_get_cb_info(env, info, &n, out, NULL, NULL);
}

static napi_value init(napi_env env, napi_callback_info info) {
  napi_value a[3]; args(env, info, 3, a);
  mb_render_init_offscreen(number(env, a[0]), number(env, a[1]), number(env, a[2]));
  return undefined(env);
}
static napi_value view(napi_env env, napi_callback_info info) {
  napi_value a[3]; args(env, info, 3, a);
  double scale = number(env, a[2]);
  mb_text_set_scale(scale);
  mb_render_set_size(number(env, a[0]), number(env, a[1]), scale);
  return undefined(env);
}
static napi_value face(napi_env env, napi_callback_info info) {
  napi_value a[3]; args(env, info, 3, a);
  int face_id = (int)number(env, a[0]);
  int weight = (int)number(env, a[2]);
  if (face_id <= 0 || face_id >= MB_FACES) return integer(env, 0);
  void *bytes; size_t len;
  if (napi_get_buffer_info(env, a[1], &bytes, &len) != napi_ok) return integer(env, 0);
  CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)len);
  CTFontDescriptorRef desc = CTFontManagerCreateFontDescriptorFromData(data);
  CFRelease(data);
  if (!desc) return integer(env, 0);
  if (!face_descs[face_id]) {
    face_descs[face_id] = [NSMutableArray new];
    face_weights[face_id] = [NSMutableArray new];
  }
  [face_descs[face_id] addObject:(__bridge_transfer id)desc];
  [face_weights[face_id] addObject:@(weight)];
  faces_changed();
  return integer(env, 1);
}
static napi_value face_clear(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a);
  mb_host_face_clear((int)number(env, a[0]));
  return undefined(env);
}
static napi_value metrics(napi_env env, napi_callback_info info) {
  napi_value a[3]; args(env, info, 3, a); double out[6] = {0};
  mb_host_font_metrics(number(env, a[0]), (int)number(env, a[1]), (int)number(env, a[2]), out);
  return doubles(env, out, 6);
}
static unichar *text(napi_env env, napi_value arg, size_t *len) {
  napi_get_value_string_utf16(env, arg, NULL, 0, len);
  char16_t *buf = calloc(*len + 1, sizeof(char16_t));
  napi_get_value_string_utf16(env, arg, buf, *len + 1, len);
  return (unichar *)buf;
}
static NSString *string_arg(napi_env env, napi_value arg) {
  size_t len; unichar *s = text(env, arg, &len);
  NSString *out = [NSString stringWithCharacters:s length:len];
  free(s);
  return out;
}
static napi_value face_path(napi_env env, napi_callback_info info) {
  napi_value a[3]; args(env, info, 3, a);
  int face_index = (int)number(env, a[0]);
  if (face_index <= 0 || face_index >= MB_FACES) return integer(env, 0);
  NSURL *url = [NSURL fileURLWithPath:string_arg(env, a[1])];
  CFArrayRef ds = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
  if (!ds || CFArrayGetCount(ds) == 0) { if (ds) CFRelease(ds); return integer(env, 0); }
  if (!face_descs[face_index]) { face_descs[face_index] = [NSMutableArray new]; face_weights[face_index] = [NSMutableArray new]; }
  [face_descs[face_index] addObject:(__bridge id)CFArrayGetValueAtIndex(ds, 0)];
  [face_weights[face_index] addObject:@((int)number(env, a[2]))];
  CFRelease(ds); faces_changed(); return integer(env, 1);
}
static napi_value face_family(napi_env env, napi_callback_info info) {
  napi_value a[2]; args(env, info, 2, a);
  int face_index = (int)number(env, a[0]);
  if (face_index <= 0 || face_index >= MB_FACES) return integer(env, 0);
  NSDictionary *attrs = @{(id)kCTFontFamilyNameAttribute : string_arg(env, a[1])};
  CTFontDescriptorRef base = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attrs);
  CFArrayRef ds = CTFontDescriptorCreateMatchingFontDescriptors(base, NULL);
  CFRelease(base);
  if (!ds) return integer(env, 0);
  NSMutableArray *descs = [NSMutableArray new];
  NSMutableArray<NSNumber *> *weights = [NSMutableArray new];
  for (CFIndex i = 0; i < CFArrayGetCount(ds); i++) {
    CTFontDescriptorRef d = (CTFontDescriptorRef)CFArrayGetValueAtIndex(ds, i);
    NSDictionary *traits = (__bridge_transfer NSDictionary *)CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute);
    if ([traits[(id)kCTFontSymbolicTrait] unsignedIntValue] & kCTFontItalicTrait) continue;
    [descs addObject:(__bridge id)d];
    [weights addObject:@(css_weight([traits[(id)kCTFontWeightTrait] doubleValue]))];
  }
  CFRelease(ds);
  if (!descs.count) return integer(env, 0);
  face_descs[face_index] = descs; face_weights[face_index] = weights; faces_changed();
  return integer(env, 1);
}
static napi_value image_load(napi_env env, napi_callback_info info) {
  napi_value a[2]; args(env, info, 2, a); size_t len;
  unichar *s = text(env, a[0], &len);
  NSString *src = [NSString stringWithCharacters:s length:len];
  free(s);
  int max_px = (int)number(env, a[1]);
  if ([src hasPrefix:@"http://"] || [src hasPrefix:@"https://"]) {
    NSURL *url = [NSURL URLWithString:src];
    setup();
    int iid = ++next_id;
    images[@(iid)] = [MBImage new];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
      (void)r; (void)e;
      dispatch_async(decode_q, ^{
        dispatch_semaphore_wait(decode_slots, DISPATCH_TIME_FOREVER);
        @autoreleasepool { decode(iid, data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL, max_px); }
        dispatch_semaphore_signal(decode_slots);
      });
    }] resume];
    return integer(env, iid);
  }
  NSURL *url = [src hasPrefix:@"file://"] ? [NSURL URLWithString:src] : [NSURL fileURLWithPath:src];
  return integer(env, start(^(int iid) { decode(iid, CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL), max_px); }));
}
static napi_value image_bytes(napi_env env, napi_callback_info info) {
  napi_value a[2]; args(env, info, 2, a); void *bytes; size_t len;
  if (napi_get_buffer_info(env, a[0], &bytes, &len) != napi_ok) return integer(env, 0);
  NSData *data = [NSData dataWithBytes:bytes length:len];
  int max_px = (int)number(env, a[1]);
  return integer(env, start(^(int iid) { decode(iid, CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL), max_px); }));
}
static napi_value image_info(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); double out[5] = {0};
  out[0] = mb_host_image_info((int)number(env, a[0]), out + 1);
  return doubles(env, out, 5);
}
static napi_value image_free(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); mb_host_image_free((int)number(env, a[0]));
  return undefined(env);
}
static napi_value image_pixels(napi_env env, napi_callback_info info) {
  napi_value a[2]; args(env, info, 2, a);
  MBImage *im = images[@((int)number(env, a[0]))];
  size_t len = im ? (size_t)im.w * im.h * 4 : 0;
  if (!im || im.state != 1 || !im.tex || len > (size_t)number(env, a[1])) return undefined(env);
  void *data; napi_value out;
  napi_create_buffer(env, len, &data, &out);
  [im.tex getBytes:data bytesPerRow:(NSUInteger)im.w * 4 fromRegion:MTLRegionMake2D(0, 0, im.w, im.h) mipmapLevel:0];
  return out;
}
static napi_value turn(napi_env env, napi_callback_info info) {
  (void)info;
  CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, true);
  return undefined(env);
}
static napi_value shape(napi_env env, napi_callback_info info) {
  napi_value a[5]; args(env, info, 5, a); size_t len;
  unichar *s = text(env, a[0], &len);
  int cap = (int)number(env, a[4]) / 4;
  double *out = calloc(cap > 0 ? (size_t)cap * 4 : 1, sizeof(double));
  int n = shape_line((moonbit_string_t)s, (int32_t)len, number(env, a[1]),
      (int)number(env, a[2]), (int)number(env, a[3]), out, cap);
  napi_value result = doubles(env, out, (size_t)n * 4);
  free(out); free(s);
  return result;
}
static napi_value key(napi_env env, napi_callback_info info) {
  napi_value a[4]; args(env, info, 4, a); size_t len;
  unichar *s = text(env, a[0], &len);
  NSString *str = [NSString stringWithCharacters:s length:len];
  int k = intern(str, number(env, a[1]), (int)number(env, a[2]), (int)number(env, a[3]));
  free(s); return integer(env, k);
}
static napi_value glyph(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); double out[8] = {0};
  mb_host_glyph((int)number(env, a[0]), out); return doubles(env, out, 8);
}
static napi_value glyph_put(napi_env env, napi_callback_info info) {
  napi_value a[3]; args(env, info, 3, a);
  mb_host_glyph_put((int)number(env, a[0]), (int)number(env, a[1]), (int)number(env, a[2]));
  return undefined(env);
}
static napi_value atlas_size(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); return integer(env, mb_host_atlas_size((int)number(env, a[0])));
}
static napi_value atlas_generation(napi_env env, napi_callback_info info) {
  (void)info; return integer(env, mb_host_atlas_generation());
}
static napi_value draw(napi_env env, napi_callback_info info) {
  napi_value a[5]; args(env, info, 5, a);
  napi_typedarray_type type; size_t len; void *data; napi_value buffer; size_t offset;
  if (napi_get_typedarray_info(env, a[0], &type, &len, &data, &buffer, &offset) != napi_ok ||
      type != napi_float64_array || len < (size_t)number(env, a[1]) * 60) {
    napi_throw_error(env, NULL, "invalid instance data"); return NULL;
  }
  double times[2];
  mb_host_render_dirty(0, 0, -1, -1);
  mb_render_draw_timed(data, (int)number(env, a[1]), number(env, a[2]), number(env, a[3]), number(env, a[4]), times);
  return doubles(env, times, 2);
}
static napi_value snapshot(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); size_t len;
  napi_get_value_string_utf8(env, a[0], NULL, 0, &len);
  char *path = calloc(len + 1, 1);
  napi_get_value_string_utf8(env, a[0], path, len + 1, &len);
  int ok = mb_render_snapshot(path); free(path); return integer(env, ok);
}
static napi_value snapshot_transparent(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); size_t len;
  napi_get_value_string_utf8(env, a[0], NULL, 0, &len);
  char *path = calloc(len + 1, 1);
  napi_get_value_string_utf8(env, a[0], path, len + 1, &len);
  int ok = mb_render_snapshot_transparent(path); free(path); return integer(env, ok);
}

// The film's writer (apple_film.m): begun at a path, a frame's instances drawn and kept, put as frame k, closed, and
// published or discarded.
static napi_value film_open(napi_env env, napi_callback_info info) {
  napi_value a[4]; args(env, info, 4, a); size_t len;
  napi_get_value_string_utf8(env, a[0], NULL, 0, &len);
  char *path = calloc(len + 1, 1);
  napi_get_value_string_utf8(env, a[0], path, len + 1, &len);
  int ok = mbf_open_path([NSString stringWithUTF8String:path], (int32_t)number(env, a[1]), (int32_t)number(env, a[2]),
      (int32_t)number(env, a[3]));
  free(path); return integer(env, ok);
}
static napi_value film_draw(napi_env env, napi_callback_info info) {
  napi_value a[5]; args(env, info, 5, a);
  napi_typedarray_type type; size_t len; void *data; napi_value buffer; size_t offset;
  if (napi_get_typedarray_info(env, a[0], &type, &len, &data, &buffer, &offset) != napi_ok ||
      type != napi_float64_array || len < (size_t)number(env, a[1]) * 60) {
    napi_throw_error(env, NULL, "invalid instance data"); return NULL;
  }
  return integer(env, mbf_draw(data, (int32_t)number(env, a[1]), number(env, a[2]), number(env, a[3]), number(env, a[4])));
}
static napi_value film_put(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); return integer(env, mbf_put((int32_t)number(env, a[0])));
}
static napi_value film_close(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); return integer(env, mbf_close((int32_t)number(env, a[0])));
}
static napi_value film_finish(napi_env env, napi_callback_info info) {
  napi_value a[1]; args(env, info, 1, a); return integer(env, mbf_finish((int32_t)number(env, a[0])));
}

static napi_value setup_exports(napi_env env, napi_value exports) {
  napi_property_descriptor props[] = {
    {"init", NULL, init, NULL, NULL, NULL, napi_default, NULL},
    {"view", NULL, view, NULL, NULL, NULL, napi_default, NULL},
    {"face", NULL, face, NULL, NULL, NULL, napi_default, NULL},
    {"facePath", NULL, face_path, NULL, NULL, NULL, napi_default, NULL},
    {"faceFamily", NULL, face_family, NULL, NULL, NULL, napi_default, NULL},
    {"faceClear", NULL, face_clear, NULL, NULL, NULL, napi_default, NULL},
    {"metrics", NULL, metrics, NULL, NULL, NULL, napi_default, NULL},
    {"shape", NULL, shape, NULL, NULL, NULL, napi_default, NULL},
    {"textKey", NULL, key, NULL, NULL, NULL, napi_default, NULL},
    {"glyph", NULL, glyph, NULL, NULL, NULL, napi_default, NULL},
    {"glyphPut", NULL, glyph_put, NULL, NULL, NULL, napi_default, NULL},
    {"atlasSize", NULL, atlas_size, NULL, NULL, NULL, napi_default, NULL},
    {"atlasGeneration", NULL, atlas_generation, NULL, NULL, NULL, napi_default, NULL},
    {"draw", NULL, draw, NULL, NULL, NULL, napi_default, NULL},
    {"snapshot", NULL, snapshot, NULL, NULL, NULL, napi_default, NULL},
    {"snapshotTransparent", NULL, snapshot_transparent, NULL, NULL, NULL, napi_default, NULL},
    {"imageLoad", NULL, image_load, NULL, NULL, NULL, napi_default, NULL},
    {"imageBytes", NULL, image_bytes, NULL, NULL, NULL, napi_default, NULL},
    {"imageInfo", NULL, image_info, NULL, NULL, NULL, napi_default, NULL},
    {"imageFree", NULL, image_free, NULL, NULL, NULL, napi_default, NULL},
    {"imagePixels", NULL, image_pixels, NULL, NULL, NULL, napi_default, NULL},
    {"turn", NULL, turn, NULL, NULL, NULL, napi_default, NULL},
    {"filmOpen", NULL, film_open, NULL, NULL, NULL, napi_default, NULL},
    {"filmDraw", NULL, film_draw, NULL, NULL, NULL, napi_default, NULL},
    {"filmPut", NULL, film_put, NULL, NULL, NULL, napi_default, NULL},
    {"filmClose", NULL, film_close, NULL, NULL, NULL, napi_default, NULL},
    {"filmFinish", NULL, film_finish, NULL, NULL, NULL, napi_default, NULL},
  };
  napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
  return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME, setup_exports)
