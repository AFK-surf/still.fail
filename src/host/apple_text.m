// Text with Core Text: shaping into grapheme clusters with their advances,
// and rasterizing each cluster into the RGBA atlas when it is first drawn.
#import "apple.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <math.h>

double mb_text_scale = 2.0;

typedef struct {
  double size;
  int weight;
  int style;  // 1 slanted, 2 the code face
  int done;
  double u, v, w, h, ox, oy;
  int color;
  // where the shaper put the cluster's glyph in its line, past where it starts on its own (a CJK bracket after
  // another, set half a width closer)
  double dx;
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

// The system font (style & 2: its monospaced face) at this size and weight;
// style & 1 its italic. A face without one (and what the cascade draws a
// cluster in, PingFang's Han) is slanted 12° as it is rasterized, as
// browsers synthesize an oblique.
static double last_size = -1;
static int last_weight = -1, last_style = -1;
static CTFontRef last_font;

// The serif face (style & 4): Songti SC (宋体, its Latin too) at the weight nearest; the system's face where there is
// no Songti.
static CTFontRef serif_font(double size, int weight) {
  NSString *face = weight >= 600 ? @"STSongti-SC-Bold" : weight <= 300 ? @"STSongti-SC-Light" : @"STSongti-SC-Regular";
  CTFontRef f = CTFontCreateWithName((__bridge CFStringRef)face, size, NULL);
  if (f) {
    CFStringRef got = CTFontCopyPostScriptName(f);
    BOOL ok = got && [(__bridge NSString *)got hasPrefix:@"STSongti"];
    if (got) CFRelease(got);
    if (ok) return f;
    CFRelease(f);
  }
  return mb_platform_font(size, weight, 0);
}

static CTFontRef font_for(double size, int weight, int style) {
  // the font asked for last, without building its key (most calls)
  if (size == last_size && weight == last_weight && style == last_style) return last_font;
  if (!fonts) fonts = [NSMutableDictionary new];
  NSString *k = [NSString stringWithFormat:@"%g/%d/%d", size, weight, style];
  id f = fonts[k];
  if (!f) {
    CTFontRef base = (style & 4) && !(style & 2) ? serif_font(size, weight) : mb_platform_font(size, weight, (style & 2) != 0);
    if (style & 1) {
      CTFontRef it = CTFontCreateCopyWithSymbolicTraits(base, 0, NULL, kCTFontTraitItalic, kCTFontTraitItalic);
      if (it) {
        CFRelease(base);
        base = it;
      }
    }
    f = (__bridge_transfer id)base;
    fonts[k] = f;
  }
  // kept alive by `fonts`
  last_size = size;
  last_weight = weight;
  last_style = style;
  last_font = (__bridge CTFontRef)f;
  return last_font;
}

void mb_host_font_metrics(double size, int32_t weight, int32_t style, double *out) {
  CTFontRef f = font_for(size, weight, style);
  out[0] = CTFontGetAscent(f);
  out[1] = CTFontGetDescent(f);
  out[2] = round(size * 1.42);
  // the font a Han ideograph falls back to: a line with Chinese in it is measured by the taller of the two (the system
  // font's is .PingFangUITextSC, made to the San Francisco's ascent and descent: the same numbers, macOS 26)
  CTFontRef han = CTFontCreateForString(f, CFSTR("\u56FD"), CFRangeMake(0, 1));
  out[3] = han ? CTFontGetAscent(han) : out[0];
  out[4] = han ? CTFontGetDescent(han) : out[1];
  if (han) CFRelease(han);
  out[5] = 0;  // lines as asked, not on whole pixels
}

// style & 8: no ligatures (words with letter spacing, each cluster spaced on its own)
static CTLineRef make_line(NSString *s, CTFontRef f, int style) {
  NSDictionary *attrs = (style & 8) ? @{
    (__bridge id)kCTFontAttributeName : (__bridge id)f,
    (__bridge id)kCTForegroundColorFromContextAttributeName : @YES,
    (__bridge id)kCTLigatureAttributeName : @0,
  } : @{
    (__bridge id)kCTFontAttributeName : (__bridge id)f,
    (__bridge id)kCTForegroundColorFromContextAttributeName : @YES,
  };
  NSAttributedString *as = [[NSAttributedString alloc] initWithString:s attributes:attrs];
  return CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)as);
}

