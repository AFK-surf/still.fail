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
static const int RT_SIZE = 512;  // largest cluster bitmap, in pixels

typedef struct {
  int off, len;  // the cluster's text in pool
  double size;
  int weight;
  int done;
  double u, v, w, h, ox, oy;
  int color;
} glyph_entry;

static IDWriteFactory2 *dw;
static IDWriteFontFallback *fallback;
static IDWriteTypography *typo;
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
static struct { double size; int weight; IDWriteTextFormat *f; } formats[32];
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
  // clusters stay single graphemes, as on the other hosts
  dw->CreateTypography(&typo);
  DWRITE_FONT_FEATURE off[] = {{DWRITE_FONT_FEATURE_TAG_STANDARD_LIGATURES, 0},
                               {DWRITE_FONT_FEATURE_TAG_CONTEXTUAL_LIGATURES, 0}};
  for (int i = 0; i < 2; i++) typo->AddFontFeature(off[i]);
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

static IDWriteTextFormat *format_for(double size, int weight) {
  for (int i = 0; i < n_formats; i++)
    if (formats[i].size == size && formats[i].weight == weight) return formats[i].f;
  IDWriteTextFormat *f = NULL;
  dw->CreateTextFormat(FAMILY, NULL, (DWRITE_FONT_WEIGHT)weight, DWRITE_FONT_STYLE_NORMAL,
                       DWRITE_FONT_STRETCH_NORMAL, (FLOAT)size, L"zh-cn", &f);
  f->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  if (n_formats == 32) {
    formats[0].f->Release();
    formats[0] = formats[--n_formats];
  }
  formats[n_formats].size = size;
  formats[n_formats].weight = weight;
  formats[n_formats++].f = f;
  return f;
}

static IDWriteTextLayout *make_layout(const WCHAR *s, int len, double size, int weight) {
  IDWriteTextLayout *l = NULL;
  dw->CreateTextLayout(s, (UINT32)len, format_for(size, weight), 1e6f, 1e6f, &l);
  IDWriteTextLayout2 *l2 = NULL;
  if (SUCCEEDED(l->QueryInterface(__uuidof(IDWriteTextLayout2), (void **)&l2))) {
    l2->SetFontFallback(fallback);
    l2->Release();
  }
  DWRITE_TEXT_RANGE all = {0, (UINT32)len};
  l->SetTypography(typo, all);
  return l;
}

extern "C" void mb_host_font_metrics(double size, int32_t weight, double *out) {
  init();
  IDWriteFontCollection *fc = NULL;
  IDWriteFontFamily *fam = NULL;
  IDWriteFont *font = NULL;
  UINT32 i = 0;
  BOOL found = FALSE;
  DWRITE_FONT_METRICS m = {};
  m.designUnitsPerEm = 2048;
  m.ascent = 2210;
  m.descent = 514;
  dw->GetSystemFontCollection(&fc, FALSE);
  if (SUCCEEDED(fc->FindFamilyName(FAMILY, &i, &found)) && found &&
      SUCCEEDED(fc->GetFontFamily(i, &fam)) &&
      SUCCEEDED(fam->GetFirstMatchingFont((DWRITE_FONT_WEIGHT)weight, DWRITE_FONT_STRETCH_NORMAL,
                                          DWRITE_FONT_STYLE_NORMAL, &font)))
    font->GetMetrics(&m);
  if (font) font->Release();
  if (fam) fam->Release();
  fc->Release();
  out[0] = size * m.ascent / m.designUnitsPerEm;
  out[1] = size * m.descent / m.designUnitsPerEm;
  out[2] = round(size * 1.42);
}

static uint32_t hash(const WCHAR *s, int len, double size, int weight) {
  uint32_t h = 2166136261u;
  for (int i = 0; i < len; i++) h = (h ^ s[i]) * 16777619u;
  h = (h ^ (uint32_t)(size * 64)) * 16777619u;
  return (h ^ (uint32_t)weight) * 16777619u;
}

static int same(const glyph_entry *e, const WCHAR *s, int len, double size, int weight) {
  return e->len == len && e->size == size && e->weight == weight &&
         memcmp(pool + e->off, s, (size_t)len * sizeof(WCHAR)) == 0;
}

static void table_put(int id) {
  glyph_entry *e = &entries[id];
  size_t i = hash(pool + e->off, e->len, e->size, e->weight) & (table_cap - 1);
  while (table[i]) i = (i + 1) & (table_cap - 1);
  table[i] = id + 1;
}

static int intern(const WCHAR *s, int len, double size, int weight) {
  if (table_cap) {
    size_t i = hash(s, len, size, weight) & (table_cap - 1);
    for (; table[i]; i = (i + 1) & (table_cap - 1))
      if (same(&entries[table[i] - 1], s, len, size, weight)) return table[i] - 1;
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
  entries[id] = {(int)pool_len, len, size, weight, 0, 0, 0, 0, 0, 0, 0, 0};
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

extern "C" int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, double *out) {
  init();
  int32_t len = Moonbit_array_length(text);
  int32_t cap = Moonbit_array_length(out) / 4;
  const WCHAR *s = (const WCHAR *)text;
  IDWriteTextLayout *l = make_layout(s, len, size, weight);
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
      key = intern(s + pos, clen, size, weight);
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
  IDWriteTextLayout *l = make_layout(pool + e->off, e->len, e->size, e->weight);
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
  double pad = 1.0 / sc;
  x0 -= pad;
  y0 -= pad;
  x1 += pad;
  y1 += pad;
  int pw = (int)ceil((x1 - x0) * sc), ph = (int)ceil((y1 - y0) * sc);
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
      }
    }
    lock->Release();
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
