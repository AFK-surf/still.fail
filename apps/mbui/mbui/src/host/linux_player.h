// A video (and audio) player on Linux (host_native.mbt's view_*, kind 1): GStreamer's playbin, the system's own, loaded
// as the first one opens (libgstreamer-1.0.so.0: nothing of it linked, so the app starts where it is not installed;
// there view_open answers 0 and the app says it cannot play it). Its bytes come only through the app, as Apple's and
// Android's do: its source is an appsrc in seekable mode, a stream of the file's bytes from where it is (as HTTP's is),
// read from the app 256 KB at a time while the source wants more (view_read_next, view_read_answer); one it seeks away
// from is let go, the next begun from there as it next wants bytes. Its pictures come out as RGBA (an appsink after
// videoconvert) and are drawn in the canvas, as Android's are: its newest frame the view's picture (MB_VIEW_TEX + its
// id: mb_player_tex), a texture made from it as the renderer first draws it, so a player moves with a list in step with
// what is around it and what is painted after it draws over it. Its sound goes to the system's (playbin's own sink).
// Played, paused, sought (to the frame, or to the nearest key frame at once), at a rate, at a volume, muted while it is
// scrubbed; buffering while it is to play and waits on the app's bytes; its frame shown grabbed as a JPEG (grab_shown);
// a frame of its file at a time grabbed as a PNG (grab_frame) by a playbin of its own, paused there, its bytes read
// through the app as the player's are (a second stream of reads of the same view, as Apple's image generator and
// Windows' second <video> read theirs); its frames' times read from its file (frames()) by a parsebin of its own over
// a third such stream, nothing decoded, as Android's MediaExtractor and Apple's sample cursor read theirs.
//
// Threads: GStreamer's streaming threads ask for bytes (need-data, seek-data) and hand frames over (new-sample), under
// the player's lock; everything else, its buses' messages among them, on the main thread. The app's bytes go into a
// source under the lock too: a seek, which lets go of the read under way, comes before a read's bytes or after them,
// never between deciding they are the stream's next and handing them over. Included by linux_views.c (its next_vid,
// vlog, told, grabs); GStreamer as linux_gst.h loads it.

#include "linux_gst.h"

// One read of a source's, the app answering it as its bytes come.
typedef struct {
  int rid;
  gint64 offset, length;
  int asked;  // given to the app (view_read_next)
} PlayRead;

struct Player;

// A stream of the file's bytes into an appsrc (the player's, a grab's), all of it under its player's lock but `wants`:
// its appsrc once made (source-setup), where it is, the read the app answers now (none: NULL), its end pushed; whether
// it wants more (atomic: enough-data is said from within a push, the lock held)
typedef struct {
  struct Player *p;
  void *src;
  gint64 at;
  PlayRead *read;
  int ended;
  gint wants;
} Source;

// A frame of its file grabbed: a playbin of its own (its video alone), paused at `ms` (once it has its first frame,
// sought there), its frame there the appsink's last
typedef struct {
  void *bin, *sink, *bus;
  Source in;
  double ms;
  int sought;
} Grab;

// Its frames' times read: a parsebin of its file's bytes (appsrc ! parsebin), its first video stream's buffers' times
// (in its stream's time, as the player seeks: its segment's) gathered as fast as they come, its other streams let go
// (fakesinks); once at its end, said
typedef struct {
  void *pipe, *bus;
  Source in;
  int video;     // its video stream taken (one only)
  GArray *times;  // (under the player's lock) ns
} Scan;

typedef struct Player {
  int vid;
  void *bin;   // playbin
  void *sink;  // the appsink of its pictures
  void *bus;
  GMutex lock;
  Source in;
  Grab *grab;  // the frame of its file being grabbed (grab_frame), if one is
  Scan *scan;  // its frames' times being read, if they are
  char *frames;  // its frames' times once read ("ms,ms,…" in time order; "" none to read), else NULL
  // (under lock) its sources' reads' ids, those let go for the app to be told of (minus their ids), how many bytes it
  // was given, the file's size (-1 not known)
  int next_read;
  GQueue gone;
  double given, total;
  // (under lock) the newest frame: its pixels (RGBA), its size, whether it is new since its texture was made
  uint8_t *px;
  int w, h, fresh, drawn;
  // the main thread's
  int state;  // -1 failed, 0 opening, 1 ready
  int playing, ended, scrubbing;
  gint64 last_t;  // its position as it was last looked at (buffering: info)
  int waiting;    // buffering, as it was last looked at
  // how it stands (player_info) as it was last looked at, and whether that was ever (player_stood)
  double stood[10];
  int stood_state, stood_told;
  double volume, rate;
  GLuint tex;
  int tex_w, tex_h;
  // its frame grabbed (grab_shown's JPEG, grab_frame's PNG; still_state 1 grabbing, 2 here, -1 failed)
  GBytes *still;
  int still_state;
  struct Player *next;
} Player;

