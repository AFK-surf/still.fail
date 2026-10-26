// Streams on Linux (src/hostapi/stream.mbt, @ui's Stream): JPEG frames decoded by gdk-pixbuf on a thread of a small
// pool, a stream's one after another in the order they came, each kept as pixels until the app shows it ("f TS W H",
// then mb_host_stream_show) or a later one; one that does not decode is let go ("d TS"). The one shown becomes the
// stream's texture as the renderer first draws it (mb_stream_tex, in the GL context), so it is drawn in the frame
// that showed it. No H.264 here (h264_here is false: the sender is asked for JPEG only); an H.264 frame handed over
// anyway is let go. Each event asks for a frame (mb_app_wake). As Windows' win_stream.cpp has it.
#include <epoxy/gl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <glib.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "linux.h"

typedef struct {
  double ts;
  int w, h;
  uint8_t *px;  // RGBA, w × h (opaque: a JPEG's)
} Frame;

typedef struct {
  int id, closed, busy;
  // (under lock) what it says, oldest first; frames decoded, not shown yet; JPEGs waiting, their stamps
  GQueue events, decoded, jobs;
  // (the main thread's) the one shown: its pixels until they are its texture, then its texture
  Frame *shown;
  GLuint tex;
  int tex_w, tex_h;
} Stream;

typedef struct {
  double ts;
  GBytes *data;
} Job;

static GPtrArray *streams;  // by id (ids are not reused; 0 is none)
static GMutex lock;
static GThreadPool *pool;

static Stream *stream_of(int id) {
  return streams && id > 0 && (guint)id < streams->len ? g_ptr_array_index(streams, id) : NULL;
}

static void frame_free(Frame *f) {
  if (!f) return;
  g_free(f->px);
  g_free(f);
}

// (under lock) an event for the app: its frame asked for
static void say_locked(Stream *s, char *e) {
  if (s->closed) g_free(e);
  else g_queue_push_tail(&s->events, e);
}

static char *stamp(double ts) {
  return ts == floor(ts) && fabs(ts) < 1e15 ? g_strdup_printf("%lld", (long long)ts) : g_strdup_printf("%.17g", ts);
}

static void say_dropped(Stream *s, double ts) {
  char *t = stamp(ts);
  g_mutex_lock(&lock);
  say_locked(s, g_strdup_printf("d %s", t));
  g_mutex_unlock(&lock);
  g_free(t);
  mb_app_wake();
}

// A JPEG's pixels as RGBA: NULL when it does not decode.
static uint8_t *decode_jpeg(GBytes *data, int *w, int *h) {
  GdkPixbufLoader *l = gdk_pixbuf_loader_new_with_type("jpeg", NULL);
  if (!l) return NULL;
  gsize n = 0;
  const guchar *d = g_bytes_get_data(data, &n);
  int ok = gdk_pixbuf_loader_write(l, d, n, NULL);
  ok = gdk_pixbuf_loader_close(l, NULL) && ok;
  GdkPixbuf *pb = ok ? gdk_pixbuf_loader_get_pixbuf(l) : NULL;
  uint8_t *out = NULL;
  if (pb) {
    int pw = gdk_pixbuf_get_width(pb), ph = gdk_pixbuf_get_height(pb), stride = gdk_pixbuf_get_rowstride(pb);
    int ch = gdk_pixbuf_get_n_channels(pb);
    const guchar *src = gdk_pixbuf_read_pixels(pb);
    if (pw > 0 && ph > 0 && (ch == 3 || ch == 4)) {
      out = g_malloc((size_t)pw * ph * 4);
      for (int y = 0; y < ph; y++) {
        const guchar *r = src + (size_t)y * stride;
        uint8_t *o = out + (size_t)y * pw * 4;
        for (int x = 0; x < pw; x++, r += ch, o += 4) o[0] = r[0], o[1] = r[1], o[2] = r[2], o[3] = 255;
      }
      *w = pw;
      *h = ph;
    }
  }
  g_object_unref(l);
  return out;
}

// A stream's JPEGs decoded one after another, until none waits (a thread of the pool).
static void work(gpointer data, gpointer user) {
  (void)user;
  Stream *s = data;
  for (;;) {
    g_mutex_lock(&lock);
    Job *j = s->closed ? NULL : g_queue_pop_head(&s->jobs);
    if (!j) {
      s->busy = 0;
      g_mutex_unlock(&lock);
      break;
    }
    g_mutex_unlock(&lock);
    int w = 0, h = 0;
    uint8_t *px = decode_jpeg(j->data, &w, &h);
    char *t = stamp(j->ts);
    g_mutex_lock(&lock);
    if (px && !s->closed) {
      Frame *f = g_new0(Frame, 1);
      f->ts = j->ts, f->w = w, f->h = h, f->px = px;
      g_queue_push_tail(&s->decoded, f);
      say_locked(s, g_strdup_printf("f %s %d %d", t, w, h));
      px = NULL;
    } else {
      say_locked(s, g_strdup_printf("d %s", t));
    }
    g_mutex_unlock(&lock);
    g_free(px);
    g_free(t);
    g_bytes_unref(j->data);
    g_free(j);
    mb_app_wake();
  }
}

