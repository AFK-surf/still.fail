// Text with DirectWrite: shaping into clusters with their advances, and
// rasterizing each cluster with Direct2D into the RGBA atlas: drawn ahead by
// threads of their own where the app says which it will draw, else when it is
// first drawn. Segoe UI, with Han, kana and CJK punctuation mapped to Microsoft
// YaHei UI ahead of the system fallback (which supplies Segoe UI Emoji).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <dwrite_3.h>
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
  double w, h, ox, oy;
  int color;
  // its ink across, from where it starts (punct_ink); known: worked out
  double ink_l, ink_r;
  bool ink_known;
} glyph_entry;

static IDWriteFactory2 *dw;
static IDWriteFontFallback *fallback;
static IDWriteRenderingParams *params, *params_ct;
static ID2D1Factory *d2d;
static IWICImagingFactory *wic;
// Where a glyph is drawn: a bitmap of RT_SIZE pixels, Direct2D's target over it at the scale it was made for, a white
// brush. The frames' thread has its own (the factories made in init); each thread drawing ahead its own, of its own
// factories (Direct2D's single-threaded one, WIC's).
struct Target {
  ID2D1Factory *d2d;
  IWICImagingFactory *wic;
  IWICBitmap *bitmap;
  ID2D1RenderTarget *rt;
  ID2D1SolidColorBrush *white;
  double scale;
};
static Target main_target;
static double text_scale = 1;
static glyph_entry *entries;
static int n_entries, cap_entries;
static WCHAR *pool;
static size_t pool_len, pool_cap;
static int *table;  // open addressing: entry index + 1, 0 is empty
static size_t table_cap;
static int generation;
// the glyph drawn last (mb_host_glyph), its picture until it is put in the atlas (mb_host_glyph_put)
static int held_key = -1, held_w, held_h;
static uint8_t *held_px;
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
  // (a trial: MBUI_CLEARTYPE=1, glyphs drawn with ClearType, the screen's stripes red, green, blue left to right)
  const char *ct = getenv("MBUI_CLEARTYPE");
  if (ct && *ct == '1') {
    IDWriteRenderingParams2 *c2 = NULL;
    dw->CreateCustomRenderingParams(1.0f, 0.0f, 0.0f, 1.0f, DWRITE_PIXEL_GEOMETRY_RGB,
                                    DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC, DWRITE_GRID_FIT_MODE_DISABLED, &c2);
    params_ct = c2;
  }
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), NULL, (void **)&d2d);
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory),
                   (void **)&wic);
  main_target.d2d = d2d;
  main_target.wic = wic;
}

// The faces given (mb_host_face_add, style.mbt): each its files, made into a collection of their own (DirectWrite's
// font set from the files: a variable file's named weights in it), and the family the files make.
#define MB_FACES 16
static struct {
  WCHAR **paths;  // a file's path, or NULL: its bytes (data, sizes)
  void **data;
  UINT32 *sizes;
  int n;
  IDWriteFontCollection1 *fc;
  WCHAR family[128];
  bool system;  // a family installed here (mb_host_face_add_family): the system's collection, no files of its own
} faces[MB_FACES];
// fonts given as bytes: DirectWrite's in-memory loader (it keeps a copy of each)
static IDWriteInMemoryFontFileLoader *mem_loader;

// The face a style is set in: the one it names; else code's (style & 2), what people wrote's (style & 16), the app's
// words' (not the serif face's); 0 none given.
static bool face_has(int f) { return faces[f].fc || faces[f].system; }

static int face_id(int style) {
  int f = (style >> 8) & 15;
  if (f > 0) return face_has(f) ? f : 0;
  if (style & 2) return face_has(3) ? 3 : 0;
  if ((style & 16) && face_has(2)) return 2;
  if (style & 4) return 0;
  return face_has(1) ? 1 : 0;
}

