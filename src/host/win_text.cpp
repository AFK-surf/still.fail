// Text with DirectWrite: shaping into clusters with their advances, and
// rasterizing each cluster with Direct2D into the RGBA atlas when it is first
// drawn. Segoe UI, with Han, kana and CJK punctuation mapped to Microsoft
// YaHei UI ahead of the system fallback (which supplies Segoe UI Emoji).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <dwrite_2.h>
#include <d2d1.h>
#include <wincodec.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "windowscodecs.lib")

static const WCHAR *FAMILY = L"Segoe UI";
static const WCHAR *MONO = L"Consolas";  // the code face (style & 2)
static const WCHAR *SERIF = L"SimSun";   // the serif face (style & 4): 宋体, its Latin too
static const int RT_SIZE = 512;  // largest cluster bitmap, in pixels

typedef struct {
  int off, len;  // the cluster's text in pool
  double size;
  int weight;
  int style;  // 1 italic, 2 the code face
  int done;
  double u, v, w, h, ox, oy;
  int color;
} glyph_entry;

static IDWriteFactory2 *dw;
static IDWriteFontFallback *fallback;
static IDWriteRenderingParams *params;
static ID2D1Factory *d2d;
static IWICImagingFactory *wic;
static IWICBitmap *bitmap;
static ID2D1RenderTarget *rt;
static ID2D1SolidColorBrush *white;
static double text_scale = 1, rt_scale;
static glyph_entry *entries;
static int n_entries, cap_entries;
static WCHAR *pool;
static size_t pool_len, pool_cap;
static int *table;  // open addressing: entry index + 1, 0 is empty
static size_t table_cap;
static int pack_x, pack_y, pack_h;
static int generation;
static struct { double size; int weight; int style; IDWriteTextFormat *f; } formats[32];
static int n_formats;

static void init(void) {
  if (dw) return;
  DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory2), (IUnknown **)&dw);
  IDWriteFontFallbackBuilder *b = NULL;
  IDWriteFontFallback *sys = NULL;
  dw->CreateFontFallbackBuilder(&b);
  DWRITE_UNICODE_RANGE cjk[] = {
      {0x2E80, 0x2FDF}, {0x3000, 0x31FF}, {0x3200, 0x4DBF},   {0x4E00, 0x9FFF},
      {0xF900, 0xFAFF}, {0xFE30, 0xFE4F}, {0xFF00, 0xFFEF}, {0x20000, 0x3FFFF},
  };
  const WCHAR *cjk_fonts[] = {L"Microsoft YaHei UI", L"Microsoft YaHei", L"SimSun"};
  b->AddMapping(cjk, sizeof cjk / sizeof cjk[0], cjk_fonts, 3, NULL, NULL, NULL, 1.0f);
  dw->GetSystemFontFallback(&sys);
  b->AddMappings(sys);
  b->CreateFontFallback(&fallback);
  sys->Release();
  b->Release();
  // the font's own features, ligatures with them, as DirectWrite draws any app's text: a ligature is one
  // cluster of its letters (GetClusterMetrics), drawn whole
  // plain coverage without hinting or contrast boost, like Core Text with
  // smoothing off
  IDWriteRenderingParams2 *p2 = NULL;
  dw->CreateCustomRenderingParams(1.0f, 0.0f, 0.0f, 0.0f, DWRITE_PIXEL_GEOMETRY_FLAT,
                                  DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC,
                                  DWRITE_GRID_FIT_MODE_DISABLED, &p2);
  params = p2;
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), NULL, (void **)&d2d);
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory),
                   (void **)&wic);
  wic->CreateBitmap(RT_SIZE, RT_SIZE, GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnDemand, &bitmap);
}

static IDWriteTextFormat *format_for(double size, int weight, int style) {
  for (int i = 0; i < n_formats; i++)
    if (formats[i].size == size && formats[i].weight == weight && formats[i].style == style) return formats[i].f;
  IDWriteTextFormat *f = NULL;
  dw->CreateTextFormat((style & 2) ? MONO : (style & 4) ? SERIF : FAMILY, NULL, (DWRITE_FONT_WEIGHT)weight,
                       (style & 1) ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL,
                       DWRITE_FONT_STRETCH_NORMAL, (FLOAT)size, L"zh-cn", &f);
  f->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  if (n_formats == 32) {
    formats[0].f->Release();
    formats[0] = formats[--n_formats];
  }
  formats[n_formats].size = size;
  formats[n_formats].weight = weight;
  formats[n_formats].style = style;
  formats[n_formats++].f = f;
  return f;
}

