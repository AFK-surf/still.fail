// Images on Linux: gdk-pixbuf decodes them on a small pool of threads straight to the size asked for (its loader told
// the size as it learns the picture's: the JPEG loader then decodes at a reduced size), turned by the EXIF
// orientation, premultiplied; the texture made from that in the GL context as the next frame begins, and only then
// the image ready (its decode told). A file's path (file:// too), or http(s) through libsoup; or bytes. What it was
// made from kept, to decode it again for a new context. Also a PDF's pages drawn into images (poppler's, below).
#include <dlfcn.h>
#include <cairo.h>
#include <epoxy/gl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <glib.h>
#include <libsoup/soup.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "linux.h"

typedef struct {
  int state;  // 0 decoding, 1 ready, -1 failed or freed
  int w, h, ow, oh;
  GLuint tex;
  uint8_t *px;  // decoded, its texture not made yet (premultiplied RGBA, w × h)
  int untold;   // decoded (or failed), not yet told to the app (mb_images_tell)
  int told;     // its first decode told: not again when decoded anew for a new context
  int max_px;
  char *src;    // what it was made from: a path or a URL, or
  GBytes *data;
  struct page *page;  // a PDF's page (pdf_page_load)
} image;

// by id (ids are not reused); the main thread grows it, the pool's threads fill entries in (under lock)
static image *imgs;
static int nimgs, img_cap;
static GMutex lock;
static GThreadPool *pool;
static int log_times;

static void work(gpointer item, gpointer user);
static uint8_t *draw_page(struct page *pg, int max_px, int *w, int *h, int *ow, int *oh);
static struct page *page_hold(struct page *pg);
static void page_free(struct page *pg);

static void setup(void) {
  if (pool) return;
  // a few at a time, so a grid scrolled fast doesn't keep every core busy with pictures already off screen
  pool = g_thread_pool_new(work, NULL, 3, FALSE, NULL);
  const char *b = getenv("MBUI_BENCH");
  log_times = b && atoi(b) != 0;
}

typedef struct {
  int max_px, sw, sh;
} sizing;

// the size to decode at (gdk-pixbuf's loader, as it learns the picture's): at most max_px a side
static void size_prepared(GdkPixbufLoader *l, int w, int h, gpointer data) {
  sizing *s = data;
  s->sw = w;
  s->sh = h;
  double k = fmin(1.0, s->max_px / (double)(w > h ? w : h));
  if (k < 1) {
    int tw = (int)lround(w * k), th = (int)lround(h * k);
    gdk_pixbuf_loader_set_size(l, tw > 0 ? tw : 1, th > 0 ? th : 1);
  }
}

static GBytes *fetch(const char *url) {
  static SoupSession *session;
  static GMutex once;
  g_mutex_lock(&once);
  if (!session) session = soup_session_new();
  g_mutex_unlock(&once);
  SoupMessage *m = soup_message_new("GET", url);
  if (!m) return NULL;
  GBytes *b = soup_session_send_and_read(session, m, NULL, NULL);
  if (b && soup_message_get_status(m) != SOUP_STATUS_OK) {
    g_bytes_unref(b);
    b = NULL;
  }
  g_object_unref(m);
  return b;
}