// Face `f`'s files as a collection, its family's name from it (false: not fonts DirectWrite reads).
static bool face_build(int f) {
  IDWriteFactory5 *dw5 = NULL;
  if (FAILED(dw->QueryInterface(__uuidof(IDWriteFactory5), (void **)&dw5))) return false;
  IDWriteFontSetBuilder1 *b = NULL;
  IDWriteFontSet *set = NULL;
  IDWriteFontCollection1 *fc = NULL;
  IDWriteFontFamily1 *fam = NULL;
  IDWriteLocalizedStrings *names = NULL;
  bool ok = SUCCEEDED(dw5->CreateFontSetBuilder(&b));
  for (int i = 0; ok && i < faces[f].n; i++) {
    IDWriteFontFile *file = NULL;
    if (faces[f].paths[i]) {
      ok = SUCCEEDED(dw5->CreateFontFileReference(faces[f].paths[i], NULL, &file));
    } else {
      if (!mem_loader && SUCCEEDED(dw5->CreateInMemoryFontFileLoader(&mem_loader))) dw5->RegisterFontFileLoader(mem_loader);
      ok = mem_loader && SUCCEEDED(mem_loader->CreateInMemoryFontFileReference(dw5, faces[f].data[i], faces[f].sizes[i], NULL, &file));
    }
    ok = ok && SUCCEEDED(b->AddFontFile(file));
    if (file) file->Release();
  }
  ok = ok && SUCCEEDED(b->CreateFontSet(&set)) && SUCCEEDED(dw5->CreateFontCollectionFromFontSet(set, &fc)) &&
       fc->GetFontFamilyCount() > 0 && SUCCEEDED(fc->GetFontFamily(0, &fam)) && SUCCEEDED(fam->GetFamilyNames(&names)) &&
       SUCCEEDED(names->GetString(0, faces[f].family, 128));
  if (ok) {
    if (faces[f].fc) faces[f].fc->Release();
    faces[f].fc = fc;
    faces[f].system = false;
    fc = NULL;
  }
  if (names) names->Release();
  if (fam) fam->Release();
  if (fc) fc->Release();
  if (set) set->Release();
  if (b) b->Release();
  dw5->Release();
  return ok;
}

static void faces_changed(void);

// A file of face `f`: its path, or its bytes (path NULL); made part of it if DirectWrite reads them as a font.
static int32_t face_take(int32_t f, WCHAR *path, void *data, UINT32 size) {
  init();
  if (f <= 0 || f >= MB_FACES) {
    free(path);
    free(data);
    return 0;
  }
  int n = faces[f].n;
  faces[f].paths = (WCHAR **)realloc(faces[f].paths, sizeof(WCHAR *) * (n + 1));
  faces[f].data = (void **)realloc(faces[f].data, sizeof(void *) * (n + 1));
  faces[f].sizes = (UINT32 *)realloc(faces[f].sizes, sizeof(UINT32) * (n + 1));
  faces[f].paths[n] = path;
  faces[f].data[n] = data;
  faces[f].sizes[n] = size;
  faces[f].n = n + 1;
  if (!face_build(f)) {
    faces[f].n = n;
    free(path);
    free(data);
    return 0;
  }
  faces_changed();
  return 1;
}

extern "C" int32_t mb_host_face_add(int32_t f, moonbit_string_t path, int32_t weight) {
  (void)weight;  // the files' own weights say which is which (a variable file: its named instances)
  int len = Moonbit_array_length(path);
  WCHAR *p = (WCHAR *)malloc(sizeof(WCHAR) * (len + 1));
  memcpy(p, path, sizeof(WCHAR) * len);
  p[len] = 0;
  return face_take(f, p, NULL, 0);
}

extern "C" int32_t mb_host_face_add_bytes(int32_t f, moonbit_bytes_t data, int32_t weight) {
  (void)weight;
  UINT32 size = (UINT32)Moonbit_array_length(data);
  void *copy = malloc(size);
  memcpy(copy, data, size);
  return face_take(f, NULL, copy, size);
}

extern "C" void mb_host_face_clear(int32_t f) {
  if (f <= 0 || f >= MB_FACES || !face_has(f)) return;
  for (int i = 0; i < faces[f].n; i++) {
    free(faces[f].paths[i]);
    free(faces[f].data[i]);
  }
  faces[f].n = 0;
  if (faces[f].fc) faces[f].fc->Release();
  faces[f].fc = NULL;
  faces[f].system = false;
  faces_changed();
}

// The system's font collection's family named `name` (its index), if there is one.
static bool system_family(const WCHAR *name) {
  IDWriteFontCollection *fc = NULL;
  if (FAILED(dw->GetSystemFontCollection(&fc, FALSE))) return false;
  UINT32 at = 0;
  BOOL there = FALSE;
  fc->FindFamilyName(name, &at, &there);
  fc->Release();
  return there;
}