static Player *players;
static GArray *gone_texs;  // the textures of players closed, deleted as the next frame begins (the GL context current)

static Player *player_of(int vid) {
  for (Player *p = players; p; p = p->next)
    if (p->vid == vid) return p;
  return NULL;
}

// (under lock) a source's read let go of: the app told to stop it
static void source_let_go(Source *s) {
  if (!s->read) return;
  g_queue_push_tail(&s->p->gone, GINT_TO_POINTER(s->read->rid));
  g_clear_pointer(&s->read, g_free);
  mb_app_wake();
}

// (under lock) a source's next bytes: a read of the app's asked for from where it is, unless one is under way; at the
// file's end, its end
static void source_want(Source *s) {
  Player *p = s->p;
  if (s->read || s->ended || !s->src) return;
  if (p->total >= 0 && s->at >= p->total) {
    s->ended = 1;
    int flow = 0;
    g_signal_emit_by_name(s->src, "end-of-stream", &flow);
    return;
  }
  s->read = g_new0(PlayRead, 1);
  s->read->rid = ++p->next_read;
  s->read->offset = s->at;
  s->read->length = 256 * 1024;
  mb_app_wake();
}

// the source wants bytes (a streaming thread's)
static void on_need(void *src, guint length, gpointer data) {
  (void)src, (void)length;
  Source *s = data;
  g_atomic_int_set(&s->wants, 1);
  g_mutex_lock(&s->p->lock);
  source_want(s);
  g_mutex_unlock(&s->p->lock);
}

static void on_enough(void *src, gpointer data) {
  (void)src;
  g_atomic_int_set(&((Source *)data)->wants, 0);
}

// the source goes to `offset` (a seek): the read under way let go, the next begun from there as it next wants bytes
// (once the seek has flushed what it had: anything pushed before then would go with it)
static gboolean on_seek_data(void *src, guint64 offset, gpointer data) {
  (void)src;
  Source *s = data;
  g_mutex_lock(&s->p->lock);
  source_let_go(s);
  s->at = (gint64)offset;
  s->ended = 0;
  g_mutex_unlock(&s->p->lock);
  return TRUE;
}

static void on_source(void *bin, void *src, gpointer data) {
  (void)bin;
  Source *s = data;
  g_object_set(src, "stream-type", GAPP_SEEKABLE, "format", 2 /* bytes */, NULL);
  g_signal_connect(src, "need-data", G_CALLBACK(on_need), s);
  g_signal_connect(src, "enough-data", G_CALLBACK(on_enough), s);
  g_signal_connect(src, "seek-data", G_CALLBACK(on_seek_data), s);
  g_mutex_lock(&s->p->lock);
  s->src = src;
  if (s->p->total >= 0) g_object_set(src, "size", (gint64)s->p->total, NULL);
  g_mutex_unlock(&s->p->lock);
}

// a sample's picture (RGBA), copied out, and its size; NULL where it has none
static uint8_t *sample_pixels(void *sample, int *w, int *h) {
  void *buf = gs.gst_sample_get_buffer(sample), *caps = gs.gst_sample_get_caps(sample);
  void *st = caps ? gs.gst_caps_get_structure(caps, 0) : NULL;
  *w = *h = 0;
  if (st) gs.gst_structure_get_int(st, "width", w), gs.gst_structure_get_int(st, "height", h);
  if (*w <= 0 || *h <= 0 || !buf || gs.gst_buffer_get_size(buf) < (gsize)*w * *h * 4) return NULL;
  uint8_t *px = g_malloc((size_t)*w * *h * 4);
  gs.gst_buffer_extract(buf, 0, px, (gsize)*w * *h * 4);
  return px;
}

// a frame for the canvas (a streaming thread's): its pixels kept as the newest
static int take_sample(Player *p, void *sample) {
  if (!sample) return 0;
  int w, h;
  uint8_t *px = sample_pixels(sample, &w, &h);
  if (px) {
    g_mutex_lock(&p->lock);
    g_free(p->px);
    p->px = px, p->w = w, p->h = h, p->fresh = 1;
    g_mutex_unlock(&p->lock);
    mb_app_wake();
  }
  gs.gst_mini_object_unref(sample);
  return 0;
}

static int on_sample(void *sink, gpointer data) {
  void *sample = NULL;
  g_signal_emit_by_name(sink, "pull-sample", &sample);
  return take_sample(data, sample);
}

static int on_preroll(void *sink, gpointer data) {
  void *sample = NULL;
  g_signal_emit_by_name(sink, "pull-preroll", &sample);
  return take_sample(data, sample);
}

