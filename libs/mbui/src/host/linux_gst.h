// GStreamer as it is on the system (libgstreamer-1.0.so.0), loaded as it is first wanted: nothing of it linked, so the
// app starts where it is not installed (gs_here false; its players and its streams' H.264 then none). Its functions
// called through `gs`, its enums' and its buffer's head written out here as its headers have them (public, the same
// through 1.x). Included by linux_player.h (linux_views.c's) and linux_stream.c, each with its own `gs` (the library
// loaded and started once: dlopen and gst_init_check are the same again); their vlog says why it is not here.
#pragma once
#include <dlfcn.h>
#include <glib-object.h>
#include <stdio.h>
#include <string.h>
#include "linux.h"

// ---- its enums' values (gst/gstelement.h, gstformat.h, gstevent.h, gstelementfactory.h, gstpad.h, app/gstappsrc.h,
// playback's GstPlayFlags) ----
enum { GSTATE_NULL = 1, GSTATE_PAUSED = 3, GSTATE_PLAYING = 4 };
enum { GFORMAT_TIME = 3 };
enum { GSEEK_FLUSH = 1 << 0, GSEEK_ACCURATE = 1 << 1, GSEEK_KEY_UNIT = 1 << 2 };
enum { GSEEK_TYPE_NONE = 0, GSEEK_TYPE_SET = 1 };
enum { GAPP_SEEKABLE = 1 };
enum { GPLAY_VIDEO = 1 << 0 };
enum { GPAD_SINK = 2 };
enum { GRANK_MARGINAL = 64 };
#define GFACTORY_DECODER ((guint64)1 << 0)
#define GFACTORY_VIDEO ((guint64)1 << 49)
#define GCLOCK_NONE ((guint64)-1)

// GstBuffer's head, as gst/gstminiobject.h and gstbuffer.h have it (public, the same through 1.x): its times
typedef struct {
  GType type;
  gint refcount, lockstate;
  guint flags;
  void *copy, *dispose, *free;
  guint priv_uint;
  gpointer priv_pointer;
  void *pool;
  guint64 pts, dts, duration, offset, offset_end;
} GstBufferHead;

#define GST_FNS(X)                                                                                                   \
  X(gboolean, gst_init_check, (int *, char ***, GError **))                                                          \
  X(void *, gst_element_factory_make, (const char *, const char *))                                                  \
  X(void *, gst_parse_bin_from_description, (const char *, gboolean, GError **))                                     \
  X(int, gst_element_set_state, (void *, int))                                                                       \
  X(void *, gst_element_get_bus, (void *))                                                                           \
  X(void, gst_bus_add_signal_watch, (void *))                                                                        \
  X(void, gst_bus_remove_signal_watch, (void *))                                                                     \
  X(void, gst_object_unref, (void *))                                                                                \
  X(void *, gst_bin_get_by_name, (void *, const char *))                                                             \
  X(gboolean, gst_element_seek, (void *, double, int, int, int, gint64, int, gint64))                                \
  X(gboolean, gst_element_query_position, (void *, int, gint64 *))                                                   \
  X(gboolean, gst_element_query_duration, (void *, int, gint64 *))                                                   \
  X(void, gst_message_parse_error, (void *, GError **, char **))                                                     \
  X(GQuark, gst_core_error_quark, (void))                                                                            \
  X(GQuark, gst_stream_error_quark, (void))                                                                          \
  X(void *, gst_buffer_new_memdup, (const void *, gsize))                                                            \
  X(void *, gst_sample_get_buffer, (void *))                                                                         \
  X(void *, gst_sample_get_caps, (void *))                                                                           \
  X(void *, gst_caps_get_structure, (void *, guint))                                                                 \
  X(gboolean, gst_structure_get_int, (void *, const char *, int *))                                                  \
  X(gsize, gst_buffer_get_size, (void *))                                                                            \
  X(gsize, gst_buffer_extract, (void *, gsize, void *, gsize))                                                       \
  X(void, gst_mini_object_unref, (void *))                                                                           \
  X(void *, gst_parse_launch, (const char *, GError **))                                                             \
  X(gboolean, gst_bin_add, (void *, void *))                                                                         \
  X(gboolean, gst_element_sync_state_with_parent, (void *))                                                          \
  X(void *, gst_element_get_static_pad, (void *, const char *))                                                      \
  X(int, gst_pad_link, (void *, void *))                                                                             \
  X(void *, gst_pad_get_current_caps, (void *))                                                                      \
  X(const char *, gst_structure_get_name, (void *))                                                                  \
  X(const char *, gst_structure_get_string, (void *, const char *))                                                  \
  X(void *, gst_sample_get_segment, (void *))                                                                        \
  X(guint64, gst_segment_to_stream_time, (void *, int, guint64))                                                    \
  X(void *, gst_caps_from_string, (const char *))                                                                    \
  X(GList *, gst_element_factory_list_get_elements, (guint64, int))                                                  \
  X(GList *, gst_element_factory_list_filter, (GList *, void *, int, gboolean))                                      \
  X(void, gst_plugin_feature_list_free, (GList *))

