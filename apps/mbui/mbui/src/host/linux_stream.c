// Streams on Linux (src/hostapi/stream.mbt, @ui's Stream): JPEG frames decoded by gdk-pixbuf on a thread of a small
// pool, a stream's one after another in the order they came; H.264 by GStreamer (linux_gst.h: where it is, with a
// decoder of H.264, h264_here is true), a live pipeline of the stream's own from its config (appsrc ! decodebin, the
// system's best decoder, VA-API's where it has one, else gst-libav's, which takes a live stream on slice threads,
// holding no frame back; then RGBA). Each frame decoded is kept as pixels until the app shows it ("f TS W H", then
// mb_host_stream_show) or a later one; one that does not decode, or that its decoder passed over, is let go ("d TS");
// the decoder failing says "b" and starts anew from the next key frame. The one shown becomes the stream's texture as
// the renderer first draws it (mb_stream_tex, in the GL context), so it is drawn in the frame that showed it. Each
// event asks for a frame (mb_app_wake). As Windows' win_stream.cpp has its JPEG.
#include <epoxy/gl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <glib.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "linux.h"

#define vlog(...) (fprintf(stdout, __VA_ARGS__), fputc('\n', stdout), fflush(stdout))
#include "linux_gst.h"

typedef struct {
  double ts;
  int w, h;
  uint8_t *px;  // RGBA, w × h (opaque: a JPEG's)
} Frame;

// A stream's H.264 decoder (its config's: started anew with each, and as it fails): its pipeline, its source, its bus;
// the config's caps (avcC as codec_data, an access unit a buffer); whether it waits for a key frame; each frame's time
// in it a count (`next`, ms), and those fed it not out of it yet, oldest first, by it (under lock)
typedef struct {
  void *pipe, *src, *bus;
  char *caps;
  int need_key;
  guint64 next;
  GQueue fed;
} Decoder;

typedef struct {
  guint64 n;
  double ts;
} Fed;