// decoded: premultiplied RGBA, upright; NULL when it is not a picture gdk-pixbuf reads
static uint8_t *decode(GBytes *bytes, int max_px, int *w, int *h, int *ow, int *oh) {
  sizing s = {max_px, 0, 0};
  GdkPixbufLoader *l = gdk_pixbuf_loader_new();
  g_signal_connect(l, "size-prepared", G_CALLBACK(size_prepared), &s);
  gsize n = 0;
  const guchar *d = g_bytes_get_data(bytes, &n);
  int ok = gdk_pixbuf_loader_write(l, d, n, NULL);
  ok = gdk_pixbuf_loader_close(l, NULL) && ok;
  GdkPixbuf *pb = ok ? gdk_pixbuf_loader_get_pixbuf(l) : NULL;
  uint8_t *out = NULL;
  if (pb) {
    const char *o = gdk_pixbuf_get_option(pb, "orientation");
    int turned = o && atoi(o) >= 5 && atoi(o) <= 8;
    *ow = turned ? s.sh : s.sw;
    *oh = turned ? s.sw : s.sh;
    GdkPixbuf *up = gdk_pixbuf_apply_embedded_orientation(pb);
    int pw = gdk_pixbuf_get_width(up), ph = gdk_pixbuf_get_height(up), stride = gdk_pixbuf_get_rowstride(up);
    int ch = gdk_pixbuf_get_n_channels(up), alpha = gdk_pixbuf_get_has_alpha(up);
    const guchar *src = gdk_pixbuf_read_pixels(up);
    out = malloc((size_t)pw * ph * 4);
    for (int y = 0; y < ph; y++) {
      const guchar *r = src + (size_t)y * stride;
      uint8_t *o4 = out + (size_t)y * pw * 4;
      for (int x = 0; x < pw; x++) {
        int a = alpha ? r[x * ch + 3] : 255;
        o4[x * 4] = (uint8_t)((r[x * ch] * a + 127) / 255);
        o4[x * 4 + 1] = (uint8_t)((r[x * ch + 1] * a + 127) / 255);
        o4[x * 4 + 2] = (uint8_t)((r[x * ch + 2] * a + 127) / 255);
        o4[x * 4 + 3] = (uint8_t)a;
      }
    }
    *w = pw;
    *h = ph;
    g_object_unref(up);
  }
  g_object_unref(l);
  return out;
}

static void work(gpointer item, gpointer user) {
  (void)user;
  int id = GPOINTER_TO_INT(item);
  gint64 t0 = g_get_monotonic_time();
  g_mutex_lock(&lock);
  char *src = g_strdup(imgs[id].src);
  GBytes *data = imgs[id].data ? g_bytes_ref(imgs[id].data) : NULL;
  // (a page of its own, its document held: the image may be freed while it is drawn)
  struct page *page = imgs[id].page ? page_hold(imgs[id].page) : NULL;
  int max_px = imgs[id].max_px;
  g_mutex_unlock(&lock);
  if (page) {
    int w = 0, h = 0, ow = 0, oh = 0;
    uint8_t *px = draw_page(page, max_px, &w, &h, &ow, &oh);
    page_free(page);
    g_mutex_lock(&lock);
    image *im = &imgs[id];
    if (im->state == 0 && !im->px) {
      im->w = w, im->h = h, im->ow = ow, im->oh = oh;
      im->px = px;
      if (!px) im->state = -1, im->untold = !im->told;
      px = NULL;
    }
    g_mutex_unlock(&lock);
    free(px);  // freed meanwhile
    mb_app_wake();
    return;
  }
  if (!data && src) {
    if (!strncmp(src, "http://", 7) || !strncmp(src, "https://", 8)) {
      data = fetch(src);
    } else {
      const char *path = !strncmp(src, "file://", 7) ? src + 7 : src;
      gchar *d = NULL;
      gsize n = 0;
      if (g_file_get_contents(path, &d, &n, NULL)) data = g_bytes_new_take(d, n);
    }
  }
  int w = 0, h = 0, ow = 0, oh = 0;
  uint8_t *px = data ? decode(data, max_px, &w, &h, &ow, &oh) : NULL;
  if (data) g_bytes_unref(data);
  if (log_times)
    fprintf(stdout, "image %dx%d -> %dx%d in %.1f ms: %s\n", ow, oh, w, h, (g_get_monotonic_time() - t0) / 1000.0,
            src ? src : "(bytes)");
  g_free(src);
  g_mutex_lock(&lock);
  image *im = &imgs[id];
  if (im->state == 0 && !im->px) {
    im->w = w, im->h = h, im->ow = ow, im->oh = oh;
    im->px = px;
    if (!px) {
      im->state = -1;
      im->untold = !im->told;
    }
    px = NULL;
  }
  g_mutex_unlock(&lock);
  free(px);  // freed meanwhile
  mb_app_wake();
}

// an image made from a path or a URL, bytes, or a PDF's page, as one of the pool's threads gets to it
static int start_page(char *src, GBytes *data, struct page *page, int max_px) {
  setup();
  g_mutex_lock(&lock);
  if (nimgs == 0) nimgs = 1;  // 0 is no image
  if (nimgs >= img_cap) {
    img_cap = img_cap ? img_cap * 2 : 256;
    imgs = realloc(imgs, (size_t)img_cap * sizeof *imgs);
  }
  int id = nimgs++;
  imgs[id] = (image){0};
  imgs[id].src = src;
  imgs[id].data = data;
  imgs[id].page = page;
  imgs[id].max_px = max_px;
  g_mutex_unlock(&lock);
  g_thread_pool_push(pool, GINT_TO_POINTER(id), NULL);
  return id;
}

