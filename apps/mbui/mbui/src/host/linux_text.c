// Text on Linux: Pango shapes it into clusters with their advances (HarfBuzz, the fonts fontconfig finds: Han, kana and
// CJK punctuation in the simplified Chinese faces first, the language being zh-cn; Noto Color Emoji's colour glyphs),
// and cairo draws each cluster, as it is first asked for, into a picture the atlas takes (MoonBit says where: hostapi's
// atlas.mbt). Unhinted, positions not rounded to pixels, plain coverage: as Core Text and DirectWrite draw them for the
// other hosts. The words' face is the system's (GTK's gtk-font-name, told by linux_app.c), else fontconfig's
// sans-serif.
#include <cairo.h>
#include <fontconfig/fontconfig.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <math.h>
#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "linux.h"

static char family_ui[128] = "sans-serif";
static const char *MONO = "monospace";  // the code face (style & 2)
static const char *SERIF = "serif";     // the serif face (style & 4): Noto Serif CJK SC's Latin and Han
// the words' and the code's faces as fontconfig names them for Latin (latin_family)
static char face_ui[128], face_mono[128];
static const int MAX_PX = 1024;         // largest cluster picture, in pixels a side

typedef struct {
  int off, len;  // the cluster's text in pool
  double size;
  int weight;
  int style;  // 1 italic, 2 the code face, … (style.mbt)
  double w, h, ox, oy;
  int color;
} glyph_entry;

static PangoFontMap *fontmap;
static PangoContext *ctx;
static double text_scale = 1;
static glyph_entry *entries;
static int n_entries, cap_entries;
static uint16_t *pool;
static size_t pool_len, pool_cap;
static int *table;  // open addressing: entry index + 1, 0 is empty
static size_t table_cap;
static int generation;
// the glyph drawn last (mb_host_glyph), its picture until it is put in its atlas (mb_host_glyph_put)
static int held_key = -1, held_w, held_h, held_colour;
static uint8_t *held_px;

void mb_text_set_family(const char *family) {
  if (!family || !*family || strlen(family) >= sizeof family_ui) return;
  strcpy(family_ui, family);
  face_ui[0] = 0;
  generation++;
}

// The family fontconfig gives `name` (an alias: sans-serif, monospace, GTK's "Sans"; or a family installed) for Latin
// words: the face the words are set in, Han then falling back by the context's language (zh-cn) to the simplified
// Chinese faces. Asked as the context asks, with zh-cn, sans-serif would be a CJK face, its Latin and its taller lines
// setting every word.
static void latin_family(const char *name, char *out, size_t cap) {
  snprintf(out, cap, "%s", name);
  FcPattern *p = FcNameParse((const FcChar8 *)name);
  if (!p) return;
  FcPatternAddString(p, FC_LANG, (const FcChar8 *)"en");
  FcConfigSubstitute(NULL, p, FcMatchPattern);
  FcDefaultSubstitute(p);
  FcResult r;
  FcPattern *m = FcFontMatch(NULL, p, &r);
  FcChar8 *f = NULL;
  if (m && FcPatternGetString(m, FC_FAMILY, 0, &f) == FcResultMatch && strlen((const char *)f) < cap)
    snprintf(out, cap, "%s", (const char *)f);
  if (m) FcPatternDestroy(m);
  FcPatternDestroy(p);
}

static void init(void) {
  if (!face_ui[0]) latin_family(family_ui, face_ui, sizeof face_ui);
  if (!face_mono[0]) latin_family(MONO, face_mono, sizeof face_mono);
  if (ctx) return;
  fontmap = pango_cairo_font_map_new();
  ctx = pango_font_map_create_context(fontmap);
  pango_context_set_language(ctx, pango_language_from_string("zh-cn"));
  pango_context_set_round_glyph_positions(ctx, FALSE);
  cairo_font_options_t *o = cairo_font_options_create();
  cairo_font_options_set_antialias(o, CAIRO_ANTIALIAS_GRAY);
  cairo_font_options_set_hint_style(o, CAIRO_HINT_STYLE_NONE);
  cairo_font_options_set_hint_metrics(o, CAIRO_HINT_METRICS_OFF);
  pango_cairo_context_set_font_options(ctx, o);
  cairo_font_options_destroy(o);
}