static int intern_at(NSString *cluster, double size, int weight, int style, double dx) {
  if (!keys) {
    keys = [NSMutableDictionary new];
    texts = [NSMutableArray new];
  }
  NSString *k = dx == 0 ? [NSString stringWithFormat:@"%@\x01%g\x01%d\x01%d", cluster, size, weight, style]
                        : [NSString stringWithFormat:@"%@\x01%g\x01%d\x01%d\x01%.3f", cluster, size, weight, style, dx];
  NSNumber *n = keys[k];
  if (n) return n.intValue;
  if (n_entries == cap_entries) {
    cap_entries = cap_entries ? cap_entries * 2 : 1024;
    entries = realloc(entries, sizeof(glyph_entry) * cap_entries);
  }
  int id_ = n_entries++;
  entries[id_] = (glyph_entry){size, weight, style, 0, 0, 0, 0, 0, 0, 0, 0, dx};
  [texts addObject:cluster];
  keys[k] = @(id_);
  return id_;
}

static int intern(NSString *cluster, double size, int weight, int style) {
  return intern_at(cluster, size, weight, style, 0);
}

// The keys of ASCII clusters, per font, found without building a string
// for the cluster and its key.
typedef struct {
  double size;
  int weight, style;
  int ids[128];
} ascii_keys;
static ascii_keys *ascii;
static int n_ascii, last_ascii = -1;

static int *ascii_for(double size, int weight, int style) {
  if (last_ascii >= 0) {
    ascii_keys *a = &ascii[last_ascii];
    if (a->size == size && a->weight == weight && a->style == style) return a->ids;
  }
  for (int i = 0; i < n_ascii; i++) {
    if (ascii[i].size == size && ascii[i].weight == weight && ascii[i].style == style) {
      last_ascii = i;
      return ascii[i].ids;
    }
  }
  ascii = realloc(ascii, sizeof(ascii_keys) * (n_ascii + 1));
  ascii_keys *a = &ascii[n_ascii];
  a->size = size;
  a->weight = weight;
  a->style = style;
  for (int i = 0; i < 128; i++) a->ids[i] = -1;
  last_ascii = n_ascii++;
  return a->ids;
}

// The key of an ASCII cluster (not a space) in this font.
static int ascii_key(unichar c, double size, int weight, int style) {
  int *ids = ascii_for(size, weight, style);
  if (ids[c] < 0) ids[c] = intern([NSString stringWithCharacters:&c length:1], size, weight, style);
  return ids[c];
}

// The fast path for printable ASCII (after nanoui's shaper.zig): each
// character's advance and each pair's kerning learned once from Core Text,
// so a string of them is laid out with lookups instead of a CTLine. A pair
// Core Text makes something else of (a ligature, an alternate that changes
// an advance) sends the string down the slow path. MBUI_SHAPE_CHECK=1
// compares the two on every string and reports where they differ.
enum { ascii_first = 0x20, ascii_n = 0x7f - 0x20 };
typedef struct {
  double size;
  int weight, style;
  double adv[ascii_n];
  unsigned char adv_known[ascii_n];
  // per pair: 0 not asked yet, 1 kerned by kern[], 2 Core Text's own
  unsigned char pair[ascii_n * ascii_n];
  double kern[ascii_n * ascii_n];
} ascii_metrics;
static ascii_metrics **metrics;
static int n_metrics, last_metrics = -1;

static ascii_metrics *metrics_for(double size, int weight, int style) {
  if (last_metrics >= 0) {
    ascii_metrics *m = metrics[last_metrics];
    if (m->size == size && m->weight == weight && m->style == style) return m;
  }
  for (int i = 0; i < n_metrics; i++) {
    ascii_metrics *m = metrics[i];
    if (m->size == size && m->weight == weight && m->style == style) {
      last_metrics = i;
      return m;
    }
  }
  ascii_metrics *m = calloc(1, sizeof(ascii_metrics));
  m->size = size;
  m->weight = weight;
  m->style = style;
  metrics = realloc(metrics, sizeof(ascii_metrics *) * (n_metrics + 1));
  metrics[n_metrics] = m;
  last_metrics = n_metrics++;
  return m;
}