// style & 8: no ligatures (words with letter spacing, each cluster spaced on its own): liga and clig off
static IDWriteTypography *no_ligatures;

static void set_style_features(IDWriteTextLayout *l, int len, int style) {
  if (!(style & 8)) return;
  if (!no_ligatures) {
    dw->CreateTypography(&no_ligatures);
    no_ligatures->AddFontFeature({DWRITE_FONT_FEATURE_TAG_STANDARD_LIGATURES, 0});
    no_ligatures->AddFontFeature({DWRITE_FONT_FEATURE_TAG_CONTEXTUAL_LIGATURES, 0});
  }
  l->SetTypography(no_ligatures, {0, (UINT32)len});
}

static IDWriteTextLayout *make_layout(const WCHAR *s, int len, double size, int weight, int style) {
  IDWriteTextLayout *l = NULL;
  dw->CreateTextLayout(s, (UINT32)len, format_for(size, weight, style), 1e6f, 1e6f, &l);
  IDWriteTextLayout2 *l2 = NULL;
  if (SUCCEEDED(l->QueryInterface(__uuidof(IDWriteTextLayout2), (void **)&l2))) {
    l2->SetFontFallback(fallback);
    l2->Release();
  }
  set_style_features(l, len, style);
  return l;
}

// A family's metrics at this weight and style (false: not on this system, `m` as it was).
static bool family_metrics(const WCHAR *name, int weight, int style, DWRITE_FONT_METRICS *m) {
  IDWriteFontCollection *fc = NULL;
  IDWriteFontFamily *fam = NULL;
  IDWriteFont *font = NULL;
  UINT32 i = 0;
  BOOL found = FALSE;
  bool ok = false;
  dw->GetSystemFontCollection(&fc, FALSE);
  if (SUCCEEDED(fc->FindFamilyName(name, &i, &found)) && found && SUCCEEDED(fc->GetFontFamily(i, &fam)) &&
      SUCCEEDED(fam->GetFirstMatchingFont((DWRITE_FONT_WEIGHT)weight, DWRITE_FONT_STRETCH_NORMAL,
                                          (style & 1) ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL, &font))) {
    font->GetMetrics(m);
    ok = true;
  }
  if (font) font->Release();
  if (fam) fam->Release();
  fc->Release();
  return ok;
}

extern "C" void mb_host_font_metrics(double size, int32_t weight, int32_t style, double *out) {
  init();
  DWRITE_FONT_METRICS m = {};
  m.designUnitsPerEm = 2048;
  m.ascent = 2210;
  m.descent = 514;
  family_metrics((style & 2) ? MONO : (style & 4) ? SERIF : FAMILY, weight, style, &m);
  out[0] = size * m.ascent / m.designUnitsPerEm;
  out[1] = size * m.descent / m.designUnitsPerEm;
  out[2] = round(size * 1.42);
  // the face Han falls back to (Chinese Windows' UI font): a line with Chinese in it is measured by the taller
  DWRITE_FONT_METRICS h = m;
  family_metrics(L"Microsoft YaHei UI", weight, style, &h);
  out[3] = size * h.ascent / h.designUnitsPerEm;
  out[4] = size * h.descent / h.designUnitsPerEm;
  out[5] = 0;  // lines as asked, not on whole pixels
}

static uint32_t hash(const WCHAR *s, int len, double size, int weight, int style) {
  uint32_t h = 2166136261u;
  for (int i = 0; i < len; i++) h = (h ^ s[i]) * 16777619u;
  h = (h ^ (uint32_t)(size * 64)) * 16777619u;
  h = (h ^ (uint32_t)style) * 16777619u;
  return (h ^ (uint32_t)weight) * 16777619u;
}

static int same(const glyph_entry *e, const WCHAR *s, int len, double size, int weight, int style) {
  return e->len == len && e->size == size && e->weight == weight && e->style == style &&
         memcmp(pool + e->off, s, (size_t)len * sizeof(WCHAR)) == 0;
}

