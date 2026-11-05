// The native views' self-test (test/apple_views/run.sh builds and runs it):
// what the MoonBit side will do, done from Objective-C. A window holding the
// views' root; each tick (60 Hz) the player's reads are answered from a file
// as the app would answer them; the frames presented (offscreen) with a hole
// where the view shows and a bar over it, snapshots checked pixel by pixel.
//   selftest <out dir> <pdf> "<file>|<mime>|<duration ms>|<width>|<height>"...
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import "apple.h"

// what the app's host files (mac_app.m) give the shared ones
mb_callbacks mb_cb;
static int frames_asked;
void mb_host_request_frame(void) { frames_asked++; }
void mb_host_outside(int32_t kind, int32_t id, int32_t state) { (void)kind; (void)id; (void)state; }
void mb_stream_attach_layer(int sid, CALayer *layer) { (void)sid; (void)layer; }
void mb_stream_layout(int sid, double w, double h) { (void)sid; (void)w; (void)h; }
id<MTLTexture> mb_stream_texture(int sid) { (void)sid; return nil; }
double mb_now_ms(void) { return CACurrentMediaTime() * 1000.0; }
CTFontRef mb_platform_font(double size, int weight, int mono) {
  return (CTFontRef)CFBridgingRetain([NSFont systemFontOfSize:size]);
}
void mb_render_init_offscreen(double w, double h, double scale);
void moonbit_panic(void) { abort(); }  // the runtime's, given by a MoonBit program

// the host API under test
int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg);
void mb_host_view_place(int32_t, double, double, double, double, double, double, double, double, double, double,
                        double, double, int32_t);
void mb_host_view_close(int32_t);
void mb_host_view_control(int32_t, int32_t, double);
int32_t mb_host_view_info(int32_t, double *);
int32_t mb_host_view_read_next(int32_t, double *);
void mb_host_view_read_answer(int32_t, int32_t, moonbit_bytes_t, double, int32_t);
double mb_host_video_test_rate(int32_t);
moonbit_string_t mb_host_view_text(int32_t, int32_t);
moonbit_bytes_t mb_host_view_still(int32_t);
int32_t mb_host_pdf_open(moonbit_bytes_t);
int32_t mb_host_pdf_pages(int32_t);
void mb_host_pdf_page_size(int32_t, int32_t, double *);
int32_t mb_host_pdf_page_load(int32_t, int32_t, int32_t);
void mb_host_pdf_close(int32_t);
int32_t mb_host_image_info(int32_t, double *);
void mb_host_image_free(int32_t);
int32_t mb_host_save_file(moonbit_string_t, moonbit_bytes_t);

static const double W = 480, H = 360, S = 2;
static NSString *out_dir;
static int fails;

static void check(BOOL ok, NSString *what) {
  printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
  fflush(stdout);
  if (!ok) fails++;
}

static moonbit_bytes_t mbytes(const void *p, size_t n) {
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, p, n);
  return b;
}

// ---- frames and snapshots ----

static double inst[60 * 8];
static int ninst;
static void add(double x, double y, double w, double h, int kind, double r, double g, double b, double a) {
  double *f = inst + 60 * ninst++;
  memset(f, 0, 60 * sizeof(double));
  f[0] = x; f[1] = y; f[2] = w; f[3] = h; f[5] = kind;
  f[8] = r; f[9] = g; f[10] = b; f[11] = a;
  f[16] = 0; f[17] = 0; f[18] = 1e9; f[19] = 1e9;
}
// the view's hole at (x, y, w, h), a red bar over its top left, the background light grey
static NSString *snapshot(NSString *name, int32_t vid, double x, double y, double w, double h) {
  ninst = 0;
  add(x, y, w, h, 9, 0, 0, 0, 0);
  inst[20] = MB_VIEW_TEX + vid;
  add(x, y, 100, 50, 0, 1, 0, 0, 1);
  mb_render_present(inst, ninst, 0.9, 0.9, 0.9);
  NSString *p = [out_dir stringByAppendingPathComponent:name];
  check(mb_render_snapshot(p.fileSystemRepresentation), [NSString stringWithFormat:@"snapshot %@ written", name]);
  return p;
}

// a pixel of a PNG (x, y from the top left, pixels), RGBA
static void pixel(NSString *path, int x, int y, uint8_t px[4]) {
  memset(px, 0, 4);
  CGImageSourceRef s = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
  if (!s) return;
  CGImageRef im = CGImageSourceCreateImageAtIndex(s, 0, NULL);
  CFRelease(s);
  if (!im) return;
  size_t iw = CGImageGetWidth(im), ih = CGImageGetHeight(im);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef c = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGContextSetBlendMode(c, kCGBlendModeCopy);
  CGContextSetInterpolationQuality(c, kCGInterpolationNone);
  CGContextDrawImage(c, CGRectMake(-x, -((double)ih - 1 - y), iw, ih), im);
  CGContextRelease(c);
  CGColorSpaceRelease(cs);
  CGImageRelease(im);
}
static BOOL near(const uint8_t *px, int r, int g, int b, int tol) {
  return abs(px[0] - r) <= tol && abs(px[1] - g) <= tol && abs(px[2] - b) <= tol;
}
static NSString *rgba(const uint8_t *p) {
  return [NSString stringWithFormat:@"(%d,%d,%d,%d)", p[0], p[1], p[2], p[3]];
}

// ---- the steps, one per tick until each says it is done ----

typedef BOOL (^Step)(int tick);
static NSMutableArray<Step> *steps;
static int step_tick;