static CFIndex glyph_count(CTLineRef line) {
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  CFIndex n = 0, k = CFArrayGetCount(runs);
  for (CFIndex i = 0; i < k; i++) n += CTRunGetGlyphCount(CFArrayGetValueAtIndex(runs, i));
  return k == 1 ? n : -1;
}

static double ascii_adv(ascii_metrics *m, CTFontRef f, unichar c) {
  int a = c - ascii_first;
  if (!m->adv_known[a]) {
    CTLineRef line = make_line([NSString stringWithCharacters:&c length:1], f, m->style);
    m->adv[a] = CTLineGetOffsetForStringIndex(line, 1, NULL);
    m->adv_known[a] = 1;
    CFRelease(line);
  }
  return m->adv[a];
}

// What a pair adds to its first character's advance; 0 for a pair Core
// Text has to lay out itself (*ok cleared).
static double ascii_kern(ascii_metrics *m, CTFontRef f, unichar c1, unichar c2, int *ok) {
  int k = (c1 - ascii_first) * ascii_n + (c2 - ascii_first);
  if (!m->pair[k]) {
    double a1 = ascii_adv(m, f, c1), a2 = ascii_adv(m, f, c2);
    unichar both[2] = {c1, c2};
    CTLineRef line = make_line([NSString stringWithCharacters:both length:2], f, m->style);
    double o1 = CTLineGetOffsetForStringIndex(line, 1, NULL);
    double o2 = CTLineGetOffsetForStringIndex(line, 2, NULL);
    m->pair[k] = glyph_count(line) == 2 && fabs(o2 - o1 - a2) < 1e-9 ? 1 : 2;
    m->kern[k] = o1 - a1;
    CFRelease(line);
  }
  if (m->pair[k] != 1) *ok = 0;
  return m->kern[k];
}

static int32_t shape_ascii(const unichar *t, int32_t len, double size, int weight, int style, double *out) {
  CTFontRef f = font_for(size, weight, style);
  ascii_metrics *m = metrics_for(size, weight, style);
  int ok = 1;
  for (int32_t i = 0; i < len && ok; i++) {
    double adv = ascii_adv(m, f, t[i]);
    if (i + 1 < len) adv += ascii_kern(m, f, t[i], t[i + 1], &ok);
    out[i * 4] = i;
    out[i * 4 + 1] = 1;
    out[i * 4 + 2] = adv < 0 ? 0 : adv;
    out[i * 4 + 3] = t[i] == ' ' ? -1 : ascii_key(t[i], size, weight, style);
  }
  return ok ? len : -1;
}