static void table_put(int id) {
  glyph_entry *e = &entries[id];
  size_t i = hash(pool + e->off, e->len, e->size, e->weight, e->style) & (table_cap - 1);
  while (table[i]) i = (i + 1) & (table_cap - 1);
  table[i] = id + 1;
}

static int intern(const WCHAR *s, int len, double size, int weight, int style) {
  if (table_cap) {
    size_t i = hash(s, len, size, weight, style) & (table_cap - 1);
    for (; table[i]; i = (i + 1) & (table_cap - 1))
      if (same(&entries[table[i] - 1], s, len, size, weight, style)) return table[i] - 1;
  }
  if (n_entries == cap_entries) {
    cap_entries = cap_entries ? cap_entries * 2 : 1024;
    entries = (glyph_entry *)realloc(entries, sizeof(glyph_entry) * cap_entries);
  }
  if (pool_len + len > pool_cap) {
    pool_cap = (pool_len + len) * 2 + 4096;
    pool = (WCHAR *)realloc(pool, pool_cap * sizeof(WCHAR));
  }
  memcpy(pool + pool_len, s, (size_t)len * sizeof(WCHAR));
  int id = n_entries++;
  entries[id] = {(int)pool_len, len, size, weight, style, 0, 0, 0, 0, 0, 0, 0, 0};
  pool_len += len;
  if ((size_t)n_entries * 2 > table_cap) {
    free(table);
    table_cap = table_cap ? table_cap * 2 : 4096;
    table = (int *)calloc(table_cap, sizeof(int));
    for (int j = 0; j < n_entries; j++) table_put(j);
  } else {
    table_put(id);
  }
  return id;
}

extern "C" int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, int32_t style, double *out) {
  init();
  int32_t len = Moonbit_array_length(text);
  int32_t cap = Moonbit_array_length(out) / 4;
  const WCHAR *s = (const WCHAR *)text;
  IDWriteTextLayout *l = make_layout(s, len, size, weight, style);
  static DWRITE_CLUSTER_METRICS *cm;
  static UINT32 cm_cap;
  UINT32 n = 0;
  if (l->GetClusterMetrics(cm, cm_cap, &n) == E_NOT_SUFFICIENT_BUFFER) {
    cm_cap = n * 2;
    cm = (DWRITE_CLUSTER_METRICS *)realloc(cm, cm_cap * sizeof *cm);
    l->GetClusterMetrics(cm, cm_cap, &n);
  }
  int32_t k = 0, pos = 0;
  for (UINT32 i = 0; i < n && k < cap; i++) {
    int clen = cm[i].length;
    WCHAR c = s[pos];
    double adv = cm[i].width;
    int key;
    if (c == '\n' || cm[i].isNewline) {
      adv = 0;
      key = -1;
    } else if (c == ' ' || c == '\t') {
      key = -1;
    } else {
      key = intern(s + pos, clen, size, weight, style);
    }
    out[k * 4] = pos;
    out[k * 4 + 1] = clen;
    out[k * 4 + 2] = adv < 0 ? 0 : adv;
    out[k * 4 + 3] = key;
    k++;
    pos += clen;
  }
  l->Release();
  return k;
}

// The key of a piece of text drawn whole (a word of a joining script): host_native.mbt's text_key.
extern "C" int32_t mb_host_text_key(moonbit_string_t text, double size, int32_t weight, int32_t style) {
  init();
  return intern((const WCHAR *)text, Moonbit_array_length(text), size, weight, style);
}

extern "C" int32_t mb_host_atlas_generation(void) { return generation; }

static void reset_atlas(void) {
  for (int i = 0; i < n_entries; i++) entries[i].done = 0;
  pack_x = pack_y = pack_h = 0;
  generation++;
}

extern "C" void mb_text_set_scale(double scale) {
  if (scale == text_scale) return;
  text_scale = scale;
  reset_atlas();
}