// A WebM goes through the app's same streamed reads as an AVPlayer file. Exercise real VP8 and VP9 decoding, the
// player's controls and its frame grab, with each step waiting for the event/state produced by the preceding one.
static void webm_steps(NSString *file, NSString *mime) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  __block int reads = 0;
  __block double maxRead = 0;
  __block double heldPosition = 0;
  double *info = calloc(10, sizeof(double));
  NSString *tag = file.lastPathComponent;
  __block double tolerance = 1;
  // After a paused seek of VP9 in MP4, WebKit sometimes presents no frame at all (#3993): the frame at a seek target is
  // not checked there, only what shows.
  BOOL seekShows = ![tag isEqualToString:@"test-vp9-aac.mp4"];
  void (^pump)(void) = ^{
    double o[2]; int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) continue;
      reads++; maxRead = MAX(maxRead, o[1]);
      long long off = (long long)o[0], n = MAX(0, MIN((long long)o[1], (long long)data.length - off));
      // A short answer followed by an empty last chunk, as station.file.part can deliver.
      n = MIN(n, 64 << 10);
      mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes + MIN(off, (long long)data.length), n), data.length, 1);
      mb_host_view_read_answer(vid, rid, mbytes(NULL, 0), data.length, 0);
    }
  };
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(mime));
    mb_host_view_place(vid, 40, 30, 320, 240, 40, 30, 360, 270, 0, 0, 0, 0, 1);
    double pending[10];
    check(mb_host_view_info(vid, pending) == 0, [NSString stringWithFormat:@"%@: waits for incomplete reads", tag]);
    NSView *root = mb_views_root(CGRectMake(0, 0, W, H));
    NSView *web = root.subviews.lastObject.subviews.firstObject;
    check(web && [web hitTest:NSMakePoint(1, 1)] == nil, [NSString stringWithFormat:@"%@: input reaches the app", tag]);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if ((state == 0 || state == 2) && t < 20 * 60) return NO;
    check(state == 1 && info[6] == 1, [NSString stringWithFormat:@"%@: ready (%d)", tag, state]);
    check(fabs(info[0] - 5000) < 300 && info[3] == 320 && info[4] == 240,
          [NSString stringWithFormat:@"%@: duration %.0f ms, size %.0fx%.0f", tag, info[0], info[3], info[4]]);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if ((state == 0 || state == 2 || (state == 1 && info[1] < 900)) && t < 20 * 60) return NO;
    check(state == 1 && info[1] >= 900, [NSString stringWithFormat:@"%@: played to %.0f ms", tag, info[1]]);
    mb_host_view_control(vid, 2, 0);
    mb_host_view_control(vid, 3, 2500);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if (state == 1 && (fabs(info[1] - 2500) > tolerance || info[2] != 0) && t < 20 * 60) return NO;
    check(state == 1 && fabs(info[1] - 2500) <= tolerance && info[2] == 0,
          [NSString stringWithFormat:@"%@: paused and sought to %.0f ms", tag, info[1]]);
    heldPosition = info[1];
    if (seekShows) mb_host_view_control(vid, 21, 2500);
    else mb_host_view_control(vid, 22, 160);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    if (!seekShows) return YES;
    pump(); NSString *state = mb_ns_from_string(mb_host_view_text(vid, 2));
    if ([state isEqualToString:@"1"] && t < 20 * 60) return NO;
    check([state isEqualToString:@"2"], [NSString stringWithFormat:@"%@: the frame at the seek target grabbed (%@)", tag, state]);
    if ([tag isEqualToString:@"test-vp9-aac.mp4"]) {
      moonbit_bytes_t bytes = mb_host_view_still(vid);
      NSString *path = [out_dir stringByAppendingPathComponent:[tag stringByAppendingString:@".target.png"]];
      [[NSData dataWithBytes:bytes length:Moonbit_array_length(bytes)] writeToFile:path atomically:YES];
      uint8_t px[4];
      pixel(path, 160, 120, px);
      check(near(px, 0, 0, 255, 40), [NSString stringWithFormat:@"%@: captured the frame at the seek target %@", tag, rgba(px)]);
    }
    mb_host_view_control(vid, 22, 160);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); NSString *state = mb_ns_from_string(mb_host_view_text(vid, 2));
    if ([state isEqualToString:@"1"] && t < 20 * 60) return NO;
    BOOL ok = [state isEqualToString:@"2"];
    moonbit_bytes_t bytes = mb_host_view_still(vid);
    NSData *image = [NSData dataWithBytes:bytes length:Moonbit_array_length(bytes)];
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)image, NULL);
    CGImageRef frame = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
    check(ok && frame && CGImageGetWidth(frame) == 160 && CGImageGetHeight(frame) == 120,
          [NSString stringWithFormat:@"%@: current frame captured (%@)", tag, state]);
    NSString *path = [out_dir stringByAppendingPathComponent:[tag stringByAppendingString:@".jpg"]];
    [image writeToFile:path atomically:YES];
    int coloured = 0; uint8_t px[4];
    for (int x = 20; x < 150; x += 25) {
      pixel(path, x, 75, px);
      if (px[3] == 255 && !near(px, 0, 0, 0, 8) && !near(px, 255, 255, 255, 8)) coloured++;
    }
    check(coloured >= 3, [NSString stringWithFormat:@"%@: captured the picture, not an empty frame", tag]);
    if (frame) CGImageRelease(frame);
    if (src) CFRelease(src);
    check(reads > 0 && maxRead <= (4 << 20), [NSString stringWithFormat:@"%@: bounded reads (%d)", tag, reads]);
    if ([mime isEqualToString:@"video/mp4"])
      check(reads < 32, [NSString stringWithFormat:@"%@: nearby MP4 reads were reused (%d)", tag, reads]);
    if (seekShows) mb_host_view_control(vid, 21, 1000);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    if (!seekShows) return YES;
    pump(); NSString *state = mb_ns_from_string(mb_host_view_text(vid, 2));
    if ([state isEqualToString:@"1"] && t < 20 * 60) return NO;
    moonbit_bytes_t bytes = mb_host_view_still(vid);
    NSData *image = [NSData dataWithBytes:bytes length:Moonbit_array_length(bytes)];
    [image writeToFile:[out_dir stringByAppendingPathComponent:[tag stringByAppendingString:@".png"]] atomically:YES];
    if ([tag isEqualToString:@"test-vp9-aac.mp4"]) {
      uint8_t px[4];
      pixel([out_dir stringByAppendingPathComponent:[tag stringByAppendingString:@".png"]], 160, 120, px);
      check(near(px, 255, 0, 0, 40), [NSString stringWithFormat:@"%@: saved the requested earlier frame %@", tag, rgba(px)]);
    }
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)image, NULL);
    CGImageRef frame = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
    check([state isEqualToString:@"2"] && frame && CGImageGetWidth(frame) == 320 && CGImageGetHeight(frame) == 240,
          [NSString stringWithFormat:@"%@: saved a full-size frame", tag]);
    if (frame) CGImageRelease(frame);
    if (src) CFRelease(src);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if (state == 1 && fabs(info[1] - heldPosition) > tolerance && t < 20 * 60) return NO;
    check(state == 1 && fabs(info[1] - heldPosition) <= tolerance && info[2] == 0,
          [NSString stringWithFormat:@"%@: saving a different frame kept the playhead (%.0f -> %.0f, state %d)",
           tag, heldPosition, info[1], state]);
    mb_host_view_control(vid, 4, 2);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    double rate = mb_host_video_test_rate(vid);
    if (state == 1 && (info[1] < 3500 || fabs(rate - 2) > 0.001) && t < 20 * 60) return NO;
    check(state == 1 && info[1] >= 3500 && fabs(rate - 2) <= 0.001,
          [NSString stringWithFormat:@"%@: played at a changed speed (%.2f)", tag, rate]);
    mb_host_view_control(vid, 21, 500);
    mb_host_view_control(vid, 23, 0);
    check([mb_ns_from_string(mb_host_view_text(vid, 2)) isEqualToString:@"0"],
          [NSString stringWithFormat:@"%@: a grab given up is over", tag]);
    mb_host_view_close(vid);
    return YES;
  }];
}