static int32_t shape_slow(moonbit_string_t text, int32_t len, double size, int32_t weight, int32_t style,
                          double *out, int32_t cap) {
  NSString *s = [[NSString alloc] initWithCharacters:(const unichar *)text length:len];
  CTFontRef f = font_for(size, weight, style);
  CTLineRef line = make_line(s, f, style);
  // where Core Text's glyphs come from in the text: a cluster none comes from is part of the glyph before it (a
  // ligature), drawn by that cluster (-2 tells MoonBit, which gives the ligature to the first of them)
  uint8_t *from = calloc((size_t)len + 1, 1);
  // In a line with right-to-left text, a caret offset is where a character is from the line's start in a reading
  // order of its own, not what it advances: there each cluster advances as far as its glyphs do, each glyph to
  // where the next one in the run starts (the run's glyphs are in visual order), counted to where it comes from
  int any_rtl = 0;
  double *glyph_adv = calloc((size_t)len + 1, sizeof(double));
  // where the first glyph from each character is in the line (NAN: none), left to right
  double *glyph_x = malloc(sizeof(double) * ((size_t)len + 1));
  for (int32_t j = 0; j <= len; j++) glyph_x[j] = NAN;
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  for (CFIndex r = 0; r < CFArrayGetCount(runs); r++) {
    CTRunRef run = CFArrayGetValueAtIndex(runs, r);
    CFIndex gc = CTRunGetGlyphCount(run);
    CFIndex *idx = malloc(sizeof(CFIndex) * (gc > 0 ? gc : 1));
    CGPoint *pos = malloc(sizeof(CGPoint) * (gc > 0 ? gc : 1));
    CTRunGetStringIndices(run, CFRangeMake(0, 0), idx);
    CTRunGetPositions(run, CFRangeMake(0, 0), pos);
    double w = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), NULL, NULL, NULL);
    if (CTRunGetStatus(run) & kCTRunStatusRightToLeft) any_rtl = 1;
    for (CFIndex g = 0; g < gc; g++) {
      if (idx[g] < 0 || idx[g] >= len) continue;
      from[idx[g]] = 1;
      if (isnan(glyph_x[idx[g]]) || pos[g].x < glyph_x[idx[g]]) glyph_x[idx[g]] = pos[g].x;
      double next = g + 1 < gc ? pos[g + 1].x : pos[0].x + w;
      glyph_adv[idx[g]] += next - pos[g].x;
    }
    free(idx);
    free(pos);
  }
  int32_t k = 0;
  NSUInteger i = 0;
  // a cluster starts where the one before it ended
  double x0 = CTLineGetOffsetForStringIndex(line, 0, NULL);
  while (i < (NSUInteger)len && k < cap) {
    NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:i];
    unichar c = [s characterAtIndex:r.location];
    if (r.location != i) x0 = CTLineGetOffsetForStringIndex(line, r.location, NULL);
    double start_x = x0;
    double x1 = CTLineGetOffsetForStringIndex(line, r.location + r.length, NULL);
    double adv = x1 - x0;
    x0 = x1;
    if (any_rtl) {
      adv = 0;
      for (NSUInteger j = r.location; j < r.location + r.length; j++) adv += glyph_adv[j];
    }
    int key;
    if (c == '\n') {
      adv = 0;
      key = -1;
    } else if (c == ' ' || c == '\t') {
      key = -1;
    } else {
      int drawn = 0;
      for (NSUInteger j = r.location; j < r.location + r.length; j++) drawn |= from[j];
      if (!drawn && k > 0)
        key = -2;
      else if (r.length == 1 && c < 128)
        key = ascii_key(c, size, weight, style);
      else {
        // a glyph the shaper moved within its cluster's advance (contextual spacing of CJK punctuation): drawn
        // there, not where it sits on its own
        // (the leftmost of its glyphs: a vowel sign the shaper put before its consonant is where it starts)
        double gx = NAN;
        for (NSUInteger j = r.location; j < r.location + r.length; j++)
          if (!isnan(glyph_x[j]) && (isnan(gx) || glyph_x[j] < gx)) gx = glyph_x[j];
        double dx = any_rtl || isnan(gx) ? 0 : gx - start_x;
        if (fabs(dx) < 0.01) dx = 0;
        key = intern_at([s substringWithRange:r], size, weight, style, dx);
      }
    }
    out[k * 4] = r.location;
    out[k * 4 + 1] = r.length;
    out[k * 4 + 2] = adv < 0 ? 0 : adv;
    out[k * 4 + 3] = key;
    k++;
    i = r.location + r.length;
  }
  free(from);
  free(glyph_adv);
  free(glyph_x);
  CFRelease(line);
  return k;
}

// The key of a piece of text drawn whole (a word of a joining script, a ligature): host_native.mbt's text_key.
int32_t mb_host_text_key(moonbit_string_t text, double size, int32_t weight, int32_t style) {
  @autoreleasepool {
    return intern(mb_ns_from_string(text), size, weight, style);
  }
}

static int shape_check = -1;