// ---- UTF-16 (MoonBit's) to UTF-8 (Pango's), each UTF-8 byte's place in the UTF-16 kept ----

typedef struct {
  char *s;
  int n;        // bytes
  int *at;      // at[byte]: the UTF-16 index the byte's character starts at; at[n]: the UTF-16 length
} utf8_text;

static utf8_text to_utf8(const uint16_t *u, int len) {
  utf8_text t = {malloc((size_t)len * 3 + 1), 0, malloc(((size_t)len * 3 + 1) * sizeof(int))};
  for (int i = 0; i < len;) {
    int start = i;
    uint32_t c = u[i++];
    if (c >= 0xD800 && c < 0xDC00 && i < len && u[i] >= 0xDC00 && u[i] < 0xE000)
      c = 0x10000 + ((c - 0xD800) << 10) + (u[i++] - 0xDC00);
    else if (c >= 0xD800 && c < 0xE000)
      c = 0xFFFD;  // a lone surrogate
    char b[4];
    int k = g_unichar_to_utf8(c, b);
    for (int j = 0; j < k; j++) {
      t.s[t.n] = b[j];
      t.at[t.n++] = start;
    }
  }
  t.s[t.n] = 0;
  t.at[t.n] = len;
  return t;
}

static void utf8_free(utf8_text *t) {
  free(t->s);
  free(t->at);
}

// ---- faces given (mb_host_face_add, style.mbt): fontconfig's application fonts, by the family their files make ----

#define MB_FACES 16
static struct {
  char family[128];
  int has;
} faces[MB_FACES];

static int face_id(int style) {
  int f = (style >> 8) & 15;
  if (f > 0) return faces[f].has ? f : 0;
  if (style & 2) return faces[3].has ? 3 : 0;
  if ((style & 16) && faces[2].has) return 2;
  if (style & 4) return 0;
  return faces[1].has ? 1 : 0;
}

static void faces_changed(void) {
  pango_fc_font_map_config_changed(PANGO_FC_FONT_MAP(fontmap));
  g_object_unref(ctx);
  ctx = NULL;
  PangoFontMap *fm = fontmap;
  fontmap = NULL;
  init();
  g_object_unref(fm);
  generation++;
}

// The file at `path` (fontconfig reads it) made part of face `f`: its family's name kept.
static int face_take(int f, const char *path) {
  init();
  if (f <= 0 || f >= MB_FACES) return 0;
  int count = 0;
  FcPattern *p = FcFreeTypeQuery((const FcChar8 *)path, 0, NULL, &count);
  FcChar8 *family = NULL;
  int ok = p && FcPatternGetString(p, FC_FAMILY, 0, &family) == FcResultMatch && strlen((char *)family) < 128 &&
           FcConfigAppFontAddFile(FcConfigGetCurrent(), (const FcChar8 *)path);
  if (ok) {
    strcpy(faces[f].family, (char *)family);
    faces[f].has = 1;
  }
  if (p) FcPatternDestroy(p);
  if (ok) faces_changed();
  return ok;
}

static char *utf8_of(moonbit_string_t s) {
  utf8_text t = to_utf8((const uint16_t *)s, Moonbit_array_length(s));
  free(t.at);
  return t.s;
}

int32_t mb_host_face_add(int32_t f, moonbit_string_t path, int32_t weight) {
  (void)weight;  // the files' own weights say which is which (a variable file: its named instances)
  char *p = utf8_of(path);
  int ok = face_take(f, p);
  free(p);
  return ok;
}