static int start(char *src, GBytes *data, int max_px) { return start_page(src, data, NULL, max_px); }

static char *utf8_of(moonbit_string_t s) {
  glong n = 0;
  return g_utf16_to_utf8((const gunichar2 *)s, Moonbit_array_length(s), NULL, &n, NULL);
}

int32_t mb_host_image_load(moonbit_string_t s, int32_t max_px) {
  char *src = utf8_of(s);
  return start(src ? src : g_strdup(""), NULL, max_px);
}

int32_t mb_host_image_load_bytes(moonbit_bytes_t data, int32_t max_px) {
  return start(NULL, g_bytes_new(data, Moonbit_array_length(data)), max_px);
}

int32_t mb_host_image_info(int32_t id, double *out) {
  if (id <= 0 || id >= nimgs) return -1;
  g_mutex_lock(&lock);
  image im = imgs[id];
  g_mutex_unlock(&lock);
  if (im.state == 1) {
    out[0] = im.w, out[1] = im.h, out[2] = im.ow, out[3] = im.oh;
  }
  return im.state;
}

static void tex_gone(GLuint t);

void mb_host_image_free(int32_t id) {
  if (id <= 0 || id >= nimgs) return;
  g_mutex_lock(&lock);
  image im = imgs[id];
  imgs[id] = (image){-1};
  g_mutex_unlock(&lock);
  tex_gone(im.tex);
  free(im.px);
  g_free(im.src);
  if (im.data) g_bytes_unref(im.data);
  if (im.page) page_free(im.page);
}

// the textures of images freed, deleted as the next frame's are made (the context current then)
static GLuint *gone_texs;
static int n_gone, gone_cap;

static void tex_gone(GLuint t) {
  if (!t) return;
  if (n_gone == gone_cap) {
    gone_cap = gone_cap ? gone_cap * 2 : 64;
    gone_texs = realloc(gone_texs, sizeof *gone_texs * (size_t)gone_cap);
  }
  gone_texs[n_gone++] = t;
}

static GLuint make_tex(const uint8_t *px, int w, int h) {
  GLuint t = 0;
  glGenTextures(1, &t);
  glBindTexture(GL_TEXTURE_2D, t);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
  return t;
}

void mb_images_upload(void) {
  if (n_gone) {
    glDeleteTextures(n_gone, gone_texs);
    n_gone = 0;
  }
  if (!pool) return;
  for (int id = 1; id < nimgs; id++) {
    g_mutex_lock(&lock);
    image *im = &imgs[id];
    uint8_t *px = im->state == 0 ? im->px : NULL;
    int w = im->w, h = im->h;
    im->px = NULL;
    g_mutex_unlock(&lock);
    if (!px) continue;
    GLuint t = make_tex(px, w, h);
    free(px);
    g_mutex_lock(&lock);
    if (imgs[id].state == 0) {
      imgs[id].tex = t;
      imgs[id].state = 1;
      imgs[id].untold = !imgs[id].told;
      t = 0;
    }
    g_mutex_unlock(&lock);
    tex_gone(t);
  }
}

void mb_images_tell(mb_outside_fn f) {
  if (!pool) return;  // no image asked for yet
  for (int id = 1; id < nimgs; id++) {
    g_mutex_lock(&lock);
    int tell = imgs[id].untold && imgs[id].state != 0;
    int state = imgs[id].state;
    if (tell) imgs[id].untold = 0, imgs[id].told = 1;
    g_mutex_unlock(&lock);
    if (tell && f) f(MB_OUTSIDE_IMAGE, id, state);
  }
}

unsigned mb_image_tex(int id) {
  if (id <= 0 || id >= nimgs) return 0;
  return imgs[id].state == 1 ? imgs[id].tex : 0;
}

