// Text with Core Text: shaping into grapheme clusters with their advances,
// and rasterizing each cluster into the RGBA atlas when it is first drawn.
#import "apple.h"
#import <CoreGraphics/CoreGraphics.h>

double mb_text_scale = 2.0;

typedef struct {
  double size;
  int weight;
  int done;
  double u, v, w, h, ox, oy;
  int color;
} glyph_entry;

static NSMutableDictionary<NSString *, NSNumber *> *keys;
static NSMutableArray<NSString *> *texts;
static glyph_entry *entries;
static int n_entries, cap_entries;
static NSMutableDictionary<NSString *, id> *fonts;
static int pack_x, pack_y, pack_h;
static int generation;

moonbit_string_t mb_string_from_ns(NSString *s) {
  NSUInteger n = s.length;
  moonbit_string_t out = moonbit_make_string_raw((int32_t)n);
  [s getCharacters:(unichar *)out range:NSMakeRange(0, n)];
  return out;
}

NSString *mb_ns_from_string(moonbit_string_t s) {
  return [[NSString alloc] initWithCharacters:(const unichar *)s length:Moonbit_array_length(s)];
}

static CTFontRef font_for(double size, int weight) {
  if (!fonts) fonts = [NSMutableDictionary new];
  NSString *k = [NSString stringWithFormat:@"%g/%d", size, weight];
  id f = fonts[k];
  if (!f) {
    f = (__bridge_transfer id)mb_platform_font(size, weight);
    fonts[k] = f;
  }
  return (__bridge CTFontRef)f;
}

void mb_host_font_metrics(double size, int32_t weight, double *out) {
  CTFontRef f = font_for(size, weight);
  out[0] = CTFontGetAscent(f);
  out[1] = CTFontGetDescent(f);
  out[2] = round(size * 1.42);
}

static CTLineRef make_line(NSString *s, CTFontRef f) {
  NSDictionary *attrs = @{
    (__bridge id)kCTFontAttributeName : (__bridge id)f,
    (__bridge id)kCTForegroundColorFromContextAttributeName : @YES,
  };
  NSAttributedString *as = [[NSAttributedString alloc] initWithString:s attributes:attrs];
  return CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)as);
}

static int intern(NSString *cluster, double size, int weight) {
  if (!keys) {
    keys = [NSMutableDictionary new];
    texts = [NSMutableArray new];
  }
  NSString *k = [NSString stringWithFormat:@"%@\x01%g\x01%d", cluster, size, weight];
  NSNumber *n = keys[k];
  if (n) return n.intValue;
  if (n_entries == cap_entries) {
    cap_entries = cap_entries ? cap_entries * 2 : 1024;
    entries = realloc(entries, sizeof(glyph_entry) * cap_entries);
  }
  int id_ = n_entries++;
  entries[id_] = (glyph_entry){size, weight, 0, 0, 0, 0, 0, 0, 0, 0};
  [texts addObject:cluster];
  keys[k] = @(id_);
  return id_;
}

int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, double *out) {
  @autoreleasepool {
    int32_t len = Moonbit_array_length(text);
    int32_t cap = Moonbit_array_length(out) / 4;
    NSString *s = [[NSString alloc] initWithCharacters:(const unichar *)text length:len];
    CTFontRef f = font_for(size, weight);
    CTLineRef line = make_line(s, f);
    int32_t k = 0;
    NSUInteger i = 0;
    while (i < (NSUInteger)len && k < cap) {
      NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:i];
      unichar c = [s characterAtIndex:r.location];
      double x0 = CTLineGetOffsetForStringIndex(line, r.location, NULL);
      double x1 = CTLineGetOffsetForStringIndex(line, r.location + r.length, NULL);
      double adv = x1 - x0;
      int key;
      if (c == '\n') {
        adv = 0;
        key = -1;
      } else if (c == ' ' || c == '\t') {
        key = -1;
      } else {
        key = intern([s substringWithRange:r], size, weight);
      }
      out[k * 4] = r.location;
      out[k * 4 + 1] = r.length;
      out[k * 4 + 2] = adv < 0 ? 0 : adv;
      out[k * 4 + 3] = key;
      k++;
      i = r.location + r.length;
    }
    CFRelease(line);
    return k;
  }
}