// Its state for the app (host_native.mbt's set_outside, kind 2): 1 ready (its first frame decoded), -1 failed, told
// between frames (mb_views_tell), as a page's is.
static void player_tell(Player *p, int state) {
  p->state = state;
  g_queue_push_tail(&told, GINT_TO_POINTER(p->vid));
  g_queue_push_tail(&told, GINT_TO_POINTER(state));
  vlog("view %d: told %d", p->vid, state);
  mb_host_request_frame();
}

// A grab of its frame done (`still`: the picture, taken; NULL none), told between frames (mb_views_tell) as a page's
// is.
static void player_grabbed(Player *p, GBytes *still) {
  g_clear_pointer(&p->still, g_bytes_unref);
  p->still = still;
  p->still_state = still ? 2 : -1;
  g_queue_push_tail(&grabs, GINT_TO_POINTER(p->vid));
  g_queue_push_tail(&grabs, GINT_TO_POINTER(still ? 1 : -1));
  mb_host_request_frame();
}

static void on_error(void *bus, void *msg, gpointer data) {
  (void)bus;
  Player *p = player_of(GPOINTER_TO_INT(data));
  if (!p) return;
  GError *e = NULL;
  char *dbg = NULL;
  gs.gst_message_parse_error(msg, &e, &dbg);
  vlog("view %d: cannot be played: %s (%s)", p->vid, e ? e->message : "?", dbg ? dbg : "");
  g_clear_error(&e);
  g_free(dbg);
  if (p->state >= 0) player_tell(p, -1);
}

static void on_ready(void *bus, void *msg, gpointer data) {
  (void)bus, (void)msg;
  Player *p = player_of(GPOINTER_TO_INT(data));
  if (p && p->state == 0) {
    vlog("view %d: player ready", p->vid);
    player_tell(p, 1);
  }
  mb_app_wake();
}

static void on_eos(void *bus, void *msg, gpointer data) {
  (void)bus, (void)msg;
  Player *p = player_of(GPOINTER_TO_INT(data));
  if (!p) return;
  p->ended = 1;
  p->playing = 0;
  mb_app_wake();
}

// A playbin of the app's bytes: `video` its video's sink, its source `in`, its bus's errors and async-dones to
// `on_err` and `on_done` (by the view's id).
static void *play_bin(Player *p, void *video, Source *in, void **bus, GCallback on_err, GCallback on_done) {
  void *bin = gs.gst_element_factory_make("playbin", NULL);
  if (!bin) return NULL;
  in->p = p;
  g_object_set(bin, "uri", "appsrc://", "video-sink", video, NULL);
  g_signal_connect(bin, "source-setup", G_CALLBACK(on_source), in);
  *bus = gs.gst_element_get_bus(bin);
  gs.gst_bus_add_signal_watch(*bus);
  gpointer id = GINT_TO_POINTER(p->vid);
  g_signal_connect(*bus, "message::error", on_err, id);
  g_signal_connect(*bus, "message::async-done", on_done, id);
  return bin;
}

// A pipeline (a playbin, a scan's) and its bus let go of (its streams stopped: none of its callbacks after), its
// source's read let go.
static void pipe_end(Player *p, void *bin, void *bus, Source *in) {
  g_signal_handlers_disconnect_matched(bus, G_SIGNAL_MATCH_DATA, 0, 0, NULL, NULL, GINT_TO_POINTER(p->vid));
  gs.gst_bus_remove_signal_watch(bus);
  gs.gst_object_unref(bus);
  gs.gst_element_set_state(bin, GSTATE_NULL);
  gs.gst_object_unref(bin);
  g_mutex_lock(&p->lock);
  source_let_go(in);
  g_mutex_unlock(&p->lock);
}

// ---- a frame of its file grabbed (grab_frame) ----

static void grab_end(Player *p) {
  Grab *g = p->grab;
  if (!g) return;
  p->grab = NULL;
  pipe_end(p, g->bin, g->bus, &g->in);
  gs.gst_object_unref(g->sink);
  g_free(g);
}

static void on_grab_error(void *bus, void *msg, gpointer data) {
  (void)bus;
  Player *p = player_of(GPOINTER_TO_INT(data));
  if (!p || !p->grab) return;
  GError *e = NULL;
  char *dbg = NULL;
  gs.gst_message_parse_error(msg, &e, &dbg);
  vlog("view %d: no frame grabbed: %s", p->vid, e ? e->message : "?");
  g_clear_error(&e);
  g_free(dbg);
  grab_end(p);
  player_grabbed(p, NULL);
}