// A new context: every ready one decoded again (its texture made as it comes), not told again.
void mb_images_lost(void) {
  n_gone = 0;  // (the old context's, gone with it)
  if (!pool) return;
  for (int id = 1; id < nimgs; id++) {
    g_mutex_lock(&lock);
    int again = imgs[id].state == 1;
    if (again) {
      imgs[id].state = 0;
      imgs[id].tex = 0;
    }
    g_mutex_unlock(&lock);
    if (again) g_thread_pool_push(pool, GINT_TO_POINTER(id), NULL);
  }
}

// A ready image's pixels read back from its texture through a framebuffer of its own (premultiplied RGBA, as made),
// rows from the top (as they were made).
int32_t mb_host_image_pixels(int32_t id, moonbit_bytes_t out) {
  if (id <= 0 || id >= nimgs) return 0;
  image *im = &imgs[id];
  if (im->state != 1 || !im->tex) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)im->w * im->h * 4) return 0;
  GLint was = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &was);
  GLuint fb = 0;
  glGenFramebuffers(1, &fb);
  glBindFramebuffer(GL_FRAMEBUFFER, fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, im->tex, 0);
  int ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  if (ok) {
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, im->w, im->h, GL_RGBA, GL_UNSIGNED_BYTE, out);
  }
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)was);
  glDeleteFramebuffers(1, &fb);
  return ok;
}

// ---- PDFs (host_native.mbt pdf_*): poppler's (its GLib face, libpoppler-glib.so.8, loaded as the first is opened:
// nothing of it linked, so the app starts where it is not installed; there pdf_open answers 0 and the app says it
// cannot show the PDF). A page drawn on white with cairo into an image, at most max_px on its longer side and turned
// as the page says (its /Rotate), on the pool's threads; one page of a document at a time (poppler draws none of a
// document from two threads at once). ----

static struct {
  void *(*doc_new)(GBytes *, const char *, GError **);
  int (*n_pages)(void *);
  void *(*get_page)(void *, int);
  void (*page_size)(void *, double *, double *);
  void (*render)(void *, cairo_t *);
} pp;
static int pp_state;  // 0 not looked for, 1 here, -1 not

static int pp_here(void) {
  if (pp_state) return pp_state > 0;
  pp_state = -1;
  void *h = dlopen("libpoppler-glib.so.8", RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    fprintf(stdout, "pdf: no poppler (%s): PDFs cannot be shown\n", dlerror());
    return 0;
  }
  *(void **)&pp.doc_new = dlsym(h, "poppler_document_new_from_bytes");
  *(void **)&pp.n_pages = dlsym(h, "poppler_document_get_n_pages");
  *(void **)&pp.get_page = dlsym(h, "poppler_document_get_page");
  *(void **)&pp.page_size = dlsym(h, "poppler_page_get_size");
  *(void **)&pp.render = dlsym(h, "poppler_page_render");
  if (!pp.doc_new || !pp.n_pages || !pp.get_page || !pp.page_size || !pp.render) {
    fprintf(stdout, "pdf: a poppler without what it draws with: PDFs cannot be shown\n");
    return 0;
  }
  pp_state = 1;
  return 1;
}

typedef struct {
  GMutex lock;    // one page of it drawn at a time
  void *doc;      // PopplerDocument; NULL: it could not be opened
  int refs;       // the app's (until pdf_close) and each page's image's
} pdf;

struct page {
  pdf *doc;
  int at;
};

static GPtrArray *pdfs;  // by id (ids are not reused; 0 is none)
static GMutex pdfs_lock;

static void pdf_unref(pdf *d) {
  g_mutex_lock(&pdfs_lock);
  int last = --d->refs == 0;
  g_mutex_unlock(&pdfs_lock);
  if (!last) return;
  if (d->doc) g_object_unref(d->doc);
  g_mutex_clear(&d->lock);
  g_free(d);
}

static pdf *pdf_of(int id) {
  return pdfs && id > 0 && (guint)id < pdfs->len ? g_ptr_array_index(pdfs, id) : NULL;
}

static struct page *page_hold(struct page *pg) {
  struct page *held = g_new(struct page, 1);
  g_mutex_lock(&pdfs_lock);
  pg->doc->refs++;
  g_mutex_unlock(&pdfs_lock);
  held->doc = pg->doc;
  held->at = pg->at;
  return held;
}

static void page_free(struct page *pg) {
  pdf_unref(pg->doc);
  g_free(pg);
}

