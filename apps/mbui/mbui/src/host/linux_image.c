// Images on Linux: gdk-pixbuf decodes them on a small pool of threads straight to the size asked for (its loader told
// the size as it learns the picture's: the JPEG loader then decodes at a reduced size), turned by the EXIF
// orientation, premultiplied; the texture made from that in the GL context as the next frame begins, and only then
// the image ready (its decode told). A file's path (file:// too), or http(s) through libsoup; or bytes. What it was
// made from kept, to decode it again for a new context.
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
} image;

// by id (ids are not reused); the main thread grows it, the pool's threads fill entries in (under lock)
static image *imgs;
static int nimgs, img_cap;
static GMutex lock;
static GThreadPool *pool;
static int log_times;

static void work(gpointer item, gpointer user);

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
  int max_px = imgs[id].max_px;
  g_mutex_unlock(&lock);
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

static int start(char *src, GBytes *data, int max_px) {
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
  imgs[id].max_px = max_px;
  g_mutex_unlock(&lock);
  g_thread_pool_push(pool, GINT_TO_POINTER(id), NULL);
  return id;
}

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