// VP9 in MP4 through WebKit, sought as it plays: its frames are red before 2 s and blue after. What shows now can be
// grabbed in the middle of a seek, however that seek goes.
static void vp9_mp4_steps(NSString *file) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  __block int reads = 0;
  double *info = calloc(10, sizeof(double));
  NSString *tag = file.lastPathComponent;
  NSString *path = [out_dir stringByAppendingPathComponent:[tag stringByAppendingString:@".jpg"]];
  void (^pump)(void) = ^{
    double o[2]; int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) continue;
      reads++;
      long long off = (long long)o[0], n = MAX(0, MIN((long long)o[1], (long long)data.length - off));
      n = MIN(n, 64 << 10);
      mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes + MIN(off, (long long)data.length), n), data.length, 1);
      mb_host_view_read_answer(vid, rid, mbytes(NULL, 0), data.length, 0);
    }
  };
  // The grab of what shows, once answered: its middle's colour, as a check named `what`.
  BOOL (^shown)(int, int, int, int, NSString *) = ^BOOL(int t, int r, int g, int b, NSString *what) {
    pump(); NSString *state = mb_ns_from_string(mb_host_view_text(vid, 2));
    if ([state isEqualToString:@"1"] && t < 20 * 60) return NO;
    check([state isEqualToString:@"2"], [NSString stringWithFormat:@"%@: %@ grabbed (%@)", tag, what, state]);
    moonbit_bytes_t bytes = mb_host_view_still(vid);
    [[NSData dataWithBytes:bytes length:Moonbit_array_length(bytes)] writeToFile:path atomically:YES];
    if (r >= 0) {
      uint8_t px[4];
      pixel(path, 80, 60, px);
      check(near(px, r, g, b, 40), [NSString stringWithFormat:@"%@: %@ shows its frame %@", tag, what, rgba(px)]);
    }
    return YES;
  };
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(@"video/mp4"));
    mb_host_view_place(vid, 40, 30, 320, 240, 40, 30, 360, 270, 0, 0, 0, 0, 1);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if ((state == 0 || state == 2) && t < 20 * 60) return NO;
    check(state == 1 && info[6] == 1, [NSString stringWithFormat:@"%@: ready (%d)", tag, state]);
    check(fabs(info[0] - 5000) < 300 && info[3] == 320 && info[4] == 240,
          [NSString stringWithFormat:@"%@: duration %.0f ms, size %.0fx%.0f", tag, info[0], info[3], info[4]]);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if (state == 1 && info[1] < 300 && t < 20 * 60) return NO;
    check(state == 1 && info[1] >= 300 && info[2] == 1, [NSString stringWithFormat:@"%@: played to %.0f ms", tag, info[1]]);
    mb_host_view_control(vid, 22, 160);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    if (!shown(t, 255, 0, 0, @"the first picture")) return NO;
    mb_host_view_control(vid, 3, 3000);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if (state == 1 && info[1] < 3300 && t < 20 * 60) return NO;
    check(state == 1 && info[1] >= 3300 && info[2] == 1,
          [NSString stringWithFormat:@"%@: played on from a seek, to %.0f ms", tag, info[1]]);
    mb_host_view_control(vid, 22, 160);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    if (!shown(t, 0, 0, 255, @"the picture after a seek")) return NO;
    mb_host_view_control(vid, 2, 0);
    mb_host_view_control(vid, 3, 1000);
    mb_host_view_control(vid, 22, 160);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    if (!shown(t, -1, 0, 0, @"what shows during a paused seek")) return NO;
    check(reads > 0 && reads < 32, [NSString stringWithFormat:@"%@: nearby MP4 reads were reused (%d)", tag, reads]);
    mb_host_view_close(vid);
    return YES;
  }];
}