// paused with a frame: at its start, sought to `ms` (accurately: the frame showing then); there, that frame as a PNG
static void on_grab_done(void *bus, void *msg, gpointer data) {
  (void)bus, (void)msg;
  Player *p = player_of(GPOINTER_TO_INT(data));
  Grab *g = p ? p->grab : NULL;
  if (!g) return;
  // (a seek it cannot make: its first frame the one there is)
  if (!g->sought && g->ms > 0) {
    g->sought = 1;
    if (gs.gst_element_seek(g->bin, 1, GFORMAT_TIME, GSEEK_FLUSH | GSEEK_ACCURATE, GSEEK_TYPE_SET,
                            (gint64)(g->ms * 1e6), GSEEK_TYPE_NONE, -1))
      return;
  }
  void *sample = NULL;
  g_object_get(g->sink, "last-sample", &sample, NULL);
  GBytes *png = NULL;
  int w, h;
  uint8_t *px = sample ? sample_pixels(sample, &w, &h) : NULL;
  if (px) {
    GdkPixbuf *pb =
        gdk_pixbuf_new_from_data(px, GDK_COLORSPACE_RGB, TRUE, 8, w, h, w * 4, (GdkPixbufDestroyNotify)g_free, NULL);
    char *out = NULL;
    gsize n = 0;
    if (gdk_pixbuf_save_to_buffer(pb, &out, &n, "png", NULL, NULL)) png = g_bytes_new_take(out, n);
    g_object_unref(pb);
  }
  if (sample) gs.gst_mini_object_unref(sample);
  grab_end(p);
  player_grabbed(p, png);
}

// Its file's frame showing at `ms`, grabbed whole at its own size (one at a time: one asked before the last is done
// takes its place).
static void player_grab_frame(Player *p, double ms) {
  grab_end(p);
  g_clear_pointer(&p->still, g_bytes_unref);
  p->still_state = 1;
  GError *e = NULL;
  void *video = gs.gst_parse_bin_from_description("videoconvert ! video/x-raw,format=RGBA ! appsink name=frame", TRUE, &e);
  g_clear_error(&e);
  Grab *g = g_new0(Grab, 1);
  g->ms = ms;
  g->bin = video ? play_bin(p, video, &g->in, &g->bus, G_CALLBACK(on_grab_error), G_CALLBACK(on_grab_done)) : NULL;
  if (!g->bin) {
    if (video) gs.gst_object_unref(video);
    g_free(g);
    player_grabbed(p, NULL);
    return;
  }
  g->sink = gs.gst_bin_get_by_name(video, "frame");
  g_object_set(g->bin, "flags", GPLAY_VIDEO, NULL);
  p->grab = g;
  gs.gst_element_set_state(g->bin, GSTATE_PAUSED);
}

// ---- its frames' times read (frames()) ----

static void scan_end(Player *p) {
  Scan *sc = p->scan;
  if (!sc) return;
  p->scan = NULL;
  pipe_end(p, sc->pipe, sc->bus, &sc->in);
  g_array_unref(sc->times);
  g_free(sc);
}

// a buffer of its video stream (a streaming thread's): its time, in its stream's
static int on_scan_sample(void *sink, gpointer data) {
  Player *p = data;
  void *sample = NULL;
  g_signal_emit_by_name(sink, "pull-sample", &sample);
  if (!sample) return 0;
  GstBufferHead *b = gs.gst_sample_get_buffer(sample);
  void *seg = gs.gst_sample_get_segment(sample);
  guint64 t = b ? (b->pts != GCLOCK_NONE ? b->pts : b->dts) : GCLOCK_NONE;
  if (t != GCLOCK_NONE && seg) t = gs.gst_segment_to_stream_time(seg, GFORMAT_TIME, t);
  if (t != GCLOCK_NONE) {
    g_mutex_lock(&p->lock);
    if (p->scan) g_array_append_val(p->scan->times, t);
    g_mutex_unlock(&p->lock);
  }
  gs.gst_mini_object_unref(sample);
  return 0;
}

// a stream of its file (a streaming thread's): the first video one's buffers taken, every other let go
static void on_scan_pad(void *parse, void *pad, gpointer data) {
  (void)parse;
  Player *p = data;
  Scan *sc = p->scan;
  void *caps = gs.gst_pad_get_current_caps(pad);
  void *st = caps ? gs.gst_caps_get_structure(caps, 0) : NULL;
  const char *name = st ? gs.gst_structure_get_name(st) : "";
  int video = g_str_has_prefix(name, "video/") && !g_atomic_int_get(&sc->video);
  if (caps) gs.gst_mini_object_unref(caps);
  void *sink = gs.gst_element_factory_make(video ? "appsink" : "fakesink", NULL);
  if (!sink) return;
  if (video) {
    g_atomic_int_set(&sc->video, 1);
    g_object_set(sink, "emit-signals", TRUE, NULL);
    g_signal_connect(sink, "new-sample", G_CALLBACK(on_scan_sample), p);
  }
  g_object_set(sink, "sync", FALSE, NULL);
  gs.gst_bin_add(sc->pipe, sink);
  gs.gst_element_sync_state_with_parent(sink);
  void *in = gs.gst_element_get_static_pad(sink, "sink");
  gs.gst_pad_link(pad, in);
  gs.gst_object_unref(in);
}