// Draws nothing; tells whether any run of a layout comes from a color font
// (emoji), the way the Core Text host checks kCTFontTraitColorGlyphs.
struct ColorProbe : public IDWriteTextRenderer {
  int color = 0;
  STDMETHOD(QueryInterface)(REFIID iid, void **o) override {
    if (iid == __uuidof(IUnknown) || iid == __uuidof(IDWritePixelSnapping) ||
        iid == __uuidof(IDWriteTextRenderer)) {
      *o = this;
      return S_OK;
    }
    *o = NULL;
    return E_NOINTERFACE;
  }
  STDMETHOD_(ULONG, AddRef)() override { return 1; }
  STDMETHOD_(ULONG, Release)() override { return 1; }
  STDMETHOD(IsPixelSnappingDisabled)(void *, BOOL *d) override {
    *d = TRUE;
    return S_OK;
  }
  STDMETHOD(GetCurrentTransform)(void *, DWRITE_MATRIX *m) override {
    *m = {1, 0, 0, 1, 0, 0};
    return S_OK;
  }
  STDMETHOD(GetPixelsPerDip)(void *, FLOAT *p) override {
    *p = 1;
    return S_OK;
  }
  STDMETHOD(DrawGlyphRun)(void *, FLOAT, FLOAT, DWRITE_MEASURING_MODE, DWRITE_GLYPH_RUN const *run,
                          DWRITE_GLYPH_RUN_DESCRIPTION const *, IUnknown *) override {
    IDWriteFontFace2 *f2 = NULL;
    if (SUCCEEDED(run->fontFace->QueryInterface(__uuidof(IDWriteFontFace2), (void **)&f2))) {
      if (f2->IsColorFont()) color = 1;
      f2->Release();
    }
    return S_OK;
  }
  STDMETHOD(DrawUnderline)(void *, FLOAT, FLOAT, DWRITE_UNDERLINE const *, IUnknown *) override {
    return S_OK;
  }
  STDMETHOD(DrawStrikethrough)(void *, FLOAT, FLOAT, DWRITE_STRIKETHROUGH const *, IUnknown *) override {
    return S_OK;
  }
  STDMETHOD(DrawInlineObject)(void *, FLOAT, FLOAT, IDWriteInlineObject *, BOOL, BOOL, IUnknown *) override {
    return S_OK;
  }
};

static void ensure_target(void) {
  if (rt && rt_scale == text_scale) return;
  if (white) white->Release();
  if (rt) rt->Release();
  float dpi = (float)(96.0 * text_scale);
  D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties(
      D2D1_RENDER_TARGET_TYPE_SOFTWARE,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), dpi, dpi);
  d2d->CreateWicBitmapRenderTarget(bitmap, &p, &rt);
  rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
  rt->SetTextRenderingParams(params);
  rt->CreateSolidColorBrush(D2D1::ColorF(1, 1, 1, 1), &white);
  rt_scale = text_scale;
}