// A chat can ask for its thumbnail as soon as the player is opened, without placing the view on screen.
static void webm_thumbnail_steps(NSString *file, NSString *mime) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(mime));
    mb_host_view_control(vid, 21, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    double o[2]; int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) continue;
      long long off = (long long)o[0], n = MAX(0, MIN((long long)o[1], (long long)data.length - off));
      mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes + MIN(off, (long long)data.length), n), data.length, 0);
    }
    NSString *state = mb_ns_from_string(mb_host_view_text(vid, 2));
    if ([state isEqualToString:@"1"] && t < 20 * 60) return NO;
    moonbit_bytes_t bytes = mb_host_view_still(vid);
    check([state isEqualToString:@"2"] && Moonbit_array_length(bytes) > 0,
          [NSString stringWithFormat:@"%@: first frame grabbed before the view is placed", file.lastPathComponent]);
    mb_host_view_close(vid);
    return YES;
  }];
}

// A larger file arrives in small chunks, as over a station connection. The player can start and seek while reads are
// in flight, and never asks the app for more than one 4 MB part.
static void webm_large_steps(NSString *file) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  __block int reads = 0;
  __block double maxRead = 0;
  NSMutableArray<NSMutableArray<NSNumber *> *> *open = [NSMutableArray new];
  double *info = calloc(10, sizeof(double));
  void (^pump)(void) = ^{
    double o[2]; int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) {
        for (NSMutableArray<NSNumber *> *r in [open copy]) if (r[0].intValue == -rid) [open removeObject:r];
        continue;
      }
      reads++; maxRead = MAX(maxRead, o[1]);
      long long off = (long long)o[0], end = MIN((long long)data.length, off + (long long)o[1]);
      [open addObject:[@[@(rid), @(off), @(end)] mutableCopy]];
    }
    for (NSMutableArray<NSNumber *> *r in [open copy]) {
      long long off = r[1].longLongValue, end = r[2].longLongValue, n = MIN(32 << 10, MAX(0, end - off));
      BOOL more = off + n < end;
      mb_host_view_read_answer(vid, r[0].intValue, mbytes((const uint8_t *)data.bytes + MIN(off, (long long)data.length), n),
                               data.length, more);
      if (more) r[1] = @(off + n); else [open removeObject:r];
    }
  };
  [steps addObject:^BOOL(int t) {
    check(data.length > (4 << 20), @"WebM: large fixture exceeds one read");
    vid = mb_host_view_open(1, mb_string_from_ns(@"video/webm"));
    mb_host_view_place(vid, 40, 30, 320, 180, 40, 30, 360, 210, 0, 0, 0, 0, 1);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if ((state == 0 || state == 2) && t < 40 * 60) return NO;
    check(state == 1 && info[3] == 640 && info[4] == 360, @"WebM: large file became ready as its bytes arrived");
    mb_host_view_control(vid, 3, 10000);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if (state == 1 && (fabs(info[1] - 10000) > 1 || info[6] == 0) && t < 40 * 60) return NO;
    check(state == 1 && fabs(info[1] - 10000) <= 1 && info[6] == 1, @"WebM: seek into the large file showed a frame");
    check(reads > 1 && maxRead <= (4 << 20), [NSString stringWithFormat:@"WebM: %d bounded reads, largest %.0f", reads, maxRead]);
    mb_host_view_close(vid);
    return YES;
  }];
}

// AV1 in MP4 is handled by AVFoundation on devices with its decoder. Where the system lacks it, the player must say so
// rather than claim a silent video is ready; where it has one, exercise actual playback as well as metadata.
static void av1_mp4_steps(NSString *file) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  __block BOOL unavailable = NO;
  double *info = calloc(10, sizeof(double));
  void (^pump)(void) = ^{
    double o[2]; int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) continue;
      long long off = (long long)o[0], n = MAX(0, MIN((long long)o[1], (long long)data.length - off));
      mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes + MIN(off, (long long)data.length), n), data.length, 0);
    }
  };
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(@"video/mp4"));
    mb_host_view_place(vid, 40, 30, 320, 240, 40, 30, 360, 270, 0, 0, 0, 0, 1);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump(); int state = mb_host_view_info(vid, info);
    if ((state == 0 || state == 2) && t < 20 * 60) return NO;
    unavailable = state == -2 || state == -4;
    check(unavailable || (state == 1 && info[3] == 320 && info[4] == 240),
          [NSString stringWithFormat:@"AV1 MP4: supported or correctly unavailable (state %d, %.0fx%.0f)", state, info[3], info[4]]);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    if (!unavailable) {
      pump(); int state = mb_host_view_info(vid, info);
      if (state == 1 && (info[6] == 0 || info[1] < 500) && t < 20 * 60) return NO;
      check(state == 1 && info[6] == 1 && info[1] >= 500, @"AV1 MP4: played and showed a frame");
    }
    mb_host_view_close(vid);
    return YES;
  }];
}