// A font as bytes: written to a file of this run's (fontconfig reads files), then as a file.
int32_t mb_host_face_add_bytes(int32_t f, moonbit_bytes_t data, int32_t weight) {
  (void)weight;
  static int n;
  char *dir = g_build_filename(g_get_user_runtime_dir(), "mbui-fonts", NULL);
  g_mkdir_with_parents(dir, 0700);
  char name[64];
  snprintf(name, sizeof name, "%d-%d.font", (int)getpid(), n++);
  char *path = g_build_filename(dir, name, NULL);
  int ok = g_file_set_contents(path, (const char *)data, Moonbit_array_length(data), NULL) && face_take(f, path);
  g_free(path);
  g_free(dir);
  return ok;
}

void mb_host_face_clear(int32_t f) {
  if (f <= 0 || f >= MB_FACES || !faces[f].has) return;
  faces[f].has = 0;
  faces_changed();
}

static int family_installed(const char *name) {
  init();
  PangoFontFamily **fams = NULL;
  int n = 0, there = 0;
  pango_font_map_list_families(fontmap, &fams, &n);
  for (int i = 0; i < n && !there; i++) there = g_ascii_strcasecmp(pango_font_family_get_name(fams[i]), name) == 0;
  g_free(fams);
  return there;
}

int32_t mb_host_face_add_family(int32_t f, moonbit_string_t family) {
  char *name = utf8_of(family);
  int ok = f > 0 && f < MB_FACES && strlen(name) > 0 && strlen(name) < 128 && family_installed(name);
  if (ok) {
    strcpy(faces[f].family, name);
    faces[f].has = 1;
    faces_changed();
  }
  free(name);
  return ok;
}

static int name_order(const void *a, const void *b) { return g_utf8_collate(*(char *const *)a, *(char *const *)b); }

// The families installed here as a JSON array of their names, in the order of the user's language.
moonbit_string_t mb_host_local_font_families(void) {
  init();
  PangoFontFamily **fams = NULL;
  int n = 0;
  pango_font_map_list_families(fontmap, &fams, &n);
  const char **names = calloc((size_t)(n ? n : 1), sizeof(char *));
  for (int i = 0; i < n; i++) names[i] = pango_font_family_get_name(fams[i]);
  qsort(names, (size_t)n, sizeof(char *), name_order);
  GString *out = g_string_new("[");
  for (int i = 0; i < n; i++) {
    if (i) g_string_append_c(out, ',');
    g_string_append_c(out, '"');
    for (const char *c = names[i]; *c; c++) {
      if (*c == '"' || *c == '\\') g_string_append_c(out, '\\');
      g_string_append_c(out, (unsigned char)*c < 0x20 ? ' ' : *c);
    }
    g_string_append_c(out, '"');
  }
  g_string_append_c(out, ']');
  free(names);
  g_free(fams);
  glong len = 0;
  gunichar2 *u = g_utf8_to_utf16(out->str, -1, NULL, &len, NULL);
  g_string_free(out, TRUE);
  moonbit_string_t s = moonbit_make_string_raw((int32_t)len);
  if (len) memcpy(s, u, (size_t)len * 2);
  g_free(u);
  return s;
}

// ---- a style's font and layouts ----

static PangoFontDescription *desc_for(double size, int weight, int style) {
  int face = face_id(style);
  PangoFontDescription *d = pango_font_description_new();
  const char *family = face ? faces[face].family : (style & 2) ? face_mono : (style & 4) ? SERIF : face_ui;
  pango_font_description_set_family(d, family);
  pango_font_description_set_weight(d, (PangoWeight)weight);
  pango_font_description_set_style(d, (style & 1) ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL);
  pango_font_description_set_absolute_size(d, size * PANGO_SCALE);
  return d;
}