static void rasterize(int key) {
  glyph_entry *e = &entries[key];
  e->done = 1;
  IDWriteTextLayout *l = make_layout(pool + e->off, e->len, e->size, e->weight, e->style);
  double sc = text_scale;
  ColorProbe probe;
  l->Draw(NULL, &probe, 0, 0);
  int color = probe.color;
  DWRITE_TEXT_METRICS tm;
  DWRITE_LINE_METRICS lm;
  UINT32 nl = 0;
  l->GetMetrics(&tm);
  l->GetLineMetrics(&lm, 1, &nl);
  l->SetMaxWidth(tm.widthIncludingTrailingWhitespace);
  l->SetMaxHeight(tm.height);
  DWRITE_OVERHANG_METRICS om;
  l->GetOverhangMetrics(&om);
  // the ink box in layout coordinates (y down, the baseline at lm.baseline);
  // color glyphs and blanks use the typographic box
  double x0 = -om.left, y0 = -om.top;
  double x1 = tm.widthIncludingTrailingWhitespace + om.right, y1 = tm.height + om.bottom;
  if (color || x1 - x0 <= 0 || y1 - y0 <= 0) {
    x0 = 0;
    y0 = 0;
    x1 = tm.widthIncludingTrailingWhitespace;
    y1 = tm.height;
  }
  // The bitmap's edges on whole pixels from the baseline, a pixel of room
  // around: the baseline then falls on a pixel row of every glyph's bitmap,
  // so glyphs placed on the same rounded baseline line up.
  double base = nl ? lm.baseline : 0;
  int px0 = (int)floor(x0 * sc) - 1, px1 = (int)ceil(x1 * sc) + 1;
  int py0 = (int)floor((y0 - base) * sc) - 1, py1 = (int)ceil((y1 - base) * sc) + 1;
  x0 = px0 / sc;
  y0 = base + py0 / sc;
  int pw = px1 - px0, ph = py1 - py0;
  if (pw <= 0 || ph <= 0 || pw > RT_SIZE || ph > RT_SIZE) {
    l->Release();
    return;
  }
  if (pack_x + pw + 1 > mb_atlas_size) {
    pack_x = 0;
    pack_y += pack_h + 1;
    pack_h = 0;
  }
  if (pack_y + ph + 1 > mb_atlas_size) {
    // full: start over; MoonBit drops its glyph cache when the generation changes
    reset_atlas();
    e->done = 1;
  }
  ensure_target();
  rt->BeginDraw();
  rt->Clear(D2D1::ColorF(0, 0, 0, 0));
  rt->DrawTextLayout(D2D1::Point2F((FLOAT)-x0, (FLOAT)-y0), l, white,
                     D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | D2D1_DRAW_TEXT_OPTIONS_NO_SNAP);
  rt->EndDraw();
  WICRect r = {0, 0, pw, ph};
  IWICBitmapLock *lock = NULL;
  if (SUCCEEDED(bitmap->Lock(&r, WICBitmapLockRead, &lock))) {
    UINT stride = 0, bytes = 0;
    BYTE *src = NULL;
    lock->GetStride(&stride);
    lock->GetDataPointer(&bytes, &src);
    uint8_t *px = (uint8_t *)malloc((size_t)pw * ph * 4);
    for (int y = 0; y < ph; y++) {
      const BYTE *s = src + (size_t)y * stride;
      uint8_t *d = px + (size_t)y * pw * 4;
      for (int x = 0; x < pw; x++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
        // premultiplied: drawn in white, a mask's pixel has its colour equal to its alpha; an emoji's does not
        if (color == 1 && d[3] > 64 && (d[0] + 32 < d[3] || d[1] + 32 < d[3] || d[2] + 32 < d[3])) color = 2;
      }
    }
    lock->Release();
    // a color font's glyph drawn in the text's colour (Segoe UI Emoji's flags are letters): a mask after all
    color = color == 2;
    mb_atlas_upload(pack_x, pack_y, pw, ph, px);
    free(px);
  }
  e->u = pack_x;
  e->v = pack_y;
  e->w = pw / sc;
  e->h = ph / sc;
  e->ox = x0;
  e->oy = y0 - (nl ? lm.baseline : 0);
  e->color = color;
  pack_x += pw + 1;
  if (ph > pack_h) pack_h = ph;
  l->Release();
}

extern "C" void mb_host_glyph(int32_t key, double *out) {
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

// ---------------------------------------------------------------------------
// The platform's own drawing of a line (textref_native.mbt, for src/textdiff): DirectWrite's text layout with its
// default features (ligatures as any app has them) and the fonts above, drawn by Direct2D into a WIC bitmap with the
// rasterizer settings above, at the places mbui draws the same words.

static IWICBitmap *ref_bmp;
static ID2D1RenderTarget *ref_rt;
static ID2D1SolidColorBrush *ref_brush;
static int ref_w, ref_h;

static void ref_path(moonbit_string_t name, WCHAR *out, size_t cap) {
  const WCHAR *dir = _wgetenv(L"MBUI_SHOT_DIR");
  int n = Moonbit_array_length(name);
  _snwprintf(out, cap, L"%ls\\%.*ls.png", dir ? dir : L".", n, (const WCHAR *)name);
}

static void ref_release(void) {
  if (ref_brush) ref_brush->Release();
  if (ref_rt) ref_rt->Release();
  if (ref_bmp) ref_bmp->Release();
  ref_brush = NULL;
  ref_rt = NULL;
  ref_bmp = NULL;
}

static D2D1_COLOR_F rgb(int c) {
  return D2D1::ColorF(((c >> 16) & 255) / 255.0f, ((c >> 8) & 255) / 255.0f, (c & 255) / 255.0f, 1);
}

extern "C" void mb_host_ref_begin(double w, double h, double scale, int32_t bg) {
  init();
  ref_release();
  ref_w = (int)floor(w * scale + 0.5);
  ref_h = (int)floor(h * scale + 0.5);
  wic->CreateBitmap(ref_w, ref_h, GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnDemand, &ref_bmp);
  float dpi = (float)(96.0 * scale);
  D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties(
      D2D1_RENDER_TARGET_TYPE_SOFTWARE,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), dpi, dpi);
  d2d->CreateWicBitmapRenderTarget(ref_bmp, &p, &ref_rt);
  ref_rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
  ref_rt->SetTextRenderingParams(params);
  ref_rt->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &ref_brush);
  ref_rt->BeginDraw();
  ref_rt->Clear(rgb(bg));
}