static void video_steps(NSString *file, NSString *mime, double dur, double vw, double vh) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  __block int reads = 0, partial = 0;
  __block double maxlen = 0, given = 0;
  double *info = calloc(10, sizeof(double));
  __block int state = 0;
  NSString *tag = file.lastPathComponent;
  const double X = 40, Y = 30, VW = 320, VH = 240;
  // the app's half of the player: every read waiting answered from the file, at most 1 MB of it (fewer than asked
  // is allowed), in pieces of 64 KB as they would come, then its last answer with none (one let go of: nothing)
  void (^pump)(void) = ^{
    double o[2];
    int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) continue;
      reads++;
      if (o[1] > maxlen) maxlen = o[1];
      long long off = (long long)o[0], len = (long long)o[1];
      long long n = MAX(0, MIN(len, (long long)data.length - off));
      if (n > (1 << 20)) { n = 1 << 20; partial++; }
      given += n;
      for (long long at = 0; at < n; at += 64 << 10) {
        long long k = MIN(n - at, 64 << 10);
        mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes + off + at, (size_t)k), (double)data.length, 1);
      }
      mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes, 0), (double)data.length, 0);
    }
    state = mb_host_view_info(vid, info);
  };
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(mime));
    check(vid > 0, [NSString stringWithFormat:@"%@: opened (id %d)", tag, vid]);
    mb_host_view_place(vid, X, Y, VW, VH, X, Y, X + VW, Y + VH, 0, 0, 0, 0, 1);
    mb_host_view_place(vid, X, Y, VW, VH, X, Y, X + VW, Y + VH, 0, 0, 0, 0, 1);  // again, unchanged: nothing done
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump();
    if ((state == 0 || state == 2) && t < 20 * 60) return NO;
    check(state == 1, [NSString stringWithFormat:@"%@: ready (state %d after %d ticks)", tag, state, t]);
    check(reads > 0 && given > 0, [NSString stringWithFormat:@"%@: %d reads answered, %.0f bytes", tag, reads, given]);
    check(fabs(info[0] - dur) < 200, [NSString stringWithFormat:@"%@: duration %.0f ms", tag, info[0]]);
    check(info[3] == vw && info[4] == vh, [NSString stringWithFormat:@"%@: size %.0fx%.0f", tag, info[3], info[4]]);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump();
    if ((info[6] == 0 || info[1] < 1200) && t < 20 * 60) return NO;
    check(info[6] == 1, [NSString stringWithFormat:@"%@: a frame shown", tag]);
    check(info[1] >= 1200, [NSString stringWithFormat:@"%@: played to %.0f ms (playing %.0f, buffering %.0f)", tag,
                                                        info[1], info[2], info[7]]);
    mb_host_view_control(vid, 2, 0);
    mb_host_view_control(vid, 3, 2500);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump();
    if ((fabs(info[1] - 2500) > 0.5 || t < 30) && t < 10 * 60) return NO;
    check(fabs(info[1] - 2500) <= 0.5 && info[2] == 0,
          [NSString stringWithFormat:@"%@: paused, sought to %.1f ms exactly", tag, info[1]]);
    check(info[5] == given, [NSString stringWithFormat:@"%@: bytes told %.0f", tag, info[5]]);
    NSString *p = snapshot([NSString stringWithFormat:@"video-%@.png", tag], vid, X, Y, VW, VH);
    uint8_t px[4];
    pixel(p, 10 * S, 10 * S, px);
    check(near(px, 230, 230, 230, 2) && px[3] == 255, [NSString stringWithFormat:@"%@: background %@", tag, rgba(px)]);
    pixel(p, (X + 20) * S, (Y + 20) * S, px);
    check(near(px, 255, 0, 0, 2) && px[3] == 255, [NSString stringWithFormat:@"%@: the bar over the video %@", tag, rgba(px)]);
    // testsrc's picture: colored, not the grey behind, not black (no frame)
    int colored = 0;
    NSMutableString *seen = [NSMutableString new];
    for (int i = 0; i < 6; i++) {
      pixel(p, (X + 40 + i * 50) * S, (Y + 150) * S, px);
      [seen appendString:rgba(px)];
      if (px[3] == 255 && !near(px, 230, 230, 230, 8) && !near(px, 0, 0, 0, 8)) colored++;
    }
    check(colored >= 3, [NSString stringWithFormat:@"%@: the video's frame under the hole %@", tag, seen]);
    mb_host_view_control(vid, 4, 2);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    pump();
    double rate = mb_host_video_test_rate(vid);
    if ((info[2] == 0 || fabs(rate - 2) > 0.001) && t < 20 * 60) return NO;
    check(info[2] == 1 && fabs(rate - 2) <= 0.001, [NSString stringWithFormat:@"%@: playing at the requested 2× rate (%.2f)", tag, rate]);
    mb_host_view_close(vid);
    check(mb_host_view_info(vid, info) == -1, [NSString stringWithFormat:@"%@: closed", tag]);
    printf("%s: %d reads, the longest %.0f bytes, %d answered short, %.0f bytes of %lu\n", tag.UTF8String, reads,
           maxlen, partial, given, (unsigned long)data.length);
    check(maxlen <= (4 << 20), [NSString stringWithFormat:@"%@: reads at most 4 MB", tag]);
    return YES;
  }];
}