static gint by_time(gconstpointer a, gconstpointer b) {
  guint64 x = *(const guint64 *)a, y = *(const guint64 *)b;
  return x < y ? -1 : x > y;
}

// at its end (or failed: none read), its times said, in time order
static void scan_said(Player *p, int failed) {
  Scan *sc = p->scan;
  GString *out = g_string_new(NULL);
  g_mutex_lock(&p->lock);
  if (!failed) {
    g_array_sort(sc->times, by_time);
    char n[G_ASCII_DTOSTR_BUF_SIZE];
    for (guint i = 0; i < sc->times->len; i++) {
      if (i) g_string_append_c(out, ',');
      g_string_append(out, g_ascii_formatd(n, sizeof n, "%.3f", g_array_index(sc->times, guint64, i) / 1e6));
    }
  }
  g_mutex_unlock(&p->lock);
  vlog("view %d: %u frames' times read", p->vid, failed ? 0 : sc->times->len);
  scan_end(p);
  g_free(p->frames);
  p->frames = g_string_free(out, FALSE);
  mb_app_wake();
}

static void on_scan_eos(void *bus, void *msg, gpointer data) {
  (void)bus, (void)msg;
  Player *p = player_of(GPOINTER_TO_INT(data));
  if (p && p->scan) scan_said(p, 0);
}

static void on_scan_error(void *bus, void *msg, gpointer data) {
  (void)bus;
  Player *p = player_of(GPOINTER_TO_INT(data));
  if (!p || !p->scan) return;
  GError *e = NULL;
  char *dbg = NULL;
  gs.gst_message_parse_error(msg, &e, &dbg);
  vlog("view %d: its frames' times not read: %s", p->vid, e ? e->message : "?");
  g_clear_error(&e);
  g_free(dbg);
  scan_said(p, 1);
}

// its frames' times asked for (once: what is read is kept)
static void player_frames(Player *p) {
  if (p->frames || p->scan) return;
  GError *e = NULL;
  void *pipe = gs.gst_parse_launch("appsrc name=src ! parsebin name=parse", &e);
  g_clear_error(&e);
  void *src = pipe ? gs.gst_bin_get_by_name(pipe, "src") : NULL;
  void *parse = pipe ? gs.gst_bin_get_by_name(pipe, "parse") : NULL;
  if (!src || !parse) {
    vlog("view %d: its frames' times not read: no parsebin", p->vid);
    if (src) gs.gst_object_unref(src);
    if (parse) gs.gst_object_unref(parse);
    if (pipe) gs.gst_object_unref(pipe);
    p->frames = g_strdup("");
    mb_app_wake();
    return;
  }
  Scan *sc = g_new0(Scan, 1);
  sc->pipe = pipe;
  sc->times = g_array_new(FALSE, FALSE, sizeof(guint64));
  sc->in.p = p;
  p->scan = sc;
  on_source(NULL, src, &sc->in);
  g_signal_connect(parse, "pad-added", G_CALLBACK(on_scan_pad), p);
  gs.gst_object_unref(src);
  gs.gst_object_unref(parse);
  sc->bus = gs.gst_element_get_bus(pipe);
  gs.gst_bus_add_signal_watch(sc->bus);
  gpointer id = GINT_TO_POINTER(p->vid);
  g_signal_connect(sc->bus, "message::error", G_CALLBACK(on_scan_error), id);
  g_signal_connect(sc->bus, "message::eos", G_CALLBACK(on_scan_eos), id);
  gs.gst_element_set_state(pipe, GSTATE_PLAYING);
}

// ---- the player ----