extern "C" void mb_host_ref_text(moonbit_string_t text, double size, int32_t weight, int32_t style, double x,
                                 double base, int32_t color, double *out) {
  for (int i = 0; i < 5; i++) out[i] = 0;
  if (!ref_rt) return;
  int len = Moonbit_array_length(text);
  IDWriteTextLayout *l = NULL;
  dw->CreateTextLayout((const WCHAR *)text, (UINT32)len, format_for(size, weight, style), 1e6f, 1e6f, &l);
  IDWriteTextLayout2 *l2 = NULL;
  if (SUCCEEDED(l->QueryInterface(__uuidof(IDWriteTextLayout2), (void **)&l2))) {
    l2->SetFontFallback(fallback);
    l2->Release();
  }
  set_style_features(l, len, style);
  DWRITE_LINE_METRICS lm;
  UINT32 nl = 0;
  l->GetLineMetrics(&lm, 1, &nl);
  DWRITE_TEXT_METRICS tm;
  l->GetMetrics(&tm);
  ref_brush->SetColor(rgb(color));
  ref_rt->DrawTextLayout(D2D1::Point2F((FLOAT)x, (FLOAT)(base - (nl ? lm.baseline : 0))), l, ref_brush,
                         D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | D2D1_DRAW_TEXT_OPTIONS_NO_SNAP);
  out[0] = tm.widthIncludingTrailingWhitespace;
  l->Release();
}

extern "C" int32_t mb_host_ref_end(moonbit_string_t name) {
  if (!ref_rt) return 0;
  ref_rt->EndDraw();
  WCHAR path[1024];
  ref_path(name, path, 1024);
  int ok = 0;
  WICRect r = {0, 0, ref_w, ref_h};
  IWICBitmapLock *lock = NULL;
  IWICStream *stream = NULL;
  IWICBitmapEncoder *enc = NULL;
  IWICBitmapFrameEncode *frame = NULL;
  if (SUCCEEDED(ref_bmp->Lock(&r, WICBitmapLockRead, &lock))) {
    UINT stride = 0, bytes = 0;
    BYTE *px = NULL;
    lock->GetStride(&stride);
    lock->GetDataPointer(&bytes, &px);
    // the ground is opaque: premultiplied or not, the same bytes
    WICPixelFormatGUID fmt = GUID_WICPixelFormat32bppBGRA;
    if (SUCCEEDED(wic->CreateStream(&stream)) && SUCCEEDED(stream->InitializeFromFilename(path, GENERIC_WRITE)) &&
        SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, NULL, &enc)) &&
        SUCCEEDED(enc->Initialize(stream, WICBitmapEncoderNoCache)) && SUCCEEDED(enc->CreateNewFrame(&frame, NULL)) &&
        SUCCEEDED(frame->Initialize(NULL)) && SUCCEEDED(frame->SetSize((UINT)ref_w, (UINT)ref_h)) &&
        SUCCEEDED(frame->SetPixelFormat(&fmt)))
      ok = SUCCEEDED(frame->WritePixels((UINT)ref_h, stride, stride * ref_h, px)) && SUCCEEDED(frame->Commit()) &&
           SUCCEEDED(enc->Commit());
    lock->Release();
  }
  if (frame) frame->Release();
  if (enc) enc->Release();
  if (stream) stream->Release();
  ref_release();
  return ok;
}

extern "C" int32_t mb_host_ref_frame(moonbit_string_t name) {
  WCHAR path[1024];
  ref_path(name, path, 1024);
  return mb_render_snapshot(path);
}