// Face `f` set in the family installed here named `family`: the system's collection, by its name.
extern "C" int32_t mb_host_face_add_family(int32_t f, moonbit_string_t family) {
  init();
  int len = Moonbit_array_length(family);
  if (f <= 0 || f >= MB_FACES || len <= 0 || len >= 128) return 0;
  WCHAR name[128];
  memcpy(name, family, sizeof(WCHAR) * len);
  name[len] = 0;
  if (!system_family(name)) return 0;
  for (int i = 0; i < faces[f].n; i++) {
    free(faces[f].paths[i]);
    free(faces[f].data[i]);
  }
  faces[f].n = 0;
  if (faces[f].fc) faces[f].fc->Release();
  faces[f].fc = NULL;
  memcpy(faces[f].family, name, sizeof(name));
  faces[f].system = true;
  faces_changed();
  return 1;
}

// The font families installed here, as a JSON array of their names (each its name in the user's language, else its
// first), sorted as the collection has them.
// the user's locale, the families' names are shown and sorted in
static WCHAR names_locale[LOCALE_NAME_MAX_LENGTH];

static int name_order(const void *a, const void *b) {
  return CompareStringEx(names_locale[0] ? names_locale : NULL, LINGUISTIC_IGNORECASE, *(const WCHAR *const *)a, -1,
                         *(const WCHAR *const *)b, -1, NULL, NULL, 0) - CSTR_EQUAL;
}

extern "C" moonbit_string_t mb_host_local_font_families(void) {
  init();
  IDWriteFontCollection *fc = NULL;
  if (FAILED(dw->GetSystemFontCollection(&fc, FALSE))) return moonbit_make_string_raw(0);
  if (!GetUserDefaultLocaleName(names_locale, LOCALE_NAME_MAX_LENGTH)) names_locale[0] = 0;
  UINT32 count = fc->GetFontFamilyCount();
  WCHAR **all = (WCHAR **)calloc(count ? count : 1, sizeof(WCHAR *));
  UINT32 had = 0;
  for (UINT32 i = 0; i < count; i++) {
    IDWriteFontFamily *fam = NULL;
    IDWriteLocalizedStrings *names = NULL;
    WCHAR name[256];
    name[0] = 0;
    if (SUCCEEDED(fc->GetFontFamily(i, &fam)) && SUCCEEDED(fam->GetFamilyNames(&names))) {
      UINT32 at = 0;
      BOOL there = FALSE;
      if (names_locale[0]) names->FindLocaleName(names_locale, &at, &there);
      if (!there) at = 0;
      UINT32 len = 0;
      if (SUCCEEDED(names->GetStringLength(at, &len)) && len < 255) names->GetString(at, name, 256);
    }
    if (names) names->Release();
    if (fam) fam->Release();
    if (name[0]) all[had++] = _wcsdup(name);
  }
  fc->Release();
  // in the order of the user's language, as the web's localeCompare
  qsort(all, had, sizeof(WCHAR *), name_order);
  size_t cap = 4096, n = 0;
  WCHAR *out = (WCHAR *)malloc(sizeof(WCHAR) * cap);
  out[n++] = L'[';
  for (UINT32 i = 0; i < had; i++) {
    const WCHAR *name = all[i];
    size_t len = wcslen(name);
    // its name as a JSON string: a quote and a backslash escaped, the rest as it is
    if (n + 2 * len + 4 >= cap) {
      cap = (n + 2 * len + 4) * 2;
      out = (WCHAR *)realloc(out, sizeof(WCHAR) * cap);
    }
    if (n > 1) out[n++] = L',';
    out[n++] = L'"';
    for (size_t k = 0; k < len; k++) {
      if (name[k] == L'"' || name[k] == L'\\') out[n++] = L'\\';
      out[n++] = name[k] < 0x20 ? L' ' : name[k];
    }
    out[n++] = L'"';
    free(all[i]);
  }
  free(all);
  out[n++] = L']';
  moonbit_string_t s = moonbit_make_string_raw((int32_t)n);
  memcpy(s, out, sizeof(WCHAR) * n);
  free(out);
  return s;
}