int32_t mb_host_atlas_generation(void) { return generation; }

static void rasterize(int key) {
  glyph_entry *e = &entries[key];
  e->done = 1;
  NSString *cluster = texts[key];
  CTFontRef f = font_for(e->size, e->weight);
  CTLineRef line = make_line(cluster, f);
  double sc = mb_text_scale;
  // is it drawn from a color font (emoji)?
  int color = 0;
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  if (CFArrayGetCount(runs) > 0) {
    CTRunRef run = CFArrayGetValueAtIndex(runs, 0);
    CTFontRef rf = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
    if (rf && (CTFontGetSymbolicTraits(rf) & kCTFontTraitColorGlyphs)) color = 1;
  }
  CGRect b = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
  if (color || b.size.width <= 0 || b.size.height <= 0) {
    CGFloat asc, desc;
    double w = CTLineGetTypographicBounds(line, &asc, &desc, NULL);
    b = CGRectMake(0, -desc, w, asc + desc);
  }
  // The bitmap's edges on whole pixels from the baseline, a pixel of room
  // around: the baseline then falls on a pixel row of every glyph's bitmap,
  // so glyphs placed on the same rounded baseline line up (rounding each
  // glyph's own fractional top made them wander up and down a pixel).
  int x0 = (int)floor(b.origin.x * sc) - 1, y0 = (int)floor(b.origin.y * sc) - 1;
  int x1 = (int)ceil((b.origin.x + b.size.width) * sc) + 1;
  int y1 = (int)ceil((b.origin.y + b.size.height) * sc) + 1;
  b = CGRectMake(x0 / sc, y0 / sc, (x1 - x0) / sc, (y1 - y0) / sc);
  int pw = x1 - x0, ph = y1 - y0;
  if (pw <= 0 || ph <= 0 || pw > 512 || ph > 512) {
    CFRelease(line);
    return;
  }
  if (pack_x + pw + 1 > mb_atlas_size) {
    pack_x = 0;
    pack_y += pack_h + 1;
    pack_h = 0;
  }
  if (pack_y + ph + 1 > mb_atlas_size) {
    // full: start over; MoonBit drops its glyph cache when the generation changes
    for (int i = 0; i < n_entries; i++) entries[i].done = 0;
    e->done = 1;
    pack_x = pack_y = pack_h = 0;
    generation++;
  }
  size_t bpr = (size_t)pw * 4;
  uint8_t *px = calloc(bpr * ph, 1);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(px, pw, ph, 8, bpr, cs, kCGImageAlphaPremultipliedLast);
  CGContextScaleCTM(ctx, sc, sc);
  CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
  CGContextSetShouldSmoothFonts(ctx, false);
  CGContextSetTextPosition(ctx, -b.origin.x, -b.origin.y);
  CTLineDraw(line, ctx);
  mb_atlas_upload(pack_x, pack_y, pw, ph, px);
  e->u = pack_x;
  e->v = pack_y;
  e->w = pw / sc;
  e->h = ph / sc;
  e->ox = b.origin.x;
  e->oy = -(b.origin.y + b.size.height);
  e->color = color;
  pack_x += pw + 1;
  if (ph > pack_h) pack_h = ph;
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  free(px);
  CFRelease(line);
}

void mb_host_glyph(int32_t key, double *out) {
  @autoreleasepool {
    if (key < 0 || key >= n_entries) {
      for (int i = 0; i < 7; i++) out[i] = 0;
      return;
    }
    if (!entries[key].done) rasterize(key);
    glyph_entry *e = &entries[key];
    out[0] = e->u;
    out[1] = e->v;
    out[2] = e->w;
    out[3] = e->h;
    out[4] = e->ox;
    out[5] = e->oy;
    out[6] = e->color;
  }
}