// style & 8: no ligatures (words with letter spacing, each cluster spaced on its own); style & 32: digits all one
// width (style.mbt style_tabular)
static PangoLayout *make_layout(const char *s, int n, double size, int weight, int style) {
  PangoLayout *l = pango_layout_new(ctx);
  PangoFontDescription *d = desc_for(size, weight, style);
  pango_layout_set_font_description(l, d);
  pango_font_description_free(d);
  if (style & (8 | 32)) {
    PangoAttrList *a = pango_attr_list_new();
    const char *f = (style & 8) && (style & 32) ? "liga=0,clig=0,tnum=1" : (style & 8) ? "liga=0,clig=0" : "tnum=1";
    pango_attr_list_insert(a, pango_attr_font_features_new(f));
    pango_layout_set_attributes(l, a);
    pango_attr_list_unref(a);
  }
  pango_layout_set_text(l, s, n);
  return l;
}

static double metric(int v) { return v / (double)PANGO_SCALE; }

void mb_host_font_metrics(double size, int32_t weight, int32_t style, double *out) {
  init();
  PangoFontDescription *d = desc_for(size, weight, style);
  PangoFont *f = pango_context_load_font(ctx, d);
  PangoFontMetrics *m = f ? pango_font_get_metrics(f, NULL) : NULL;
  out[0] = m ? metric(pango_font_metrics_get_ascent(m)) : size * 0.93;
  out[1] = m ? metric(pango_font_metrics_get_descent(m)) : size * 0.24;
  out[2] = round(size * 1.42);
  // the face a Han ideograph falls back to: a line with Chinese in it is measured by the taller
  PangoFontset *fs = pango_context_load_fontset(ctx, d, pango_language_from_string("zh-cn"));
  PangoFont *han = fs ? pango_fontset_get_font(fs, 0x56FD) : NULL;
  PangoFontMetrics *hm = han ? pango_font_get_metrics(han, NULL) : NULL;
  out[3] = hm ? metric(pango_font_metrics_get_ascent(hm)) : out[0];
  out[4] = hm ? metric(pango_font_metrics_get_descent(hm)) : out[1];
  out[5] = 0;  // lines as asked, not on whole pixels
  if (hm) pango_font_metrics_unref(hm);
  if (han) g_object_unref(han);
  if (fs) g_object_unref(fs);
  if (m) pango_font_metrics_unref(m);
  if (f) g_object_unref(f);
  pango_font_description_free(d);
}

// ---- the clusters' keys ----

static uint32_t hash(const uint16_t *s, int len, double size, int weight, int style) {
  uint32_t h = 2166136261u;
  for (int i = 0; i < len; i++) h = (h ^ s[i]) * 16777619u;
  h = (h ^ (uint32_t)(size * 64)) * 16777619u;
  h = (h ^ (uint32_t)style) * 16777619u;
  return (h ^ (uint32_t)weight) * 16777619u;
}

static int same(const glyph_entry *e, const uint16_t *s, int len, double size, int weight, int style) {
  return e->len == len && e->size == size && e->weight == weight && e->style == style &&
         memcmp(pool + e->off, s, (size_t)len * sizeof(uint16_t)) == 0;
}

static void table_put(int id) {
  glyph_entry *e = &entries[id];
  size_t i = hash(pool + e->off, e->len, e->size, e->weight, e->style) & (table_cap - 1);
  while (table[i]) i = (i + 1) & (table_cap - 1);
  table[i] = id + 1;
}

static int intern(const uint16_t *s, int len, double size, int weight, int style) {
  if (table_cap) {
    size_t i = hash(s, len, size, weight, style) & (table_cap - 1);
    for (; table[i]; i = (i + 1) & (table_cap - 1))
      if (same(&entries[table[i] - 1], s, len, size, weight, style)) return table[i] - 1;
  }
  if (n_entries == cap_entries) {
    cap_entries = cap_entries ? cap_entries * 2 : 1024;
    entries = realloc(entries, sizeof(glyph_entry) * (size_t)cap_entries);
  }
  if (pool_len + (size_t)len > pool_cap) {
    pool_cap = (pool_len + len) * 2 + 4096;
    pool = realloc(pool, pool_cap * sizeof(uint16_t));
  }
  memcpy(pool + pool_len, s, (size_t)len * sizeof(uint16_t));
  int id = n_entries++;
  entries[id] = (glyph_entry){(int)pool_len, len, size, weight, style, 0, 0, 0, 0, 0};
  pool_len += len;
  if ((size_t)n_entries * 2 > table_cap) {
    free(table);
    table_cap = table_cap ? table_cap * 2 : 4096;
    table = calloc(table_cap, sizeof(int));
    for (int j = 0; j < n_entries; j++) table_put(j);
  } else {
    table_put(id);
  }
  return id;
}