typedef struct {
  int id, closed, busy;
  Decoder *dec;
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

// ---- H.264 (GStreamer's) ----

// whether GStreamer is here with a decoder of H.264 (0 not looked for, 1 here, -1 not)
static int h264_state;

static int h264_decodes(void) {
  if (h264_state) return h264_state > 0;
  h264_state = -1;
  if (!gs_here()) return 0;
  GList *all = gs.gst_element_factory_list_get_elements(GFACTORY_DECODER | GFACTORY_VIDEO, GRANK_MARGINAL);
  void *caps = gs.gst_caps_from_string("video/x-h264");
  GList *ok = caps ? gs.gst_element_factory_list_filter(all, caps, GPAD_SINK, FALSE) : NULL;
  if (ok) h264_state = 1;
  else vlog("streams: GStreamer has no decoder of H.264 (gst-libav's, VA-API's): JPEG only");
  gs.gst_plugin_feature_list_free(ok);
  gs.gst_plugin_feature_list_free(all);
  if (caps) gs.gst_mini_object_unref(caps);
  return h264_state > 0;
}

// (under lock) the frames fed it up to `n` (all: -1) let go, said as one "d" of the last one's time
static void fed_let_go(Stream *s, guint64 n) {
  Fed *last = NULL, *f;
  while ((f = g_queue_peek_head(&s->dec->fed)) && f->n <= n) {
    g_free(last);
    last = g_queue_pop_head(&s->dec->fed);
  }
  if (last) {
    char *t = stamp(last->ts);
    say_locked(s, g_strdup_printf("d %s", t));
    g_free(t);
    g_free(last);
  }
}

// a frame decoded (a streaming thread's): it kept and said, those fed before it and not out passed over
static int on_decoded(void *sink, gpointer data) {
  Stream *s = data;
  void *sample = NULL;
  g_signal_emit_by_name(sink, "pull-sample", &sample);
  if (!sample) return 0;
  GstBufferHead *b = gs.gst_sample_get_buffer(sample);
  void *caps = gs.gst_sample_get_caps(sample), *st = caps ? gs.gst_caps_get_structure(caps, 0) : NULL;
  int w = 0, h = 0;
  if (st) gs.gst_structure_get_int(st, "width", &w), gs.gst_structure_get_int(st, "height", &h);
  uint8_t *px = NULL;
  if (b && w > 0 && h > 0 && gs.gst_buffer_get_size(b) >= (gsize)w * h * 4) {
    px = g_malloc((size_t)w * h * 4);
    gs.gst_buffer_extract(b, 0, px, (gsize)w * h * 4);
  }
  guint64 n = b && b->pts != GCLOCK_NONE ? b->pts / 1000000 : 0;
  gs.gst_mini_object_unref(sample);
  g_mutex_lock(&lock);
  Fed *f = NULL;
  if (s->dec && !s->closed) {
    if (n > 0) fed_let_go(s, n - 1);
    f = g_queue_peek_head(&s->dec->fed);
    if (f && f->n == n) g_queue_pop_head(&s->dec->fed);
    else f = NULL;
  }
  if (f && px) {
    Frame *fr = g_new0(Frame, 1);
    fr->ts = f->ts, fr->w = w, fr->h = h, fr->px = px;
    g_queue_push_tail(&s->decoded, fr);
    char *t = stamp(f->ts);
    say_locked(s, g_strdup_printf("f %s %d %d", t, w, h));
    g_free(t);
    px = NULL;
  } else if (f) {
    char *t = stamp(f->ts);
    say_locked(s, g_strdup_printf("d %s", t));
    g_free(t);
  }
  g_mutex_unlock(&lock);
  g_free(f);
  g_free(px);
  mb_app_wake();
  return 0;
}

static void decoder_start(Stream *s);

// the decoder let go of (its streams stopped: none of its callbacks after), the frames in it said let go
static void decoder_stop(Stream *s) {
  Decoder *d = s->dec;
  if (!d->pipe) return;
  g_signal_handlers_disconnect_matched(d->bus, G_SIGNAL_MATCH_DATA, 0, 0, NULL, NULL, GINT_TO_POINTER(s->id));
  gs.gst_bus_remove_signal_watch(d->bus);
  gs.gst_object_unref(d->bus);
  gs.gst_element_set_state(d->pipe, GSTATE_NULL);
  gs.gst_object_unref(d->src);
  gs.gst_object_unref(d->pipe);
  d->pipe = d->src = d->bus = NULL;
  g_mutex_lock(&lock);
  fed_let_go(s, (guint64)-1);
  g_mutex_unlock(&lock);
  mb_app_wake();
}

// it failed (its bus's word, on the main thread): said, and anew from the next key frame
static void on_decoder_error(void *bus, void *msg, gpointer data) {
  (void)bus;
  Stream *s = stream_of(GPOINTER_TO_INT(data));
  if (!s || !s->dec || s->closed) return;
  GError *e = NULL;
  char *dbg = NULL;
  gs.gst_message_parse_error(msg, &e, &dbg);
  vlog("stream %d: its decoder failed: %s", s->id, e ? e->message : "?");
  g_clear_error(&e);
  g_free(dbg);
  decoder_stop(s);
  g_mutex_lock(&lock);
  say_locked(s, g_strdup("b"));
  g_mutex_unlock(&lock);
  decoder_start(s);
}

static void decoder_start(Stream *s) {
  Decoder *d = s->dec;
  d->need_key = 1;
  GError *e = NULL;
  void *pipe = gs.gst_parse_launch(
      "appsrc name=in is-live=true format=time ! decodebin ! videoconvert ! video/x-raw,format=RGBA ! "
      "appsink name=out sync=false emit-signals=true",
      &e);
  void *src = pipe ? gs.gst_bin_get_by_name(pipe, "in") : NULL, *sink = pipe ? gs.gst_bin_get_by_name(pipe, "out") : NULL;
  void *caps = gs.gst_caps_from_string(d->caps);
  if (!src || !sink || !caps) {
    vlog("stream %d: no decoder (%s)", s->id, e ? e->message : "its config's caps");
    g_clear_error(&e);
    if (src) gs.gst_object_unref(src);
    if (sink) gs.gst_object_unref(sink);
    if (pipe) gs.gst_object_unref(pipe);
    if (caps) gs.gst_mini_object_unref(caps);
    return;
  }
  g_clear_error(&e);
  g_object_set(src, "caps", caps, NULL);
  gs.gst_mini_object_unref(caps);
  g_signal_connect(sink, "new-sample", G_CALLBACK(on_decoded), s);
  gs.gst_object_unref(sink);
  d->pipe = pipe, d->src = src;
  d->bus = gs.gst_element_get_bus(pipe);
  gs.gst_bus_add_signal_watch(d->bus);
  g_signal_connect(d->bus, "message::error", G_CALLBACK(on_decoder_error), GINT_TO_POINTER(s->id));
  gs.gst_element_set_state(pipe, GSTATE_PLAYING);
}

void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  Stream *s = stream_of(id);
  if (!s || s->closed || !h264_decodes()) return;
  if (!s->dec) {
    s->dec = g_new0(Decoder, 1);
    g_queue_init(&s->dec->fed);
  }
  decoder_stop(s);
  // (its avcC as the caps' codec_data, a buffer written as hex)
  int32_t n = Moonbit_array_length(avcc);
  GString *c = g_string_new("video/x-h264,stream-format=avc,alignment=au,codec_data=(buffer)");
  for (int32_t i = 0; i < n; i++) g_string_append_printf(c, "%02x", avcc[i]);
  g_string_append_printf(c, ",width=%d,height=%d", w, h);
  g_free(s->dec->caps);
  s->dec->caps = g_string_free(c, FALSE);
  decoder_start(s);
}