int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, int32_t style, double *out) {
  @autoreleasepool {
    int32_t len = Moonbit_array_length(text);
    int32_t cap = Moonbit_array_length(out) / 4;
    const unichar *t = (const unichar *)text;
    int ascii = len > 0 && len <= cap;
    for (int32_t i = 0; i < len && ascii; i++) ascii = t[i] >= ascii_first && t[i] < 0x7f;
    if (ascii) {
      int32_t n = shape_ascii(t, len, size, weight, style, out);
      if (n >= 0) {
        if (shape_check < 0) shape_check = getenv("MBUI_SHAPE_CHECK") != NULL;
        if (shape_check) {
          double *ref = malloc(sizeof(double) * 4 * len);
          shape_slow(text, len, size, weight, style, ref, len);
          for (int32_t i = 0; i < len; i++) {
            if (fabs(ref[i * 4 + 2] - out[i * 4 + 2]) > 1e-9 || ref[i * 4 + 3] != out[i * 4 + 3]) {
              NSLog(@"shape check: \"%@\" at %g/%d/%d: cluster %d %.6f, Core Text %.6f",
                    [NSString stringWithCharacters:t length:len], size, weight, style, i,
                    out[i * 4 + 2], ref[i * 4 + 2]);
              break;
            }
          }
          free(ref);
        }
        return n;
      }
    }
    return shape_slow(text, len, size, weight, style, out, cap);
  }
}

int32_t mb_host_atlas_generation(void) { return generation; }