#define GST_FIELD(ret, name, args) ret(*name) args;
static struct {
  GST_FNS(GST_FIELD)
} gs;
static int gs_state;  // 0 not looked for, 1 here, -1 not

static int gs_here(void) {
  if (gs_state) return gs_state > 0;
  gs_state = -1;
  void *h = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (!h) {
    vlog("no GStreamer (%s): no videos played, no H.264 streams", dlerror());
    return 0;
  }
#define GST_LOAD(ret, name, args)                                               \
  if (!(*(void **)&gs.name = dlsym(h, #name))) {                                \
    vlog("a GStreamer without %s: no videos played, no H.264 streams", #name);  \
    return 0;                                                                   \
  }
  GST_FNS(GST_LOAD)
  GError *e = NULL;
  if (!gs.gst_init_check(NULL, NULL, &e)) {
    vlog("GStreamer not started (%s): no videos played, no H.264 streams", e ? e->message : "?");
    g_clear_error(&e);
    return 0;
  }
  gs_state = 1;
  return 1;
}

// What a decoded video's appsink is asked for: its frames as the decoder made them where it can (NV12 or I420, a
// videoconvert before it passing them through), their colours worked out on the GPU (linux_render.c's mb_yuv_draw).
#define GS_YUV_CAPS "video/x-raw,format=(string){NV12,I420}"

static int gs_round_up(int n, int to) { return (n + to - 1) / to * to; }

// A sample's frame (GS_YUV_CAPS: laid out as GStreamer lays it out by default, an appsink offering no video meta) copied
// out as an mb_yuv, its colours as its caps' colorimetry says (GStreamer's default where it says none: 601 under 720
// lines, else 709; 16-235); 0 where it has none or is not one of those.
static int gs_sample_yuv(void *sample, mb_yuv *out) {
  memset(out, 0, sizeof *out);
  void *buf = gs.gst_sample_get_buffer(sample), *caps = gs.gst_sample_get_caps(sample);
  void *st = caps ? gs.gst_caps_get_structure(caps, 0) : NULL;
  if (!buf || !st) return 0;
  int w = 0, h = 0;
  gs.gst_structure_get_int(st, "width", &w);
  gs.gst_structure_get_int(st, "height", &h);
  const char *format = gs.gst_structure_get_string(st, "format");
  if (w <= 0 || h <= 0 || !format) return 0;
  int nv12 = strcmp(format, "NV12") == 0;
  if (!nv12 && strcmp(format, "I420") != 0) return 0;
  // (gst-video's default layout: video-info.c's fill_planes)
  int s0 = gs_round_up(w, 4), h2 = gs_round_up(h, 2);
  size_t size;
  out->stride[0] = s0;
  out->off[0] = 0;
  out->off[1] = (size_t)s0 * h2;
  if (nv12) {
    out->stride[1] = s0;
    size = out->off[1] + (size_t)s0 * (h2 / 2);
  } else {
    int s1 = gs_round_up(gs_round_up(w, 2) / 2, 4);
    out->stride[1] = out->stride[2] = s1;
    out->off[2] = out->off[1] + (size_t)s1 * (h2 / 2);
    size = out->off[2] + (size_t)s1 * (h2 / 2);
  }
  if (gs.gst_buffer_get_size(buf) < size) return 0;
  // its colours: "bt709", "bt601", "bt2020"…, or GstVideoColorimetry's numbers ("range:matrix:transfer:primaries":
  // range 1 full, 2 16-235; matrix 3 709, 4 601, 6 2020)
  const char *cm = gs.gst_structure_get_string(st, "colorimetry");
  out->matrix = h < 720 ? 601 : 709;
  out->full = 0;
  if (cm && *cm >= '0' && *cm <= '9') {
    int range = 0, matrix = 0;
    sscanf(cm, "%d:%d", &range, &matrix);
    out->full = range == 1;
    if (matrix == 3) out->matrix = 709;
    else if (matrix == 4) out->matrix = 601;
    else if (matrix == 6) out->matrix = 2020;
  } else if (cm) {
    if (strstr(cm, "2020") || strstr(cm, "2100")) out->matrix = 2020;
    else if (strstr(cm, "709") || strstr(cm, "240")) out->matrix = 709;
    else if (strstr(cm, "601")) out->matrix = 601;
    else if (strcmp(cm, "sRGB") == 0) out->matrix = 709, out->full = 1;
  }
  out->w = w, out->h = h, out->nv12 = nv12, out->size = size;
  out->data = g_malloc(size);
  gs.gst_buffer_extract(buf, 0, out->data, size);
  return 1;
}