// ---- shaping: the layout's clusters in the text's order, each its bytes and its advance ----

typedef struct {
  int start, end;  // bytes
  double adv;
} cluster;

static int by_start(const void *a, const void *b) { return ((const cluster *)a)->start - ((const cluster *)b)->start; }

static cluster *cs;
static int n_cs, cs_cap;

// A run's clusters: its glyphs grouped by the character each began from (log_clusters; in a right-to-left run the
// glyphs go the other way), each as wide as its glyphs, as long as up to the next one's start (or the run's end).
static void run_clusters(PangoGlyphItem *run) {
  PangoItem *item = run->item;
  PangoGlyphString *g = run->glyphs;
  int first = n_cs;
  for (int i = 0; i < g->num_glyphs; i++) {
    int at = item->offset + g->log_clusters[i];
    int k = n_cs - 1;
    while (k >= first && cs[k].start != at) k--;
    if (k < first) {
      if (n_cs == cs_cap) {
        cs_cap = cs_cap ? cs_cap * 2 : 1024;
        cs = realloc(cs, sizeof *cs * (size_t)cs_cap);
      }
      cs[n_cs++] = (cluster){at, 0, 0};
      k = n_cs - 1;
    }
    cs[k].adv += metric(g->glyphs[i].geometry.width);
  }
  qsort(cs + first, (size_t)(n_cs - first), sizeof *cs, by_start);
  for (int k = first; k < n_cs; k++) cs[k].end = k + 1 < n_cs ? cs[k + 1].start : item->offset + item->length;
}

int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, int32_t style, double *out) {
  init();
  int32_t len = Moonbit_array_length(text);
  int32_t cap = Moonbit_array_length(out) / 4;
  const uint16_t *s = (const uint16_t *)text;
  if (len == 0) return 0;
  utf8_text t = to_utf8(s, len);
  PangoLayout *l = make_layout(t.s, t.n, size, weight, style);
  n_cs = 0;
  for (GSList *line = pango_layout_get_lines_readonly(l); line; line = line->next)
    for (GSList *r = ((PangoLayoutLine *)line->data)->runs; r; r = r->next) run_clusters(r->data);
  g_object_unref(l);
  qsort(cs, (size_t)n_cs, sizeof *cs, by_start);
  // each cluster with its UTF-16 span from its bytes'; what lies in none (a line break, a control) as its own, 0 wide
  int32_t k = 0, pos = 0;
  for (int i = 0; i <= n_cs && k < cap; i++) {
    int from = i < n_cs ? t.at[cs[i].start] : len;
    while (pos < from && k < cap) {
      out[k * 4] = pos;
      out[k * 4 + 1] = 1;
      out[k * 4 + 2] = 0;
      out[k * 4 + 3] = -1;
      k++;
      pos++;
    }
    if (i == n_cs || k >= cap) break;
    int to = t.at[cs[i].end];
    if (to <= pos) continue;
    uint16_t c = s[pos];
    int blank = c == ' ' || c == '\t' || c == '\n' || c == '\r';
    out[k * 4] = pos;
    out[k * 4 + 1] = to - pos;
    out[k * 4 + 2] = c == '\n' || c == '\r' ? 0 : cs[i].adv < 0 ? 0 : cs[i].adv;
    out[k * 4 + 3] = blank ? -1 : intern(s + pos, to - pos, size, weight, style);
    k++;
    pos = to;
  }
  utf8_free(&t);
  return k;
}