static IDWriteTextFormat *format_for(double size, int weight, int style) {
  for (int i = 0; i < n_formats; i++)
    if (formats[i].size == size && formats[i].weight == weight && formats[i].style == style) return formats[i].f;
  IDWriteTextFormat *f = NULL;
  int face = face_id(style);
  dw->CreateTextFormat(face ? faces[face].family : (style & 2) ? MONO : (style & 4) ? SERIF : FAMILY,
                       face && faces[face].fc ? faces[face].fc : NULL, (DWRITE_FONT_WEIGHT)weight,
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

// style & 8: no ligatures (words with letter spacing, each cluster spaced on its own): liga and clig off; style & 32:
// digits all one width (style.mbt style_tabular): tnum. One typography for each of the three ways they go together.
static IDWriteTypography *typographies[4];

// the typography of a style's features (NULL: none, the font's own)
static IDWriteTypography *typography_for(int style) {
  int k = ((style & 8) ? 1 : 0) | ((style & 32) ? 2 : 0);
  if (!k) return NULL;
  if (!typographies[k]) {
    IDWriteTypography *t = NULL;
    dw->CreateTypography(&t);
    if (k & 1) {
      t->AddFontFeature({DWRITE_FONT_FEATURE_TAG_STANDARD_LIGATURES, 0});
      t->AddFontFeature({DWRITE_FONT_FEATURE_TAG_CONTEXTUAL_LIGATURES, 0});
    }
    if (k & 2) t->AddFontFeature({DWRITE_FONT_FEATURE_TAG_TABULAR_FIGURES, 1});
    typographies[k] = t;
  }
  return typographies[k];
}

static void set_style_features(IDWriteTextLayout *l, int len, int style) {
  IDWriteTypography *t = typography_for(style);
  if (t) l->SetTypography(t, {0, (UINT32)len});
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

// A family's metrics at this weight and style (false: not on this system, `m` as it was); in a face's collection
// where one is given.
static bool family_metrics(const WCHAR *name, int weight, int style, DWRITE_FONT_METRICS *m, IDWriteFontCollection *in = NULL) {
  IDWriteFontCollection *fc = NULL;
  IDWriteFontFamily *fam = NULL;
  IDWriteFont *font = NULL;
  UINT32 i = 0;
  BOOL found = FALSE;
  bool ok = false;
  if (in) {
    fc = in;
    fc->AddRef();
  } else {
    dw->GetSystemFontCollection(&fc, FALSE);
  }
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
  int face = face_id(style);
  if (face) family_metrics(faces[face].family, weight, style, &m, faces[face].fc);
  else family_metrics((style & 2) ? MONO : (style & 4) ? SERIF : FAMILY, weight, style, &m);
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
  entries[id] = {(int)pool_len, len, size, weight, style, 0, 0, 0, 0, 0, 0, 0, false};
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

// CJK punctuation two in a row set solid, as Core Text sets it on the Apple hosts (and DirectWrite would, for a font
// with chws: Microsoft YaHei, the fallback Han is drawn in, has neither chws nor halt, so "），" stood a whole empty
// half em apart). 1: a closing mark or a pause (，。、：；and the closing brackets), its ink in its first half in a
// Simplified Chinese font; 2: an opening bracket, its ink in its second half. ！？ and the quotes (narrow in YaHei)
// are left as they are.
static int punct_kind(WCHAR c) {
  switch (c) {
    case 0xFF0C: case 0x3002: case 0x3001: case 0xFF1A: case 0xFF1B: case 0xFF0E:
    case 0xFF09: case 0x300D: case 0x300F: case 0x3011: case 0x300B: case 0x3009: case 0x3015: case 0xFF3D:
    case 0xFF5D:
      return 1;
    case 0xFF08: case 0x300C: case 0x300E: case 0x3010: case 0x300A: case 0x3008: case 0x3014: case 0xFF3B:
    case 0xFF5B:
      return 2;
  }
  return 0;
}

// Where glyph `key`'s ink is across, from where it starts: worked out once, from the face it is drawn in.
static void punct_ink(int key) {
  glyph_entry *e = &entries[key];
  if (e->ink_known) return;
  IDWriteTextLayout *l = make_layout(pool + e->off, e->len, e->size, e->weight, e->style);
  DWRITE_TEXT_METRICS tm;
  DWRITE_OVERHANG_METRICS om;
  l->GetMetrics(&tm);
  l->SetMaxWidth(tm.widthIncludingTrailingWhitespace);
  l->SetMaxHeight(tm.height);
  l->GetOverhangMetrics(&om);
  l->Release();
  e->ink_l = -om.left;
  e->ink_r = tm.widthIncludingTrailingWhitespace + om.right;
  e->ink_known = true;
}

// Each pair of full-width marks in a line's clusters (out, as mb_host_shape gives them): the first's advance a half
// em less where its ink still ends before the second's begins (a closing mark's empty second half; before an opening
// bracket, that bracket's empty first half), as chws sets them. An opening bracket then a closing one ("（）") is
// left.
static void punct_solid(const WCHAR *s, double size, double *out, int32_t k) {
  double half = size / 2, tol = size * 0.05;
  for (int32_t i = 0; i + 1 < k; i++) {
    int a = (int)out[i * 4 + 3], b = (int)out[(i + 1) * 4 + 3];
    if (a < 0 || b < 0 || out[i * 4 + 1] != 1 || out[(i + 1) * 4 + 1] != 1) continue;
    int ka = punct_kind(s[(int)out[i * 4]]), kb = punct_kind(s[(int)out[(i + 1) * 4]]);
    if (!ka || !kb || (ka == 2 && kb == 1)) continue;
    double adv = out[i * 4 + 2];
    if (fabs(adv - size) > tol || fabs(out[(i + 1) * 4 + 2] - size) > tol) continue;
    punct_ink(a);
    punct_ink(b);
    if (entries[a].ink_r <= adv - half + entries[b].ink_l + tol) out[i * 4 + 2] = adv - half;
  }
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
  punct_solid(s, size, out, k);
  return k;
}

// The key of a piece of text drawn whole (a word of a joining script): host_native.mbt's text_key.
extern "C" int32_t mb_host_text_key(moonbit_string_t text, double size, int32_t weight, int32_t style) {
  init();
  return intern((const WCHAR *)text, Moonbit_array_length(text), size, weight, style);
}

extern "C" int32_t mb_host_atlas_generation(void) { return generation; }

// (one atlas: colour glyphs in it with the others)
extern "C" int32_t mb_host_atlas_size(int32_t colour) { return colour ? 0 : mb_atlas_size; }

// What was drawn before is drawn again: MoonBit drops its glyphs as the generation moves on.
static void reset_atlas(void) {
  generation++;
}

// What was measured and drawn before a face changed: its formats made again, its glyphs drawn again.
static void ahead_forget(void);

static void faces_changed(void) {
  for (int i = 0; i < n_formats; i++) formats[i].f->Release();
  n_formats = 0;
  for (int i = 0; i < n_entries; i++) entries[i].ink_known = false;
  ahead_forget();
  reset_atlas();
}

extern "C" void mb_text_set_scale(double scale) {
  if (scale == text_scale) return;
  text_scale = scale;
  ahead_forget();
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

static void target_ensure(Target *t, double scale) {
  if (t->rt && t->scale == scale) return;
  if (t->white) t->white->Release();
  if (t->rt) t->rt->Release();
  t->white = NULL;
  t->rt = NULL;
  if (!t->bitmap && FAILED(t->wic->CreateBitmap(RT_SIZE, RT_SIZE, GUID_WICPixelFormat32bppPBGRA,
                                                  WICBitmapCacheOnDemand, &t->bitmap)))
    return;
  float dpi = (float)(96.0 * scale);
  D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties(
      D2D1_RENDER_TARGET_TYPE_SOFTWARE,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), dpi, dpi);
  if (FAILED(t->d2d->CreateWicBitmapRenderTarget(t->bitmap, &p, &t->rt))) return;
  t->rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
  t->rt->SetTextRenderingParams(params);
  t->rt->CreateSolidColorBrush(D2D1::ColorF(1, 1, 1, 1), &t->white);
  t->scale = scale;
}

// A cluster drawn: its picture (pw × ph pixels, RGBA, NULL none), its box in points as its entry has it, whether it is
// in its own colours (an emoji)
struct Drawn {
  int pw, ph;
  uint8_t *px;
  double w, h, ox, oy;
  int color;
};

// A cluster's layout drawn in white at `sc` pixels a point, a pixel round its bounds, on `t`.
static void draw_layout(IDWriteTextLayout *l, double sc, Target *t, Drawn *d) {
  *d = {};
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
  if (pw <= 0 || ph <= 0 || pw > RT_SIZE || ph > RT_SIZE) return;
  target_ensure(t, sc);
  if (!t->rt) return;
  // (a trial: ClearType, each stripe's coverage on its own, drawn white on opaque black)
  bool stripes = params_ct && !color;
  t->rt->BeginDraw();
  t->rt->Clear(D2D1::ColorF(0, 0, 0, stripes ? 1.0f : 0.0f));
  // (over the opaque black cleared above; a ClearType layer pushed here drew it gray after all)
  if (stripes) {
    t->rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);
    t->rt->SetTextRenderingParams(params_ct);
  }
  t->rt->DrawTextLayout(D2D1::Point2F((FLOAT)-x0, (FLOAT)-y0), l, t->white,
                        D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | D2D1_DRAW_TEXT_OPTIONS_NO_SNAP);
  t->rt->EndDraw();
  if (stripes) {
    t->rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    t->rt->SetTextRenderingParams(params);
  }
  WICRect r = {0, 0, pw, ph};
  IWICBitmapLock *lock = NULL;
  if (SUCCEEDED(t->bitmap->Lock(&r, WICBitmapLockRead, &lock))) {
    UINT stride = 0, bytes = 0;
    BYTE *src = NULL;
    lock->GetStride(&stride);
    lock->GetDataPointer(&bytes, &src);
    uint8_t *px = (uint8_t *)malloc((size_t)pw * ph * 4);
    for (int y = 0; y < ph; y++) {
      const BYTE *s = src + (size_t)y * stride;
      uint8_t *o = px + (size_t)y * pw * 4;
      for (int x = 0; x < pw; x++, s += 4, o += 4) {
        o[0] = s[2];
        o[1] = s[1];
        o[2] = s[0];
        o[3] = stripes ? (uint8_t)((o[0] + o[1] + o[2] + 1) / 3) : s[3];
        // premultiplied: drawn in white, a mask's pixel has its colour equal to its alpha; an emoji's does not
        if (color == 1 && o[3] > 64 && (o[0] + 32 < o[3] || o[1] + 32 < o[3] || o[2] + 32 < o[3])) color = 2;
      }
    }
    lock->Release();
    d->pw = pw;
    d->ph = ph;
    d->px = px;
  }
  // a color font's glyph drawn in the text's colour (Segoe UI Emoji's flags are letters): a mask after all
  d->color = color == 2;
  d->w = pw / sc;
  d->h = ph / sc;
  d->ox = x0;
  d->oy = y0 - (nl ? lm.baseline : 0);
}

// ---- drawing ahead: the glyphs a frame shaped and did not draw (text.mbt glyphs_ahead), drawn by threads of their own,
// as Android's MBText and the Apple hosts' queue draw them; each taken as it is first asked for, from what was drawn
// ahead: waited for while a thread draws it, drawn here when none has begun it ----

// One glyph asked to be drawn ahead: what it is drawn from (its words, its format and features as the frames' thread
// had them, held; its scale), set before a thread has it and not changed after; under ahead_lock its state and, once
// drawn, its picture. `dropped`: the frames' thread let go of it, the thread that has it frees it.
enum { AHEAD_ASKED, AHEAD_DRAWING, AHEAD_DRAWN };
struct Ahead {
  int key;
  WCHAR *text;
  int len;
  IDWriteTextFormat *format;
  IDWriteTypography *typography;
  double scale;
  int state;
  bool dropped;
  Drawn drawn;
};

// The most glyphs asked for or drawn ahead and not placed yet (the oldest drawn let go past it).
#define AHEAD_MOST 1024
static CRITICAL_SECTION ahead_lock;
static CONDITION_VARIABLE ahead_more, ahead_done;
static int ahead_started;
// (under ahead_lock) what the threads are to draw, in the order asked
static Ahead **ahead_queue;
static int ahead_head, ahead_n, ahead_cap;
// (the frames' thread's) what was asked for and not placed yet, by key, and in the order asked
static Ahead **ahead_of;  // by key, n_entries' room
static int ahead_of_cap;
static Ahead **ahead_order;
static int order_head, order_n, order_cap;

static void ahead_free(Ahead *a) {
  if (a->format) a->format->Release();
  if (a->typography) a->typography->Release();
  free(a->text);
  free(a->drawn.px);
  free(a);
}

static IDWriteTextLayout *layout_with(const WCHAR *s, int len, IDWriteTextFormat *f, IDWriteTypography *typo) {
  IDWriteTextLayout *l = NULL;
  if (FAILED(dw->CreateTextLayout(s, (UINT32)len, f, 1e6f, 1e6f, &l))) return NULL;
  IDWriteTextLayout2 *l2 = NULL;
  if (SUCCEEDED(l->QueryInterface(__uuidof(IDWriteTextLayout2), (void **)&l2))) {
    l2->SetFontFallback(fallback);
    l2->Release();
  }
  if (typo) l->SetTypography(typo, {0, (UINT32)len});
  return l;
}

// A thread drawing ahead: what is asked, oldest first, with a target of its own (on COM's multithreaded apartment)
static DWORD WINAPI ahead_thread(void *) {
  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  Target t = {};
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), NULL, (void **)&t.d2d);
  CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory), (void **)&t.wic);
  for (;;) {
    EnterCriticalSection(&ahead_lock);
    while (ahead_n == 0) SleepConditionVariableCS(&ahead_more, &ahead_lock, INFINITE);
    Ahead *a = ahead_queue[ahead_head];
    ahead_head = (ahead_head + 1) % ahead_cap;
    ahead_n--;
    bool gone = a->dropped;
    if (!gone) a->state = AHEAD_DRAWING;
    LeaveCriticalSection(&ahead_lock);
    if (gone) {
      ahead_free(a);
      continue;
    }
    Drawn d = {};
    IDWriteTextLayout *l = t.d2d && t.wic ? layout_with(a->text, a->len, a->format, a->typography) : NULL;
    if (l) {
      draw_layout(l, a->scale, &t, &d);
      l->Release();
    }
    EnterCriticalSection(&ahead_lock);
    a->drawn = d;
    a->state = AHEAD_DRAWN;
    bool free_it = a->dropped;
    WakeAllConditionVariable(&ahead_done);
    LeaveCriticalSection(&ahead_lock);
    if (free_it) ahead_free(a);
  }
}