// A video whose bytes come slower than it plays (as over a slow network): it plays what came (playWhatCame), stops
// where that runs out and plays again once the next has come; while its picture moves on it is not buffering, though
// the player reckons it will not keep up.
static void slow_steps(NSString *file, NSString *mime, double rate) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  double *info = calloc(10, sizeof(double));
  NSString *tag = [@"slow " stringByAppendingString:file.lastPathComponent];
  // the reads asked and not yet answered in full, each its id, where it is up to and where it ends
  NSMutableArray<NSArray<NSNumber *> *> *open = [NSMutableArray new];
  __block double began = 0, sent = 0;
  void (^pump)(void) = ^{
    double o[2];
    int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) {
        for (NSUInteger i = 0; i < open.count; i++)
          if (open[i][0].intValue == -rid) { [open removeObjectAtIndex:i]; break; }
        continue;
      }
      long long off = (long long)o[0], end = MIN((long long)data.length, off + MIN((long long)o[1], 1 << 20));
      [open addObject:@[@(rid), @(off), @(end)]];
    }
    // what the rate has brought since it began (by the clock: ticks slow on a busy machine), to the oldest read first
    if (began == 0) began = CACurrentMediaTime();
    long long budget = (long long)(rate * (CACurrentMediaTime() - began) - sent);
    while (budget > 0 && open.count) {
      int32_t r = open[0][0].intValue;
      long long at = open[0][1].longLongValue, end = open[0][2].longLongValue, k = MIN(budget, end - at);
      if (k > 0) mb_host_view_read_answer(vid, r, mbytes((const uint8_t *)data.bytes + at, (size_t)k), (double)data.length, 1);
      budget -= k;
      sent += k;
      if (at + k >= end) {
        mb_host_view_read_answer(vid, r, mbytes(data.bytes, 0), (double)data.length, 0);
        [open removeObjectAtIndex:0];
      } else {
        open[0] = @[@(r), @(at + k), @(end)];
      }
    }
    mb_host_view_info(vid, info);
  };
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(mime));
    check(vid > 0, [NSString stringWithFormat:@"%@: opened (id %d)", tag, vid]);
    mb_host_view_place(vid, 40, 30, 320, 240, 40, 30, 360, 270, 0, 0, 0, 0, 1);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  __block int moving = 0, said = 0;
  __block BOOL moved_before = NO;
  __block double last = -1;
  __block double t0 = 0;
  [steps addObject:^BOOL(int t) {
    pump();
    if (t == 0) t0 = CACurrentMediaTime();
    // its picture moving on over this tick and the one before
    BOOL moved = last >= 0 && info[1] > last;
    if (moved && moved_before) {
      moving++;
      if (info[7] != 0) said++;
    }
    moved_before = moved;
    last = info[1];
    if (info[1] < 4000 && CACurrentMediaTime() - t0 < 40) return NO;
    check(info[1] >= 4000 && moving > 0, [NSString stringWithFormat:@"%@: played to %.0f ms", tag, info[1]]);
    check(said <= 3, [NSString stringWithFormat:@"%@: buffering said in %d of the %d ticks it played on", tag, said, moving]);
    mb_host_view_close(vid);
    return YES;
  }];
}

// The host distinguishes a failed read from a damaged file. WebKit cannot always distinguish a damaged WebM from an
// unsupported codec, so either of its two media failure states is valid for that file.
static void failure_steps(NSString *file, NSString *mime, int kind) {
  NSData *data = [NSData dataWithContentsOfFile:file];
  __block int32_t vid = 0;
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(1, mb_string_from_ns(mime));
    check(vid > 0 && data.length > 0, [NSString stringWithFormat:@"%@: opened", file.lastPathComponent]);
    mb_host_view_place(vid, 0, 0, 320, 240, 0, 0, 320, 240, 0, 0, 0, 0, 1);
    mb_host_view_control(vid, 1, 0);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    double o[2], info[10];
    int32_t rid;
    while ((rid = mb_host_view_read_next(vid, o)) != 0) {
      if (rid < 0) continue;
      if (kind == 2) {
        mb_host_view_read_answer(vid, rid, mbytes(NULL, 0), -2, 0);
        continue;
      }
      long long off = (long long)o[0], len = (long long)o[1];
      long long n = MAX(0, MIN(len, (long long)data.length - off));
      mb_host_view_read_answer(vid, rid, mbytes((const uint8_t *)data.bytes + MIN(off, (long long)data.length), n),
                               data.length, 0);
    }
    int state = mb_host_view_info(vid, info);
    if ((state == 0 || (kind == 4 && state == 1 && info[1] < 300)) && t < 20 * 60) return NO;
    // This profile can be unsupported by the system or fully delivered while still awaiting a frame.
    BOOL expected = kind == 1 ? state == -3 : kind == 3 ? state == -3 || state == -4 || state == 2 : kind == 4 ? (state == 1 && info[1] >= 300) || state == 2 || state == -2 || state == -3 || state == -4 :
                    kind == 6 ? state == -2 : kind == 5 ? state == -2 || (state == 1 && info[3] > 0 && info[4] > 0) : state == -1;
    check(expected, [NSString stringWithFormat:@"%@: failure state %d", file.lastPathComponent, state]);
    mb_host_view_close(vid);
    return YES;
  }];
}