// The key of a piece of text drawn whole (a word of a joining script): host_native.mbt's text_key.
int32_t mb_host_text_key(moonbit_string_t text, double size, int32_t weight, int32_t style) {
  init();
  return intern((const uint16_t *)text, Moonbit_array_length(text), size, weight, style);
}

int32_t mb_host_atlas_generation(void) { return generation; }

int32_t mb_host_atlas_size(int32_t colour) { return colour ? MB_ATLAS_COLOR : MB_ATLAS; }

void mb_text_set_scale(double scale) {
  if (scale == text_scale) return;
  text_scale = scale;
  generation++;
}

// ---- a cluster drawn: in white, a pixel round its ink, its picture held for mb_host_glyph_put ----

static void rasterize(int key) {
  glyph_entry *e = &entries[key];
  free(held_px);
  held_px = NULL;
  held_key = -1;
  e->w = e->h = 0;
  utf8_text t = to_utf8(pool + e->off, e->len);
  PangoLayout *l = make_layout(t.s, t.n, e->size, e->weight, e->style);
  utf8_free(&t);
  PangoRectangle ink, logical;
  pango_layout_get_extents(l, &ink, &logical);
  double base = metric(pango_layout_get_baseline(l));
  double x0 = metric(ink.x), y0 = metric(ink.y), x1 = metric(ink.x + ink.width), y1 = metric(ink.y + ink.height);
  if (ink.width <= 0 || ink.height <= 0) {
    x0 = 0, y0 = 0, x1 = metric(logical.width), y1 = metric(logical.height);
  }
  double sc = text_scale;
  // the picture's edges on whole pixels from the baseline, a pixel of room round it: the baseline then falls on a pixel
  // row of every glyph's picture, so glyphs on the same rounded baseline line up
  int px0 = (int)floor(x0 * sc) - 1, px1 = (int)ceil(x1 * sc) + 1;
  int py0 = (int)floor((y0 - base) * sc) - 1, py1 = (int)ceil((y1 - base) * sc) + 1;
  int pw = px1 - px0, ph = py1 - py0;
  if (pw <= 0 || ph <= 0 || pw > MAX_PX || ph > MAX_PX) {
    g_object_unref(l);
    return;
  }
  cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, pw, ph);
  cairo_t *cr = cairo_create(surf);
  cairo_translate(cr, -px0, -py0);
  cairo_scale(cr, sc, sc);
  cairo_move_to(cr, 0, -base);
  cairo_set_source_rgb(cr, 1, 1, 1);
  pango_cairo_show_layout(cr, l);
  cairo_destroy(cr);
  cairo_surface_flush(surf);
  const uint8_t *src = cairo_image_surface_get_data(surf);
  int stride = cairo_image_surface_get_stride(surf);
  // a colour glyph's (an emoji's): drawn in white, a mask's pixel has its colour equal to its cover; an emoji's does
  // not
  int colour = 0;
  for (int y = 0; y < ph && !colour; y++) {
    const uint32_t *p = (const uint32_t *)(src + (size_t)y * stride);
    for (int x = 0; x < pw; x++) {
      uint32_t v = p[x];
      int a = v >> 24, r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
      if (a > 64 && (r + 32 < a || g + 32 < a || b + 32 < a)) {
        colour = 1;
        break;
      }
    }
  }
  uint8_t *px = malloc((size_t)pw * ph * (colour ? 4 : 1));
  for (int y = 0; y < ph; y++) {
    const uint32_t *p = (const uint32_t *)(src + (size_t)y * stride);
    for (int x = 0; x < pw; x++) {
      uint32_t v = p[x];
      if (colour) {
        uint8_t *d = px + ((size_t)y * pw + x) * 4;
        d[0] = (v >> 16) & 255;
        d[1] = (v >> 8) & 255;
        d[2] = v & 255;
        d[3] = v >> 24;
      } else {
        px[(size_t)y * pw + x] = v >> 24;
      }
    }
  }
  cairo_surface_destroy(surf);
  g_object_unref(l);
  held_key = key;
  held_w = pw;
  held_h = ph;
  held_colour = colour;
  held_px = px;
  e->w = pw / sc;
  e->h = ph / sc;
  e->ox = px0 / sc;
  e->oy = py0 / sc;
  e->color = colour;
}