// (the frames' thread) its hold on `a` let go: freed here when no thread has it, else by the one that does
static void ahead_drop(Ahead *a) {
  EnterCriticalSection(&ahead_lock);
  bool mine = a->state == AHEAD_DRAWN;
  a->dropped = true;
  LeaveCriticalSection(&ahead_lock);
  if (mine) ahead_free(a);
}

static void order_remove_front(void) {
  order_head = (order_head + 1) % order_cap;
  order_n--;
}

// Everything asked for let go: the faces or the scale changed, and what is drawn with them with it.
static void ahead_forget(void) {
  for (int i = 0; i < order_n; i++) {
    Ahead *a = ahead_order[(order_head + i) % order_cap];
    if (!a) continue;
    if (a->key < ahead_of_cap) ahead_of[a->key] = NULL;
    ahead_drop(a);
  }
  order_n = order_head = 0;
}

// The oldest asked, let go if it is drawn (the threads draw about in the order asked: hardly any is when it is not);
// false when not.
static bool drop_oldest_drawn(void) {
  while (order_n > 0 && !ahead_order[order_head]) order_remove_front();
  if (order_n == 0) return false;
  Ahead *a = ahead_order[order_head];
  EnterCriticalSection(&ahead_lock);
  bool drawn = a->state == AHEAD_DRAWN;
  LeaveCriticalSection(&ahead_lock);
  if (!drawn) return false;
  ahead_of[a->key] = NULL;
  order_remove_front();
  ahead_free(a);
  return true;
}