int32_t mb_host_stream_open(void) {
  if (!streams) {
    streams = g_ptr_array_new();
    g_ptr_array_add(streams, NULL);  // 0 is none
    pool = g_thread_pool_new(work, NULL, 2, FALSE, NULL);
  }
  Stream *s = g_new0(Stream, 1);
  s->id = (int)streams->len;
  g_queue_init(&s->events);
  g_queue_init(&s->decoded);
  g_queue_init(&s->jobs);
  g_ptr_array_add(streams, s);
  return s->id;
}

void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  (void)id, (void)avcc, (void)w, (void)h;
}

void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  (void)data, (void)key;
  Stream *s = stream_of(id);
  if (s) say_dropped(s, ts);
}

void mb_host_stream_jpeg(int32_t id, moonbit_bytes_t data, double ts) {
  Stream *s = stream_of(id);
  if (!s) return;
  Job *j = g_new(Job, 1);
  j->ts = ts;
  j->data = g_bytes_new(data, (gsize)Moonbit_array_length(data));
  g_mutex_lock(&lock);
  g_queue_push_tail(&s->jobs, j);
  int start = !s->busy && !s->closed;
  if (start) s->busy = 1;
  g_mutex_unlock(&lock);
  if (start) g_thread_pool_push(pool, s, NULL);
}

moonbit_string_t mb_host_stream_next(int32_t id) {
  Stream *s = stream_of(id);
  char *e = NULL;
  if (s) {
    g_mutex_lock(&lock);
    e = g_queue_pop_head(&s->events);
    g_mutex_unlock(&lock);
  }
  int n = e ? (int)strlen(e) : 0;
  moonbit_string_t out = moonbit_make_string_raw(n);
  for (int i = 0; i < n; i++) out[i] = (uint16_t)(unsigned char)e[i];
  g_free(e);
  return out;
}

void mb_host_stream_show(int32_t id, double ts) {
  Stream *s = stream_of(id);
  if (!s) return;
  Frame *shown = NULL;
  g_mutex_lock(&lock);
  for (GList *l = s->decoded.head; l; l = l->next)
    if (((Frame *)l->data)->ts == ts) shown = l->data;
  if (shown) {
    // it, and those decoded before it passed over
    GList *l = s->decoded.head;
    while (l) {
      GList *next = l->next;
      Frame *f = l->data;
      if (f->ts <= ts) {
        g_queue_delete_link(&s->decoded, l);
        if (f != shown) frame_free(f);
      }
      l = next;
    }
  }
  g_mutex_unlock(&lock);
  if (!shown) return;
  frame_free(s->shown);
  s->shown = shown;
}

void mb_host_stream_close(int32_t id) {
  Stream *s = stream_of(id);
  if (!s) return;
  g_mutex_lock(&lock);
  s->closed = 1;
  g_queue_clear_full(&s->events, g_free);
  g_queue_clear_full(&s->decoded, (GDestroyNotify)frame_free);
  Job *j;
  while ((j = g_queue_pop_head(&s->jobs))) g_bytes_unref(j->data), g_free(j);
  g_mutex_unlock(&lock);
  frame_free(s->shown);
  s->shown = NULL;
  // (its texture let go as the next frame begins, in the GL context: mb_streams_upload; the stream itself kept, as a
  // decode under way still holds it: it does nothing more)
}

int32_t mb_host_h264_here(void) { return 0; }

// (no H.264 here, so nothing for the framework to drive: @hostapi.stream_feeds)
int32_t mb_host_stream_feeds(void) { return 0; }
void mb_host_stream_codec(int32_t id, moonbit_string_t cmd, moonbit_bytes_t data) { (void)id, (void)cmd, (void)data; }

// The texture a stream's instances are drawn with (the GL context current): the frame shown last, made its texture
// here the first time it is drawn; 0 before one is shown.
unsigned mb_stream_tex(int id) {
  Stream *s = stream_of(id);
  if (!s) return 0;
  if (s->shown && s->shown->px) {
    Frame *f = s->shown;
    // (on the images' unit, which the renderer binds this texture to next: the atlases' stay bound on theirs)
    glActiveTexture(GL_TEXTURE1);
    if (!s->tex) {
      glGenTextures(1, &s->tex);
      glBindTexture(GL_TEXTURE_2D, s->tex);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    } else {
      glBindTexture(GL_TEXTURE_2D, s->tex);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (f->w == s->tex_w && f->h == s->tex_h) {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, f->w, f->h, GL_RGBA, GL_UNSIGNED_BYTE, f->px);
    } else {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, f->w, f->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, f->px);
      s->tex_w = f->w, s->tex_h = f->h;
    }
    // (its pixels are the texture's now; the frame kept for its size, to be made again in a new context)
    g_free(f->px);
    f->px = NULL;
  }
  return s->tex;
}

// As a frame begins (the GL context current): the textures of the streams closed since let go.
void mb_streams_upload(void) {
  for (guint i = 1; streams && i < streams->len; i++) {
    Stream *s = g_ptr_array_index(streams, i);
    if (s->closed && s->tex) {
      glDeleteTextures(1, &s->tex);
      s->tex = 0;
    }
  }
}

// A new context: the old one's textures gone with it (a stream's picture comes again with its next frame shown).
void mb_streams_lost(void) {
  for (guint i = 1; streams && i < streams->len; i++) {
    Stream *s = g_ptr_array_index(streams, i);
    s->tex = 0;
    s->tex_w = s->tex_h = 0;
  }
}