// (a glyph drawn as it is first asked for: nothing ahead)
void mb_host_glyphs_ahead(int32_t *keys, int32_t n) {
  (void)keys;
  (void)n;
}

void mb_host_glyph(int32_t key, double *out) {
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

// The glyph drawn last put in its atlas, its top left at x, y (a colour glyph's x MB_ATLAS_COLOR_U past its place).
void mb_host_glyph_put(int32_t key, int32_t x, int32_t y) {
  if (key != held_key || !held_px) return;
  if (held_colour) mb_atlas_put(1, x - MB_ATLAS_COLOR_U, y, held_w, held_h, held_px);
  else mb_atlas_put(0, x, y, held_w, held_h, held_px);
  free(held_px);
  held_px = NULL;
  held_key = -1;
}

// ---------------------------------------------------------------------------
// The platform's own drawing of a line (textref_native.mbt, for src/textdiff): Pango's layout with its default features
// and the fonts above, drawn by cairo with the settings above, at the places mbui draws the same words.

static cairo_surface_t *ref_surf;
static cairo_t *ref_cr;

static void ref_path(moonbit_string_t name, char *out, size_t cap) {
  const char *dir = getenv("MBUI_SHOT_DIR");
  char *n = utf8_of(name);
  snprintf(out, cap, "%s/%s.png", dir ? dir : ".", n);
  free(n);
}

static void rgb(cairo_t *cr, int c) {
  cairo_set_source_rgb(cr, ((c >> 16) & 255) / 255.0, ((c >> 8) & 255) / 255.0, (c & 255) / 255.0);
}

void mb_host_ref_begin(double w, double h, double scale, int32_t bg) {
  init();
  if (ref_cr) cairo_destroy(ref_cr);
  if (ref_surf) cairo_surface_destroy(ref_surf);
  ref_surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)floor(w * scale + 0.5), (int)floor(h * scale + 0.5));
  ref_cr = cairo_create(ref_surf);
  rgb(ref_cr, bg);
  cairo_paint(ref_cr);
  cairo_scale(ref_cr, scale, scale);
}

void mb_host_ref_text(moonbit_string_t text, double size, int32_t weight, int32_t style, double x, double base,
                      int32_t color, double *out) {
  for (int i = 0; i < 5; i++) out[i] = 0;
  if (!ref_cr) return;
  utf8_text t = to_utf8((const uint16_t *)text, Moonbit_array_length(text));
  PangoLayout *l = make_layout(t.s, t.n, size, weight, style);
  utf8_free(&t);
  PangoRectangle logical;
  pango_layout_get_extents(l, NULL, &logical);
  rgb(ref_cr, color);
  cairo_move_to(ref_cr, x, base - metric(pango_layout_get_baseline(l)));
  pango_cairo_show_layout(ref_cr, l);
  out[0] = metric(logical.width);
  g_object_unref(l);
}

int32_t mb_host_ref_end(moonbit_string_t name) {
  if (!ref_cr) return 0;
  char path[1024];
  ref_path(name, path, sizeof path);
  cairo_surface_flush(ref_surf);
  int ok = cairo_surface_write_to_png(ref_surf, path) == CAIRO_STATUS_SUCCESS;
  cairo_destroy(ref_cr);
  cairo_surface_destroy(ref_surf);
  ref_cr = NULL;
  ref_surf = NULL;
  return ok;
}

int32_t mb_host_ref_frame(moonbit_string_t name) {
  char path[1024];
  ref_path(name, path, sizeof path);
  return mb_render_snapshot(path);
}