// What was drawn ahead of `key` at the scale of now, taken (true, its picture in *d); false when it was not (asked
// and not begun: no longer asked, drawn here).
static bool drawn_ahead(int key, Drawn *d) {
  Ahead *a = key < ahead_of_cap ? ahead_of[key] : NULL;
  if (!a) return false;
  ahead_of[key] = NULL;
  for (int i = 0; i < order_n; i++) {
    Ahead **at = &ahead_order[(order_head + i) % order_cap];
    if (*at == a) {
      *at = NULL;
      break;
    }
  }
  EnterCriticalSection(&ahead_lock);
  if (a->state == AHEAD_ASKED) {
    // (left to its thread, which passes over it)
    a->dropped = true;
    LeaveCriticalSection(&ahead_lock);
    return false;
  }
  while (a->state == AHEAD_DRAWING) SleepConditionVariableCS(&ahead_done, &ahead_lock, INFINITE);
  LeaveCriticalSection(&ahead_lock);
  bool ok = a->scale == text_scale;
  if (ok) {
    *d = a->drawn;
    a->drawn.px = NULL;
  }
  ahead_free(a);
  return ok;
}

extern "C" void mb_host_glyphs_ahead(int32_t *keys, int32_t n) {
  if (n <= 0) return;
  if (!ahead_started) {
    ahead_started = 1;
    InitializeCriticalSection(&ahead_lock);
    InitializeConditionVariable(&ahead_more);
    InitializeConditionVariable(&ahead_done);
    // (a page's few hundred glyphs drawn in the time a frame or two takes, over the cores there are, the frames'
    // thread's left to it)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    int threads = (int)si.dwNumberOfProcessors - 1;
    threads = threads < 1 ? 1 : threads > 4 ? 4 : threads;
    for (int i = 0; i < threads; i++) {
      HANDLE h = CreateThread(NULL, 0, ahead_thread, NULL, 0, NULL);
      if (h) SetThreadPriority(h, THREAD_PRIORITY_BELOW_NORMAL), CloseHandle(h);
    }
  }
  if (ahead_of_cap < n_entries) {
    int cap = n_entries * 2;
    ahead_of = (Ahead **)realloc(ahead_of, (size_t)cap * sizeof *ahead_of);
    memset(ahead_of + ahead_of_cap, 0, (size_t)(cap - ahead_of_cap) * sizeof *ahead_of);
    ahead_of_cap = cap;
  }
  int asked = 0;
  for (int32_t i = 0; i < n; i++) {
    int k = keys[i];
    if (k < 0 || k >= n_entries || ahead_of[k]) continue;
    if (order_n >= AHEAD_MOST && !drop_oldest_drawn()) break;
    glyph_entry *e = &entries[k];
    Ahead *a = (Ahead *)calloc(1, sizeof(Ahead));
    a->key = k;
    a->len = e->len;
    a->text = (WCHAR *)malloc(sizeof(WCHAR) * (e->len ? e->len : 1));
    memcpy(a->text, pool + e->off, sizeof(WCHAR) * e->len);
    a->format = format_for(e->size, e->weight, e->style);
    a->format->AddRef();
    a->typography = typography_for(e->style);
    if (a->typography) a->typography->AddRef();
    a->scale = text_scale;
    a->state = AHEAD_ASKED;
    ahead_of[k] = a;
    if (order_n + 1 > order_cap) {
      int cap = order_cap ? order_cap * 2 : 256;
      Ahead **next = (Ahead **)malloc((size_t)cap * sizeof *next);
      for (int j = 0; j < order_n; j++) next[j] = ahead_order[(order_head + j) % order_cap];
      free(ahead_order);
      ahead_order = next;
      order_head = 0;
      order_cap = cap;
    }
    ahead_order[(order_head + order_n++) % order_cap] = a;
    EnterCriticalSection(&ahead_lock);
    if (ahead_n + 1 > ahead_cap) {
      int cap = ahead_cap ? ahead_cap * 2 : 256;
      Ahead **next = (Ahead **)malloc((size_t)cap * sizeof *next);
      for (int j = 0; j < ahead_n; j++) next[j] = ahead_queue[(ahead_head + j) % ahead_cap];
      free(ahead_queue);
      ahead_queue = next;
      ahead_head = 0;
      ahead_cap = cap;
    }
    ahead_queue[(ahead_head + ahead_n++) % ahead_cap] = a;
    LeaveCriticalSection(&ahead_lock);
    asked++;
  }
  if (asked) WakeAllConditionVariable(&ahead_more);
}