static void web_steps(void) {
  __block int32_t vid = 0;
  double *info = calloc(10, sizeof(double));
  const double X = 40, Y = 30, VW = 320, VH = 240;
  NSString *html = @"<!doctype html><html><body style=\"margin:0;background:#c00000\">"
                    "<a id=l href=\"https://example.com/\">a link</a>"
                    "<script>document.body.style.background='#00a000';"
                    "setTimeout(function(){location.href='https://example.com/'},200)</script></body></html>";
  [steps addObject:^BOOL(int t) {
    vid = mb_host_view_open(2, mb_string_from_ns(html));
    check(vid > 0, [NSString stringWithFormat:@"web: opened (id %d)", vid]);
    mb_host_view_place(vid, X, Y, VW, VH, X, Y, X + VW, Y + VH, 0, 0, 0, 0, 1);
    return YES;
  }];
  __block int loadedAt = -1;
  [steps addObject:^BOOL(int t) {
    int st = mb_host_view_info(vid, info);
    if (st == 1 && loadedAt < 0) loadedAt = t;
    // the snapshot's picture comes a little later; the script's navigation tried meanwhile
    if ((loadedAt < 0 || t < loadedAt + 60) && t < 15 * 60) return NO;
    check(st == 1 && info[6] == 1, [NSString stringWithFormat:@"web: loaded (state %d)", st]);
    check(info[5] == [html lengthOfBytesUsingEncoding:NSUTF8StringEncoding], @"web: its HTML's length told");
    check(mb_views_pass_through(X + 100, Y + 100) == 1, @"web: the pointer over it goes to it");
    check(mb_views_pass_through(10, 10) == 0, @"web: not elsewhere");
    NSString *p = snapshot(@"web.png", vid, X, Y, VW, VH);
    uint8_t px[4];
    pixel(p, (X + 200) * S, (Y + 150) * S, px);
    check(near(px, 0, 160, 0, 30) && px[3] == 255, [NSString stringWithFormat:@"web: its script ran, the page green %@", rgba(px)]);
    pixel(p, (X + 20) * S, (Y + 20) * S, px);
    check(near(px, 255, 0, 0, 2), [NSString stringWithFormat:@"web: the bar over it %@", rgba(px)]);
    mb_host_view_place(vid, X, Y, VW, VH, X, Y, X + VW, Y + VH, 0, 0, 0, 0, 0);
    check(mb_views_pass_through(X + 100, Y + 100) == 0, @"web: hidden, the pointer stays the canvas's");
    mb_host_view_close(vid);
    return YES;
  }];
}

static void pdf_steps(NSString *pdf) {
  NSData *d = [NSData dataWithContentsOfFile:pdf];
  __block int32_t doc = 0, im0 = 0, im1 = 0;
  [steps addObject:^BOOL(int t) {
    int32_t bad = mb_host_pdf_open(mbytes("not a pdf", 9));
    check(bad > 0 && mb_host_pdf_pages(bad) == -1, @"pdf: not a PDF: an id, -1 pages");
    mb_host_pdf_close(bad);
    doc = mb_host_pdf_open(mbytes(d.bytes, d.length));
    check(mb_host_pdf_pages(doc) == 2, [NSString stringWithFormat:@"pdf: %d pages", mb_host_pdf_pages(doc)]);
    double sz[2];
    mb_host_pdf_page_size(doc, 0, sz);
    check(sz[0] == 612 && sz[1] == 792, [NSString stringWithFormat:@"pdf: page 0 %.0fx%.0f", sz[0], sz[1]]);
    mb_host_pdf_page_size(doc, 1, sz);
    check(sz[0] == 792 && sz[1] == 612, [NSString stringWithFormat:@"pdf: page 1 (turned) %.0fx%.0f", sz[0], sz[1]]);
    im0 = mb_host_pdf_page_load(doc, 0, 1000);
    im1 = mb_host_pdf_page_load(doc, 1, 1000);
    return YES;
  }];
  [steps addObject:^BOOL(int t) {
    double a[4], b[4];
    int s0 = mb_host_image_info(im0, a), s1 = mb_host_image_info(im1, b);
    if ((s0 == 0 || s1 == 0) && t < 10 * 60) return NO;
    check(s0 == 1 && a[0] == 773 && a[1] == 1000, [NSString stringWithFormat:@"pdf: page 0 drawn %.0fx%.0f", a[0], a[1]]);
    check(s1 == 1 && b[0] == 1000 && b[1] == 773, [NSString stringWithFormat:@"pdf: page 1 drawn %.0fx%.0f", b[0], b[1]]);
    // the textures read back and saved; where the squares are
    struct { int32_t im; int w, h; int rx, ry, bx, by; const char *name; } pages[2] = {
        {im0, 773, 1000, 217, 846, 568, 116, "pdf-page0.png"},
        {im1, 1000, 773, 154, 217, 884, 568, "pdf-page1.png"},
    };
    for (int i = 0; i < 2; i++) {
      id<MTLTexture> tex = mb_image_texture(pages[i].im);
      if (!tex) { check(NO, @"pdf: texture"); continue; }
      int w = (int)tex.width, h = (int)tex.height;
      uint8_t *px = malloc((size_t)w * h * 4);
      [tex getBytes:px bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
      const uint8_t *r = px + ((size_t)pages[i].ry * w + pages[i].rx) * 4;
      const uint8_t *bl = px + ((size_t)pages[i].by * w + pages[i].bx) * 4;
      const uint8_t *wh = px + ((size_t)(h / 2) * w + w / 2) * 4;
      check(near(r, 255, 0, 0, 40), [NSString stringWithFormat:@"pdf: page %d red at its place %@", i, rgba(r)]);
      check(near(bl, 0, 0, 255, 40), [NSString stringWithFormat:@"pdf: page %d blue at its place %@", i, rgba(bl)]);
      check(near(wh, 255, 255, 255, 2) && wh[3] == 255, [NSString stringWithFormat:@"pdf: page %d white %@", i, rgba(wh)]);
      CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      CGContextRef c = CGBitmapContextCreate(px, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
      CGImageRef img = CGBitmapContextCreateImage(c);
      NSURL *u = [NSURL fileURLWithPath:[out_dir stringByAppendingPathComponent:@(pages[i].name)]];
      CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)u, CFSTR("public.png"), 1, NULL);
      CGImageDestinationAddImage(dst, img, NULL);
      CGImageDestinationFinalize(dst);
      CFRelease(dst);
      CGImageRelease(img);
      CGContextRelease(c);
      CGColorSpaceRelease(cs);
      free(px);
    }
    mb_host_image_free(im0);
    mb_host_image_free(im1);
    mb_host_pdf_close(doc);
    check(mb_host_pdf_pages(doc) == -1, @"pdf: closed");
    return YES;
  }];
}