int32_t mb_host_pdf_open(moonbit_bytes_t data) {
  if (!pp_here()) return 0;
  if (!pdfs) pdfs = g_ptr_array_new(), g_ptr_array_add(pdfs, NULL);
  pdf *d = g_new0(pdf, 1);
  g_mutex_init(&d->lock);
  d->refs = 1;
  GBytes *b = g_bytes_new(data, (gsize)Moonbit_array_length(data));
  // (encrypted with no password, as one forbidding only printing or copying is: opened)
  d->doc = pp.doc_new(b, NULL, NULL);
  g_bytes_unref(b);
  g_ptr_array_add(pdfs, d);
  return (int32_t)pdfs->len - 1;
}

int32_t mb_host_pdf_pages(int32_t doc) {
  pdf *d = pdf_of(doc);
  if (!d || !d->doc) return -1;
  g_mutex_lock(&d->lock);
  int n = pp.n_pages(d->doc);
  g_mutex_unlock(&d->lock);
  return n;
}

// a page's size in points, turned as it is shown (poppler's: its /Rotate taken in)
void mb_host_pdf_page_size(int32_t doc, int32_t page, double *out) {
  out[0] = out[1] = 0;
  pdf *d = pdf_of(doc);
  if (!d || !d->doc) return;
  g_mutex_lock(&d->lock);
  void *pg = page >= 0 && page < pp.n_pages(d->doc) ? pp.get_page(d->doc, page) : NULL;
  if (pg) pp.page_size(pg, &out[0], &out[1]), g_object_unref(pg);
  g_mutex_unlock(&d->lock);
}

int32_t mb_host_pdf_page_load(int32_t doc, int32_t page, int32_t max_px) {
  pdf *d = pdf_of(doc);
  if (!d || !d->doc) return 0;
  struct page *pg = g_new(struct page, 1);
  g_mutex_lock(&pdfs_lock);
  d->refs++;
  g_mutex_unlock(&pdfs_lock);
  pg->doc = d;
  pg->at = page;
  return start_page(NULL, NULL, pg, max_px > 0 ? (max_px < 8192 ? max_px : 8192) : 1024);
}

// (its pages' images hold it until they are freed)
void mb_host_pdf_close(int32_t doc) {
  pdf *d = pdf_of(doc);
  if (!d) return;
  g_ptr_array_index(pdfs, doc) = NULL;
  pdf_unref(d);
}

// A page drawn: premultiplied RGBA, upright, its size in points (rounded) as the original's; NULL past its pages.
static uint8_t *draw_page(struct page *p, int max_px, int *w, int *h, int *ow, int *oh) {
  pdf *d = p->doc;
  uint8_t *out = NULL;
  g_mutex_lock(&d->lock);
  void *pg = p->at >= 0 && p->at < pp.n_pages(d->doc) ? pp.get_page(d->doc, p->at) : NULL;
  double pw = 0, ph = 0;
  if (pg) pp.page_size(pg, &pw, &ph);
  if (pg && pw > 0 && ph > 0) {
    double k = max_px / fmax(pw, ph);
    int iw = (int)fmax(1, round(pw * k)), ih = (int)fmax(1, round(ph * k));
    cairo_surface_t *sf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, iw, ih);
    cairo_t *cr = cairo_create(sf);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    cairo_scale(cr, iw / pw, ih / ph);
    pp.render(pg, cr);
    cairo_destroy(cr);
    cairo_surface_flush(sf);
    if (cairo_surface_status(sf) == CAIRO_STATUS_SUCCESS) {
      // cairo's ARGB32 is premultiplied BGRA in memory (a little-endian word): RGBA's red and blue swapped
      const uint8_t *src = cairo_image_surface_get_data(sf);
      int stride = cairo_image_surface_get_stride(sf);
      out = malloc((size_t)iw * ih * 4);
      for (int y = 0; y < ih; y++) {
        const uint8_t *r = src + (size_t)y * stride;
        uint8_t *o = out + (size_t)y * iw * 4;
        for (int x = 0; x < iw; x++, r += 4, o += 4) o[0] = r[2], o[1] = r[1], o[2] = r[0], o[3] = r[3];
      }
      *w = iw, *h = ih, *ow = (int)round(pw), *oh = (int)round(ph);
    }
    cairo_surface_destroy(sf);
  }
  if (pg) g_object_unref(pg);
  g_mutex_unlock(&d->lock);
  return out;
}