// Glyph `key` drawn in white, a pixel round its bounds: its box (in its entry) and its picture, held for
// mb_host_glyph_put (where it goes in the atlas is MoonBit's: hostapi's atlas.mbt). From what was drawn ahead of it,
// else drawn here.
static void rasterize(int key) {
  glyph_entry *e = &entries[key];
  free(held_px);
  held_px = NULL;
  held_key = -1;
  e->w = e->h = 0;
  Drawn d = {};
  if (!drawn_ahead(key, &d)) {
    IDWriteTextLayout *l = make_layout(pool + e->off, e->len, e->size, e->weight, e->style);
    draw_layout(l, text_scale, &main_target, &d);
    l->Release();
  }
  if (d.px) {
    held_key = key;
    held_w = d.pw;
    held_h = d.ph;
    held_px = d.px;
  }
  e->w = d.w;
  e->h = d.h;
  e->ox = d.ox;
  e->oy = d.oy;
  e->color = d.color;
}

extern "C" void mb_host_glyph(int32_t key, double *out) {
  if (key < 0 || key >= n_entries) {
    for (int i = 0; i < 7; i++) out[i] = 0;
    return;
  }
  rasterize(key);
  glyph_entry *e = &entries[key];
  out[0] = 0;
  out[1] = 0;
  out[2] = e->w;
  out[3] = e->h;
  out[4] = e->ox;
  out[5] = e->oy;
  out[6] = e->color;
}

// The glyph drawn last put in the atlas, its top left at x, y.
extern "C" void mb_host_glyph_put(int32_t key, int32_t x, int32_t y) {
  if (key != held_key || !held_px) return;
  mb_atlas_upload(x, y, held_w, held_h, held_px);
  free(held_px);
  held_px = NULL;
  held_key = -1;
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