static void save_steps(void) {
  [steps addObject:^BOOL(int t) {
    NSString *dir = [out_dir stringByAppendingPathComponent:@"downloads"];
    setenv("MBUI_DOWNLOADS_DIR", dir.fileSystemRepresentation, 1);
    int a = mb_host_save_file(mb_string_from_ns(@"notes.txt"), mbytes("one", 3));
    int b = mb_host_save_file(mb_string_from_ns(@"notes.txt"), mbytes("two", 3));
    int c = mb_host_save_file(mb_string_from_ns(@"../x/README"), mbytes("three", 5));
    NSString *s1 = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"notes.txt"] encoding:NSUTF8StringEncoding error:nil];
    NSString *s2 = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"notes (2).txt"] encoding:NSUTF8StringEncoding error:nil];
    NSString *s3 = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"README"] encoding:NSUTF8StringEncoding error:nil];
    check(a == 1 && b == 1 && c == 1 && [s1 isEqualToString:@"one"] && [s2 isEqualToString:@"two"] &&
              [s3 isEqualToString:@"three"],
          @"save: notes.txt, notes (2).txt, README (no directories)");
    return YES;
  }];
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 4) {
      fprintf(stderr, "selftest <out dir> <pdf> <file|mime|ms|w|h>...\n");
      return 2;
    }
    out_dir = @(argv[1]);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    // not napped in the background (its ticks would slow to a few a second)
    id activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityUserInitiated | NSActivityLatencyCritical
                                                               reason:@"self-test"];
    (void)activity;
    mb_render_init_offscreen(W, H, S);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, W, H)
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    box.wantsLayer = YES;
    NSView *under = mb_views_root(CGRectMake(0, 0, W, H));
    [box addSubview:under];
    win.contentView = box;
    [win orderFrontRegardless];
    steps = [NSMutableArray new];
    // test.mp4 is some 1.5 MB a second
    slow_steps([out_dir stringByAppendingPathComponent:@"test.mp4"], @"video/mp4", 0.75e6);
    for (int i = 3; i < argc; i++) {
      NSArray<NSString *> *a = [@(argv[i]) componentsSeparatedByString:@"|"];
      video_steps(a[0], a[1], a[2].doubleValue, a[3].doubleValue, a[4].doubleValue);
    }
    webm_steps([out_dir stringByAppendingPathComponent:@"test-vp9.webm"], @"video/webm");
    webm_steps([out_dir stringByAppendingPathComponent:@"test-vp8.webm"], @"video/webm");
    webm_steps([out_dir stringByAppendingPathComponent:@"test-vp9-opus.webm"], @"video/webm");
    vp9_mp4_steps([out_dir stringByAppendingPathComponent:@"test-vp9-aac.mp4"]);
    webm_steps([out_dir stringByAppendingPathComponent:@"test-vp9-aac.mp4"], @"video/mp4");
    webm_thumbnail_steps([out_dir stringByAppendingPathComponent:@"test-vp9.webm"], @"video/webm");
    webm_thumbnail_steps([out_dir stringByAppendingPathComponent:@"test-vp9-aac.mp4"], @"video/mp4");
    webm_large_steps([out_dir stringByAppendingPathComponent:@"test-large.webm"]);
    av1_mp4_steps([out_dir stringByAppendingPathComponent:@"test-av1.mp4"]);
    failure_steps([out_dir stringByAppendingPathComponent:@"test-vp9.webm"], @"video/webm", 2);
    failure_steps([out_dir stringByAppendingPathComponent:@"damaged.mp4"], @"video/webm", 3);
    failure_steps([out_dir stringByAppendingPathComponent:@"profile1.webm"], @"video/webm", 4);
    failure_steps([out_dir stringByAppendingPathComponent:@"test-av1.webm"], @"video/webm", 4);
    failure_steps([out_dir stringByAppendingPathComponent:@"test-av1-10bit.webm"], @"video/webm", 4);
    failure_steps([out_dir stringByAppendingPathComponent:@"test-theora.ogv"], @"video/ogg", 6);
    failure_steps([out_dir stringByAppendingPathComponent:@"test-hev1.mp4"], @"video/mp4", 5);
    failure_steps([out_dir stringByAppendingPathComponent:@"damaged.mp4"], @"video/mp4", 1);
    failure_steps([out_dir stringByAppendingPathComponent:@"test.mp4"], @"video/mp4", 2);
    web_steps();
    pdf_steps(@(argv[2]));
    save_steps();
    double start = CACurrentMediaTime();
    [NSTimer scheduledTimerWithTimeInterval:1.0 / 60
                                    repeats:YES
                                      block:^(NSTimer *tm) {
                                        if (steps.count == 0 || CACurrentMediaTime() - start > 180) {
                                          if (steps.count) check(NO, @"timed out");
                                          printf("SELFTEST %s (%d failed; frames asked %d)\n", fails ? "FAIL" : "PASS",
                                                 fails, frames_asked);
                                          fflush(stdout);
                                          exit(fails ? 1 : 0);
                                        }
                                        if (steps[0](step_tick++)) {
                                          [steps removeObjectAtIndex:0];
                                          step_tick = 0;
                                        }
                                      }];
    [NSApp run];
  }
  return 0;
}