static void rasterize(int key) {
  glyph_entry *e = &entries[key];
  e->done = 1;
  NSString *cluster = texts[key];
  CTFontRef f = font_for(e->size, e->weight, e->style);
  CTLineRef line = make_line(cluster, f, e->style);
  double sc = mb_text_scale;
  // is it drawn from a color font (emoji)? slanted, from a face with no italic?
  int color = 0, oblique = 0;
  const double slant = 0.2126;  // tan 12°
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  if (CFArrayGetCount(runs) > 0) {
    CTRunRef run = CFArrayGetValueAtIndex(runs, 0);
    CTFontRef rf = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
    CTFontSymbolicTraits traits = rf ? CTFontGetSymbolicTraits(rf) : 0;
    if (traits & kCTFontTraitColorGlyphs) color = 1;
    if ((e->style & 1) && !color && !(traits & kCTFontTraitItalic)) oblique = 1;
  }
  CGRect b = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
  if (color || b.size.width <= 0 || b.size.height <= 0) {
    CGFloat asc, desc;
    double w = CTLineGetTypographicBounds(line, &asc, &desc, NULL);
    b = CGRectMake(0, -desc, w, asc + desc);
  }
  if (oblique) {
    // what is above the baseline leans right, what is below left
    double top = b.origin.y + b.size.height, bottom = b.origin.y;
    double l = b.origin.x + (bottom < 0 ? slant * bottom : 0);
    double r = b.origin.x + b.size.width + (top > 0 ? slant * top : 0);
    b = CGRectMake(l, b.origin.y, r - l, b.size.height);
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
  CGContextSetTextMatrix(ctx, oblique ? CGAffineTransformMake(1, 0, slant, 1, 0, 0) : CGAffineTransformIdentity);
  CGContextSetTextPosition(ctx, -b.origin.x, -b.origin.y);
  CTLineDraw(line, ctx);
  mb_atlas_upload(pack_x, pack_y, pw, ph, px);
  e->u = pack_x;
  e->v = pack_y;
  e->w = pw / sc;
  e->h = ph / sc;
  e->ox = b.origin.x;
  if (e->dx != 0) {
    // moved by as much as its glyphs sit further right in the line than they do on their own
    double iso = NAN;
    for (CFIndex r = 0; r < CFArrayGetCount(runs); r++) {
      CTRunRef run = CFArrayGetValueAtIndex(runs, r);
      CFIndex gc = CTRunGetGlyphCount(run);
      CGPoint *pos = malloc(sizeof(CGPoint) * (gc > 0 ? gc : 1));
      CTRunGetPositions(run, CFRangeMake(0, 0), pos);
      for (CFIndex g = 0; g < gc; g++)
        if (isnan(iso) || pos[g].x < iso) iso = pos[g].x;
      free(pos);
    }
    e->ox += e->dx - (isnan(iso) ? 0 : iso);
  }
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

// ---------------------------------------------------------------------------
// The platform's own drawing of a line (textref_native.mbt, for src/textdiff): Core Text's CTLineDraw into a bitmap
// context, the same fonts as above and the same rasterizer settings (no font smoothing), so what differs from
// mbui's picture is where and how mbui puts each cluster.

static CGContextRef ref_ctx;
static uint8_t *ref_px;
static double ref_h, ref_sc;

static void ref_path(NSString *name, char *out, size_t cap) {
  const char *dir = getenv("MBUI_SHOT_DIR");
  snprintf(out, cap, "%s/%s.png", dir ? dir : ".", name.UTF8String);
}

void mb_host_ref_begin(double w, double h, double scale, int32_t bg) {
  if (ref_ctx) {
    CGContextRelease(ref_ctx);
    free(ref_px);
  }
  int pw = (int)round(w * scale), ph = (int)round(h * scale);
  ref_px = calloc((size_t)pw * ph * 4, 1);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  ref_ctx = CGBitmapContextCreate(ref_px, pw, ph, 8, (size_t)pw * 4, cs, kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(cs);
  CGContextSetRGBFillColor(ref_ctx, ((bg >> 16) & 255) / 255.0, ((bg >> 8) & 255) / 255.0, (bg & 255) / 255.0, 1);
  CGContextFillRect(ref_ctx, CGRectMake(0, 0, pw, ph));
  CGContextScaleCTM(ref_ctx, scale, scale);
  CGContextSetShouldSmoothFonts(ref_ctx, false);
  ref_h = h;
  ref_sc = scale;
}

void mb_host_ref_text(moonbit_string_t text, double size, int32_t weight, int32_t style, double x, double base,
                      int32_t color, double *out) {
  @autoreleasepool {
    for (int i = 0; i < 5; i++) out[i] = 0;
    if (!ref_ctx) return;
    CTLineRef line = make_line(mb_ns_from_string(text), font_for(size, weight, style), style);
    CGContextSetRGBFillColor(ref_ctx, ((color >> 16) & 255) / 255.0, ((color >> 8) & 255) / 255.0,
                             (color & 255) / 255.0, 1);
    CGContextSetTextMatrix(ref_ctx, CGAffineTransformIdentity);
    CGContextSetTextPosition(ref_ctx, x, ref_h - base);
    CTLineDraw(line, ref_ctx);
    out[0] = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CGRect b = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    out[1] = b.origin.x;
    out[2] = -(b.origin.y + b.size.height);
    out[3] = b.origin.x + b.size.width;
    out[4] = -b.origin.y;
    CFRelease(line);
  }
}

int32_t mb_host_ref_end(moonbit_string_t name) {
  @autoreleasepool {
    if (!ref_ctx) return 0;
    char path[4096];
    ref_path(mb_ns_from_string(name), path, sizeof path);
    CGImageRef img = CGBitmapContextCreateImage(ref_ctx);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    int ok = 0;
    if (dst) {
      CGImageDestinationAddImage(dst, img, NULL);
      ok = CGImageDestinationFinalize(dst);
      CFRelease(dst);
    }
    CFRelease(url);
    CGImageRelease(img);
    CGContextRelease(ref_ctx);
    free(ref_px);
    ref_ctx = NULL;
    ref_px = NULL;
    return ok;
  }
}

int32_t mb_host_ref_frame(moonbit_string_t name) {
  @autoreleasepool {
    char path[4096];
    ref_path(mb_ns_from_string(name), path, sizeof path);
    return mb_render_snapshot(path);
  }
}

// The word around a UTF-16 offset as the system finds words (@host.word_at): CFStringTokenizer's word boundaries (a
// dictionary's words in Chinese and Japanese); start × 2^32 + end, or -1 when there is none there.
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  NSString *s = mb_ns_from_string(text);
  if (off < 0 || (NSUInteger)off >= s.length) return -1;
  CFLocaleRef loc = CFLocaleCopyCurrent();
  CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, (__bridge CFStringRef)s, CFRangeMake(0, (CFIndex)s.length),
                                                     kCFStringTokenizerUnitWordBoundary, loc);
  CFRelease(loc);
  if (!tok) return -1;
  CFStringTokenizerTokenType type = CFStringTokenizerGoToTokenAtIndex(tok, off);
  double out = -1;
  if (type != kCFStringTokenizerTokenNone) {
    CFRange r = CFStringTokenizerGetCurrentTokenRange(tok);
    if (r.location != kCFNotFound && r.length > 0) out = (double)r.location * 4294967296.0 + (double)(r.location + r.length);
  }
  CFRelease(tok);
  return out;
}