static int player_open(moonbit_string_t type) {
  (void)type;
  if (!gs_here()) return 0;
  GError *e = NULL;
  void *video = gs.gst_parse_bin_from_description(
      "videoconvert ! video/x-raw,format=RGBA ! appsink name=pictures emit-signals=true max-buffers=2", TRUE, &e);
  if (!video) {
    vlog("view: no player (%s): videoconvert or appsink missing", e ? e->message : "?");
    g_clear_error(&e);
    return 0;
  }
  Player *p = g_new0(Player, 1);
  p->vid = next_vid + 1;
  p->bin = play_bin(p, video, &p->in, &p->bus, G_CALLBACK(on_error), G_CALLBACK(on_ready));
  if (!p->bin) {
    vlog("view: no player: playbin missing");
    gs.gst_object_unref(video);
    g_free(p);
    return 0;
  }
  next_vid = p->vid;
  if (!gone_texs) gone_texs = g_array_new(FALSE, FALSE, sizeof(GLuint));
  p->total = -1;
  p->volume = 1;
  p->rate = 1;
  g_mutex_init(&p->lock);
  g_queue_init(&p->gone);
  p->sink = gs.gst_bin_get_by_name(video, "pictures");
  g_signal_connect(p->sink, "new-sample", G_CALLBACK(on_sample), p);
  g_signal_connect(p->sink, "new-preroll", G_CALLBACK(on_preroll), p);
  g_signal_connect(p->bus, "message::eos", G_CALLBACK(on_eos), GINT_TO_POINTER(p->vid));
  p->next = players;
  players = p;
  // (its first frame drawn, paused until played)
  gs.gst_element_set_state(p->bin, GSTATE_PAUSED);
  vlog("view %d: open player", p->vid);
  return p->vid;
}

static void player_close(Player *p) {
  Player **at = &players;
  while (*at && *at != p) at = &(*at)->next;
  if (*at) *at = p->next;
  grab_end(p);
  scan_end(p);
  pipe_end(p, p->bin, p->bus, &p->in);
  g_free(p->frames);
  gs.gst_object_unref(p->sink);
  g_queue_clear(&p->gone);
  g_free(p->px);
  g_clear_pointer(&p->still, g_bytes_unref);
  if (p->tex) g_array_append_val(gone_texs, p->tex);
  g_mutex_clear(&p->lock);
  vlog("view %d: closed", p->vid);
  g_free(p);
}

static gint64 player_position(Player *p) {
  gint64 t = -1;
  return gs.gst_element_query_position(p->bin, GFORMAT_TIME, &t) ? t : -1;
}

static void player_seek(Player *p, double ms, int flags, double rate) {
  gint64 t = ms >= 0 ? (gint64)(ms * 1e6) : player_position(p);
  if (t < 0) t = 0;
  p->ended = 0;
  gs.gst_element_seek(p->bin, rate, GFORMAT_TIME, GSEEK_FLUSH | flags, GSEEK_TYPE_SET, t, GSEEK_TYPE_NONE, -1);
}

// its frame shown, at most `side` pixels on its longer side, as a JPEG
static void player_grab(Player *p, double side) {
  g_mutex_lock(&p->lock);
  GdkPixbuf *pb = p->px ? gdk_pixbuf_new_from_data(g_memdup2(p->px, (gsize)p->w * p->h * 4), GDK_COLORSPACE_RGB, TRUE,
                                                   8, p->w, p->h, p->w * 4, (GdkPixbufDestroyNotify)g_free, NULL)
                        : NULL;
  g_mutex_unlock(&p->lock);
  GBytes *still = NULL;
  if (pb) {
    int w = gdk_pixbuf_get_width(pb), h = gdk_pixbuf_get_height(pb);
    double k = side > 0 ? fmin(1, side / fmax(w, h)) : 1;
    GdkPixbuf *small = gdk_pixbuf_scale_simple(pb, MAX(1, (int)round(w * k)), MAX(1, (int)round(h * k)),
                                               GDK_INTERP_BILINEAR);
    // (a JPEG has no alpha: the frame's, opaque, dropped)
    GdkPixbuf *rgb = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, gdk_pixbuf_get_width(small),
                                    gdk_pixbuf_get_height(small));
    gdk_pixbuf_composite_color(small, rgb, 0, 0, gdk_pixbuf_get_width(small), gdk_pixbuf_get_height(small), 0, 0, 1, 1,
                               GDK_INTERP_NEAREST, 255, 0, 0, 1, 0, 0);
    char *jpeg = NULL;
    gsize n = 0;
    if (gdk_pixbuf_save_to_buffer(rgb, &jpeg, &n, "jpeg", NULL, "quality", "85", NULL)) still = g_bytes_new_take(jpeg, n);
    g_object_unref(rgb);
    g_object_unref(small);
    g_object_unref(pb);
  }
  player_grabbed(p, still);
}

static void player_stood(Player *p);
static void players_ticking(void);