void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  Stream *s = stream_of(id);
  if (!s || s->closed) return;
  Decoder *d = s->dec;
  if (!d || !d->pipe || (d->need_key && !key)) {
    say_dropped(s, ts);
    return;
  }
  d->need_key = 0;
  GstBufferHead *b = gs.gst_buffer_new_memdup(data, (gsize)Moonbit_array_length(data));
  b->pts = ++d->next * 1000000;
  Fed *f = g_new(Fed, 1);
  f->n = d->next, f->ts = ts;
  g_mutex_lock(&lock);
  g_queue_push_tail(&d->fed, f);
  g_mutex_unlock(&lock);
  int flow = 0;
  g_signal_emit_by_name(d->src, "push-buffer", b, &flow);
  gs.gst_mini_object_unref(b);
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
  if (s->dec) {
    decoder_stop(s);
    g_mutex_lock(&lock);
    g_queue_clear_full(&s->dec->fed, g_free);
    g_mutex_unlock(&lock);
    g_free(s->dec->caps);
    g_clear_pointer(&s->dec, g_free);
  }
  // (its texture let go as the next frame begins, in the GL context: mb_streams_upload; the stream itself kept, as a
  // decode under way still holds it: it does nothing more)
}

int32_t mb_host_h264_here(void) { return h264_decodes(); }

// (its H.264 decoded here, nothing for the framework to drive: @hostapi.stream_feeds)
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

int32_t mb_host_stream_audio_here(void) { return 0; }
void mb_host_stream_audio(int32_t id, moonbit_bytes_t data) { (void)id; (void)data; }

// H.265 not decoded here (a remote screen asks H.264): apple_stream.m's is the one that does.
int32_t mb_host_h265_here(void) { return 0; }
void mb_host_stream_hevc(int32_t id, moonbit_bytes_t hvcc, int32_t w, int32_t h) { (void)id; (void)hvcc; (void)w; (void)h; }