static void player_control(Player *p, int op, double value) {
  switch (op) {
    case 1:
      if (p->ended) player_seek(p, 0, GSEEK_ACCURATE, p->rate);
      p->playing = 1;
      gs.gst_element_set_state(p->bin, GSTATE_PLAYING);
      players_ticking();
      player_stood(p);
      break;
    case 2:
      p->playing = 0;
      gs.gst_element_set_state(p->bin, GSTATE_PAUSED);
      player_stood(p);
      break;
    case 3:
      player_seek(p, value, GSEEK_ACCURATE, p->rate);
      player_stood(p);
      break;
    case 11:
      player_seek(p, value, GSEEK_KEY_UNIT, p->rate);
      player_stood(p);
      break;
    case 4:
      if (value > 0) p->rate = value, player_seek(p, -1, GSEEK_ACCURATE, value);
      break;
    case 9:
      p->scrubbing = value > 0;
      g_object_set(p->bin, "mute", p->scrubbing, NULL);
      break;
    case 10:
      p->volume = fmin(1, fmax(0, value));
      g_object_set(p->bin, "volume", p->volume, NULL);
      break;
    case 20: player_frames(p); break;
    case 21: player_grab_frame(p, value); break;
    case 22:
      grab_end(p);
      player_grab(p, value);
      break;
  }
}

static int player_info(Player *p, double *out) {
  gint64 d = -1, t = player_position(p);
  if (!gs.gst_element_query_duration(p->bin, GFORMAT_TIME, &d)) d = -1;
  out[0] = d >= 0 ? d / 1e6 : -1;
  out[1] = t >= 0 ? t / 1e6 : 0;
  out[2] = p->playing && !p->ended;
  g_mutex_lock(&p->lock);
  out[3] = p->w, out[4] = p->h;
  out[5] = p->given;
  out[6] = p->drawn;
  int reading = p->in.read && p->in.read->asked;
  g_mutex_unlock(&p->lock);
  // buffering, as Apple's and Android's say it: to play, waiting on the app's bytes (a read of them under way) and
  // nothing played since it was last asked (a sink's position goes no further than what it was given; playbin with an
  // appsrc says no buffering of its own)
  out[7] = p->playing && !p->ended && reading && t >= 0 && t == p->last_t;
  p->last_t = t;
  p->waiting = out[7] > 0;
  out[8] = 0;
  out[9] = p->ended;
  return p->state;
}

static GQueue stoods;        // the players whose standing changed, for the app (mb_views_tell)
static guint stood_ticking;  // the tick that looks at the players playing, while one is (players_tick)

// How it stands (player_info) looked at: the app told where it changed, between frames (mb_views_tell: kind 13,
// src/ui/hostcall.mbt's outside_stood), and reads what was looked at then (mb_host_view_info), not each frame. Looked
// at as anything happens (its bus's word, a frame of its picture, a read answered: mb_app_wake's frame), and each frame
// of the display while it plays (players_tick).
static void player_stood(Player *p) {
  double now[10];
  int st = player_info(p, now);
  if (p->stood_told && st == p->stood_state && !memcmp(now, p->stood, sizeof now)) return;
  int queued = p->stood_told && g_queue_find(&stoods, GINT_TO_POINTER(p->vid));
  p->stood_told = 1;
  p->stood_state = st;
  memcpy(p->stood, now, sizeof now);
  if (!queued) g_queue_push_tail(&stoods, GINT_TO_POINTER(p->vid));
  mb_app_wake();
}

// Each frame of the display while a player plays (GTK's frame clock): where it is looked at (a sound has no pictures
// to say so as it goes); stopped once none plays.
static gboolean players_tick(GtkWidget *w, GdkFrameClock *c, gpointer data) {
  (void)w, (void)c, (void)data;
  int any = 0;
  for (Player *p = players; p; p = p->next)
    if (p->playing && !p->ended) any = 1, player_stood(p);
  if (any) return G_SOURCE_CONTINUE;
  stood_ticking = 0;
  return G_SOURCE_REMOVE;
}

static void players_ticking(void) {
  if (!stood_ticking && mb_app_under())
    stood_ticking = gtk_widget_add_tick_callback(GTK_WIDGET(mb_app_under()), players_tick, NULL, NULL);
}

// (under lock) the source whose read the app has not been given yet, or whose read is `rid` (when it is not 0)
static Source *source_of(Player *p, int rid) {
  Source *ss[3] = {&p->in, p->grab ? &p->grab->in : NULL, p->scan ? &p->scan->in : NULL};
  for (int i = 0; i < 3; i++)
    if (ss[i] && ss[i]->read && (rid ? ss[i]->read->rid == rid : !ss[i]->read->asked)) return ss[i];
  return NULL;
}

// the next read the app is to answer, the player's, its grab's or its scan's: its id, from where, how much; minus the id of one let
// go; 0 none
static int player_read_next(Player *p, double *out) {
  int id = 0;
  g_mutex_lock(&p->lock);
  Source *s = source_of(p, 0);
  if (!g_queue_is_empty(&p->gone)) {
    id = -GPOINTER_TO_INT(g_queue_pop_head(&p->gone));
  } else if (s) {
    s->read->asked = 1;
    id = s->read->rid;
    out[0] = (double)s->read->offset;
    out[1] = (double)s->read->length;
  }
  g_mutex_unlock(&p->lock);
  return id;
}

// the app's answer to a read: its bytes the next of the source it is for, the file's size known, its end
static void player_read_answer(Player *p, int rid, moonbit_bytes_t data, double total, int more) {
  int32_t n = Moonbit_array_length(data);
  int failed = total == -2;
  g_mutex_lock(&p->lock);
  Source *s = source_of(p, rid);
  // (whose: 1 the player's, 2 its grab's, 3 its scan's)
  int whose = !s ? 0 : s == &p->in ? 1 : p->grab && s == &p->grab->in ? 2 : 3;
  if (total >= 0 && p->total < 0) {
    p->total = total;
    if (p->in.src) g_object_set(p->in.src, "size", (gint64)total, NULL);
    if (p->grab && p->grab->in.src) g_object_set(p->grab->in.src, "size", (gint64)total, NULL);
  }
  if (s && !failed) {
    if (n > 0 && s->src) {
      void *buf = gs.gst_buffer_new_memdup(data, (gsize)n);
      int flow = 0;
      g_signal_emit_by_name(s->src, "push-buffer", buf, &flow);
      gs.gst_mini_object_unref(buf);
    }
    s->at += n;
    if (whose == 1) p->given += n;
    s->read->length -= n;
    if (!more || s->read->length <= 0) {
      // (fewer than asked and no more: the file's end, its size known by it)
      if (!more && s->read->length > 0 && p->total < 0) {
        p->total = (double)s->at;
        if (s->src) g_object_set(s->src, "size", (gint64)s->at, NULL);
      }
      g_clear_pointer(&s->read, g_free);
      // (the next read while the source wants more; its end once it has all)
      if (g_atomic_int_get(&s->wants) || (p->total >= 0 && s->at >= p->total)) source_want(s);
    }
  }
  g_mutex_unlock(&p->lock);
  // (what it waited on here: the app, which looks no more while it is buffering, looks again, as Media3's and
  // AVPlayer's word that it plays on has it do; till its read is in, each part of it)
  if (p->waiting && n > 0) mb_app_wake();
  if (failed && whose == 2) {
    vlog("view %d: no frame grabbed: its file could not be read", p->vid);
    grab_end(p);
    player_grabbed(p, NULL);
  } else if (failed && whose == 3) {
    vlog("view %d: its frames' times not read: its file could not be read", p->vid);
    scan_said(p, 1);
  } else if (failed && whose == 1 && p->state >= 0) {
    vlog("view %d: its file could not be read", p->vid);
    player_tell(p, -1);
  }
}

// The player's picture for the renderer (the GL context current): its newest frame, made its texture as it is first
// drawn; 0 before it has one. The app is told once the first is drawn (shown: a frame asked for).
unsigned mb_player_tex(int vid) {
  Player *p = player_of(vid);
  if (!p) return 0;
  g_mutex_lock(&p->lock);
  if (p->px && (p->fresh || !p->tex)) {
    glActiveTexture(GL_TEXTURE1);  // (the images' unit, which the renderer binds it to next)
    if (!p->tex) {
      glGenTextures(1, &p->tex);
      glBindTexture(GL_TEXTURE_2D, p->tex);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      p->tex_w = p->tex_h = 0;
    } else {
      glBindTexture(GL_TEXTURE_2D, p->tex);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (p->w == p->tex_w && p->h == p->tex_h) {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, p->w, p->h, GL_RGBA, GL_UNSIGNED_BYTE, p->px);
    } else {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, p->w, p->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, p->px);
      p->tex_w = p->w, p->tex_h = p->h;
    }
    p->fresh = 0;
    if (!p->drawn) p->drawn = 1, mb_app_wake();
  }
  GLuint t = p->tex;
  g_mutex_unlock(&p->lock);
  return t;
}

// As a frame begins (the GL context current): the textures of players closed since deleted.
void mb_players_upload(void) {
  if (!gone_texs || !gone_texs->len) return;
  glDeleteTextures((GLsizei)gone_texs->len, (GLuint *)gone_texs->data);
  g_array_set_size(gone_texs, 0);
}

// A new GL context: the old one's textures gone with it (made again from the frames kept).
void mb_players_lost(void) {
  for (Player *p = players; p; p = p->next) p->tex = 0;
  if (gone_texs) g_array_set_size(gone_texs, 0);
}

// whether a view is a player (its picture drawn in the canvas: mb_player_tex), not a page under it
int mb_view_is_player(int vid) { return player_of(vid) != NULL; }
