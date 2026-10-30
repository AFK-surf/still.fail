// Native views over the canvas (host_native.mbt's view_*) on Linux: web pages in WebKitGTK 6.0, the system's own,
// loaded as the first view opens (libwebkitgtk-6.0.so.4: nothing of it linked, so the app starts where it is not
// installed; there view_open answers 0 and the app says it cannot show it, as Windows does without WebView2's
// runtime). Each is a widget under the canvas: the window's GtkOverlay has the views' GtkFixed for its child and the
// GtkGLArea over it (linux_app.c); the app paints a hole (kind 9: MB_VIEWS_UNDER in gles_render.h, the canvas taken
// away there) where one shows, and what it paints after the hole draws over it, as apple_views.m and win_views.cpp
// have it. A press where one shows goes to it (the area holds none there: its contains), not to the app. Kind 2, a
// page of HTML, and kind 3, a site whose every request the app answers (view_site_*); kind 1, a video player,
// GStreamer's, drawn in the canvas (linux_player.h).
//
// A site loads from a scheme of its own that never reaches the network (stillfail-preview://svc/…, as Apple's), a page
// from its HTML with no base (about:blank's, as Apple's): no link of either followed, a site's said to the app. Nothing
// of them kept (an ephemeral network session); a custom scheme has no cookies (the app keeps a site's: keeps_cookies).
//
// Threads: everything here runs on the main thread, WebKit's signals among them, but a site's answer's body, which
// WebKit reads on a thread of GIO's as the app sends it (Body).
#include <dlfcn.h>
#include <epoxy/gl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gtk/gtk.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <libsoup/soup.h>
#include "linux.h"
#include "mini_json.h"  // the app's head of an answer

void mb_host_request_frame(void);

#define SITE "stillfail-preview"
#define SITE_ROOT SITE "://svc"

// "view N: …" lines on stdout, as the other hosts log theirs
#define vlog(...) (fprintf(stdout, __VA_ARGS__), fputc('\n', stdout), fflush(stdout))

// ---- WebKitGTK 6.0, as it is there ----

// its enums' values (webkit/WebKitWebView.h, WebKitError.h, WebKitUserContent.h)
enum { WK_LOAD_STARTED = 0, WK_LOAD_FINISHED = 3 };
enum { WK_POLICY_NAVIGATION = 0, WK_POLICY_NEW_WINDOW = 1 };
enum { WK_NAV_LINK = 0, WK_NAV_FORM = 1, WK_NAV_FORM_AGAIN = 4 };
enum { WK_NETWORK_ERROR_CANCELLED = 302, WK_POLICY_ERROR_INTERRUPTED = 102 };
enum { WK_TOP_FRAME = 1, WK_AT_DOCUMENT_START = 0, WK_SNAPSHOT_VISIBLE = 0, WK_SNAPSHOT_NONE = 0 };

typedef void (*wk_scheme_fn)(void *request, gpointer data);
#define WK_FNS(X)                                                                                                    \
  X(GType, webkit_web_view_get_type, (void))                                                                         \
  X(void *, webkit_network_session_new_ephemeral, (void))                                                            \
  X(void *, webkit_web_context_get_default, (void))                                                                  \
  X(void, webkit_web_context_register_uri_scheme, (void *, const char *, wk_scheme_fn, gpointer, GDestroyNotify))   \
  X(void *, webkit_web_context_get_security_manager, (void *))                                                       \
  X(void, webkit_security_manager_register_uri_scheme_as_secure, (void *, const char *))                            \
  X(void, webkit_security_manager_register_uri_scheme_as_cors_enabled, (void *, const char *))                      \
  X(const char *, webkit_uri_scheme_request_get_uri, (void *))                                                       \
  X(const char *, webkit_uri_scheme_request_get_http_method, (void *))                                               \
  X(SoupMessageHeaders *, webkit_uri_scheme_request_get_http_headers, (void *))                                      \
  X(GInputStream *, webkit_uri_scheme_request_get_http_body, (void *))                                               \
  X(void *, webkit_uri_scheme_request_get_web_view, (void *))                                                        \
  X(void, webkit_uri_scheme_request_finish_with_response, (void *, void *))                                          \
  X(void, webkit_uri_scheme_request_finish_error, (void *, GError *))                                                \
  X(void *, webkit_uri_scheme_response_new, (GInputStream *, gint64))                                                \
  X(void, webkit_uri_scheme_response_set_status, (void *, guint, const char *))                                      \
  X(void, webkit_uri_scheme_response_set_content_type, (void *, const char *))                                       \
  X(void, webkit_uri_scheme_response_set_http_headers, (void *, SoupMessageHeaders *))                               \
  X(void *, webkit_user_content_manager_new, (void))                                                                 \
  X(gboolean, webkit_user_content_manager_register_script_message_handler, (void *, const char *, const char *))    \
  X(void *, webkit_user_script_new, (const char *, int, int, const char *const *, const char *const *))             \
  X(void, webkit_user_content_manager_add_script, (void *, void *))                                                  \
  X(void, webkit_user_script_unref, (void *))                                                                        \
  X(void, webkit_web_view_load_uri, (void *, const char *))                                                          \
  X(void, webkit_web_view_load_html, (void *, const char *, const char *))                                           \
  X(void, webkit_web_view_evaluate_javascript,                                                                       \
    (void *, const char *, gssize, const char *, const char *, GCancellable *, GAsyncReadyCallback, gpointer))      \
  X(void, webkit_web_view_go_back, (void *))                                                                         \
  X(void, webkit_web_view_go_forward, (void *))                                                                      \
  X(void, webkit_web_view_reload, (void *))                                                                          \
  X(void, webkit_web_view_stop_loading, (void *))                                                                    \
  X(gboolean, webkit_web_view_can_go_back, (void *))                                                                 \
  X(gboolean, webkit_web_view_can_go_forward, (void *))                                                              \
  X(const char *, webkit_web_view_get_uri, (void *))                                                                 \
  X(const char *, webkit_web_view_get_title, (void *))                                                               \
  X(gboolean, webkit_web_view_is_loading, (void *))                                                                  \
  X(void, webkit_web_view_set_zoom_level, (void *, double))                                                          \
  X(void, webkit_web_view_set_background_color, (void *, const GdkRGBA *))                                           \
  X(void, webkit_web_view_get_snapshot, (void *, int, int, GCancellable *, GAsyncReadyCallback, gpointer))           \
  X(GdkTexture *, webkit_web_view_get_snapshot_finish, (void *, GAsyncResult *, GError **))                          \
  X(void *, webkit_web_view_get_settings, (void *))                                                                  \
  X(void, webkit_settings_set_enable_developer_extras, (void *, gboolean))                                           \
  X(void *, webkit_navigation_policy_decision_get_navigation_action, (void *))                                       \
  X(void *, webkit_navigation_action_get_request, (void *))                                                          \
  X(int, webkit_navigation_action_get_navigation_type, (void *))                                                     \
  X(const char *, webkit_uri_request_get_uri, (void *))                                                              \
  X(void, webkit_policy_decision_ignore, (void *))                                                                   \
  X(void, webkit_policy_decision_use, (void *))                                                                      \
  X(GQuark, webkit_network_error_quark, (void))                                                                      \
  X(GQuark, webkit_policy_error_quark, (void))                                                                       \
  X(char *, jsc_value_to_string, (void *))

#define WK_FIELD(ret, name, args) ret(*name) args;
static struct {
  WK_FNS(WK_FIELD)
} wk;
static int wk_state;  // 0 not looked for, 1 here, -1 not
static void *session;  // the views' network session (ephemeral)

static void on_scheme(void *request, gpointer data);

// WebKit's sandbox (bubblewrap: its web process in a user namespace with a network of its own), where the system lets a
// program make one. Where it does not (Ubuntu 24.04's AppArmor lets a user namespace be made but not its loopback set
// up; a container; no bwrap), WebKit's web process dies as it starts and WebKit takes the app down with it: its pages
// run without the sandbox there, which the log says as the first view opens. Looked at as the program starts, before
// any thread (it is said to WebKit in the environment, which nothing may change while threads read it).
static int sandbox_off;
__attribute__((constructor)) static void sandbox_here(void) {
  if (getenv("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS")) return;
  char *argv[] = {"bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--unshare-user-try",
                  "--unshare-net", "--unshare-pid", "true", NULL};
  int status = -1;
  if (g_spawn_sync(NULL, argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                   NULL, NULL, NULL, NULL, &status, NULL) &&
      g_spawn_check_wait_status(status, NULL))
    return;
  setenv("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1", 1);
  sandbox_off = 1;
}

// WebKitGTK loaded, once: whether it is here (and its site's scheme registered)
static int wk_here(void) {
  if (wk_state) return wk_state > 0;
  wk_state = -1;
  void *h = dlopen("libwebkitgtk-6.0.so.4", RTLD_NOW | RTLD_GLOBAL);
  if (!h) {
    vlog("view: no WebKitGTK 6.0 (%s): web views cannot be shown", dlerror());
    return 0;
  }
#define WK_LOAD(ret, name, args)                                       \
  if (!(*(void **)&wk.name = dlsym(h, #name))) {                       \
    vlog("view: WebKitGTK 6.0 without %s: web views cannot be shown", #name); \
    return 0;                                                          \
  }
  WK_FNS(WK_LOAD)
  void *ctx = wk.webkit_web_context_get_default();
  wk.webkit_web_context_register_uri_scheme(ctx, SITE, on_scheme, NULL, NULL);
  void *sec = wk.webkit_web_context_get_security_manager(ctx);
  // (a secure context, as https is: fetch, EventSource and the rest as a page has them on the web)
  wk.webkit_security_manager_register_uri_scheme_as_secure(sec, SITE);
  wk.webkit_security_manager_register_uri_scheme_as_cors_enabled(sec, SITE);
  session = wk.webkit_network_session_new_ephemeral();
  wk_state = 1;
  vlog("view: WebKitGTK 6.0%s", sandbox_off ? ", without its sandbox (the system lets no program make one)" : "");
  return 1;
}

// ---- a site's answer's body: what the app sent so far, read by WebKit as it comes (a GInputStream whose read waits
// for more, on GIO's thread: its default asynchronous read runs this one there). The page letting it go (its read
// cancelled, the stream closed before its end) is said to the app on the main thread (body_gone). ----

typedef struct {
  GInputStream parent;
  GMutex lock;
  GCond more;
  GByteArray *data;  // sent, not read yet
  int ended;         // 1 whole, -1 broken off
  int let_go;        // the page took no more of it
  int vid, rid;      // whose
} Body;
typedef struct {
  GInputStreamClass parent;
} BodyClass;
G_DEFINE_TYPE(Body, body, G_TYPE_INPUT_STREAM)

static gboolean body_gone(gpointer ids);

// (b->lock held) the page took no more of it: said once, on the main thread
static void body_let_go(Body *b) {
  if (b->let_go || b->ended) return;
  b->let_go = 1;
  int *ids = g_new(int, 2);
  ids[0] = b->vid, ids[1] = b->rid;
  g_idle_add(body_gone, ids);
}

static void body_cancelled(GCancellable *c, gpointer data) {
  (void)c;
  Body *b = data;
  g_mutex_lock(&b->lock);
  g_cond_broadcast(&b->more);
  g_mutex_unlock(&b->lock);
}

static gssize body_read(GInputStream *s, void *buf, gsize n, GCancellable *c, GError **e) {
  Body *b = (Body *)s;
  gulong watch = c ? g_cancellable_connect(c, G_CALLBACK(body_cancelled), b, NULL) : 0;
  g_mutex_lock(&b->lock);
  while (b->data->len == 0 && !b->ended && !g_cancellable_is_cancelled(c)) g_cond_wait(&b->more, &b->lock);
  gssize got = (gssize)MIN(n, b->data->len);
  if (g_cancellable_set_error_if_cancelled(c, e)) {
    body_let_go(b);
    got = -1;
  } else if (got > 0) {
    memcpy(buf, b->data->data, (size_t)got);
    g_byte_array_remove_range(b->data, 0, (guint)got);
  } else if (b->ended < 0) {
    g_set_error_literal(e, G_IO_ERROR, G_IO_ERROR_BROKEN_PIPE, "the answer broke off");
    got = -1;
  }
  g_mutex_unlock(&b->lock);
  if (watch) g_cancellable_disconnect(c, watch);
  return got;
}

static gboolean body_close(GInputStream *s, GCancellable *c, GError **e) {
  (void)c, (void)e;
  Body *b = (Body *)s;
  g_mutex_lock(&b->lock);
  body_let_go(b);
  g_mutex_unlock(&b->lock);
  return TRUE;
}

static void body_finalize(GObject *o) {
  Body *b = (Body *)o;
  g_byte_array_unref(b->data);
  g_mutex_clear(&b->lock);
  g_cond_clear(&b->more);
  G_OBJECT_CLASS(body_parent_class)->finalize(o);
}

static void body_class_init(BodyClass *k) {
  G_INPUT_STREAM_CLASS(k)->read_fn = body_read;
  G_INPUT_STREAM_CLASS(k)->close_fn = body_close;
  G_OBJECT_CLASS(k)->finalize = body_finalize;
}

static void body_init(Body *b) {
  g_mutex_init(&b->lock);
  g_cond_init(&b->more);
  b->data = g_byte_array_new();
}

// more of it sent (and its end: 1 whole, -1 broken off): how much of it waits to be read now
static gsize body_put(Body *b, const uint8_t *p, size_t n, int end) {
  g_mutex_lock(&b->lock);
  if (!b->ended && !b->let_go) {
    if (n) g_byte_array_append(b->data, p, (guint)n);
    if (end) b->ended = end;
  }
  gsize waits = b->data->len;
  g_cond_broadcast(&b->more);
  g_mutex_unlock(&b->lock);
  return waits;
}

// ---- a view's box: where it shows (the clip), its page at its rect within it, its corners round ----

typedef struct {
  GtkWidget parent;
  GtkWidget *child;
  double w, h;               // the clip's size, points
  double px, py, pw, ph;     // the page's rect within it
  double r[4];               // its corners (top left, then round it)
  double ox, oy, cw, ch;     // the part of the page its widget is (all of it but where it is too big: band)
} Box;
typedef struct {
  GtkWidgetClass parent;
} BoxClass;
G_DEFINE_TYPE(Box, box, GTK_TYPE_WIDGET)

static void box_measure(GtkWidget *w, GtkOrientation o, int for_size, int *min, int *nat, int *min_base,
                        int *nat_base) {
  (void)for_size;
  Box *b = (Box *)w;
  *min = *nat = (int)ceil(o == GTK_ORIENTATION_HORIZONTAL ? b->w : b->h);
  *min_base = *nat_base = -1;
}

static void box_allocate(GtkWidget *w, int width, int height, int baseline) {
  (void)width, (void)height, (void)baseline;
  Box *b = (Box *)w;
  if (!b->child) return;
  graphene_point_t at = GRAPHENE_POINT_INIT((float)b->ox, (float)b->oy);
  gtk_widget_allocate(b->child, (int)ceil(b->cw), (int)ceil(b->ch), -1, gsk_transform_translate(NULL, &at));
}

static void box_snapshot(GtkWidget *w, GtkSnapshot *s) {
  Box *b = (Box *)w;
  if (!b->child) return;
  graphene_rect_t clip = GRAPHENE_RECT_INIT(0, 0, (float)b->w, (float)b->h);
  gtk_snapshot_push_clip(s, &clip);
  int round = b->r[0] > 0 || b->r[1] > 0 || b->r[2] > 0 || b->r[3] > 0;
  if (round) {
    GskRoundedRect rr;
    graphene_rect_t page = GRAPHENE_RECT_INIT((float)b->px, (float)b->py, (float)b->pw, (float)b->ph);
    graphene_size_t k[4];
    for (int i = 0; i < 4; i++) k[i] = GRAPHENE_SIZE_INIT((float)b->r[i], (float)b->r[i]);
    gsk_rounded_rect_init(&rr, &page, &k[0], &k[1], &k[2], &k[3]);
    gtk_snapshot_push_rounded_clip(s, &rr);
  }
  gtk_widget_snapshot_child(w, b->child, s);
  if (round) gtk_snapshot_pop(s);
  gtk_snapshot_pop(s);
}

static void box_dispose(GObject *o) {
  Box *b = (Box *)o;
  g_clear_pointer(&b->child, gtk_widget_unparent);
  G_OBJECT_CLASS(box_parent_class)->dispose(o);
}

static void box_class_init(BoxClass *k) {
  GTK_WIDGET_CLASS(k)->measure = box_measure;
  GTK_WIDGET_CLASS(k)->size_allocate = box_allocate;
  GTK_WIDGET_CLASS(k)->snapshot = box_snapshot;
  G_OBJECT_CLASS(k)->dispose = box_dispose;
}

static void box_init(Box *b) { gtk_widget_set_overflow(GTK_WIDGET(b), GTK_OVERFLOW_HIDDEN); }

// ---------------------------------------------------------------------------

// One request of a site's page: what it asked, until the app has answered it whole.
typedef struct Req {
  int rid;
  void *request;  // WebKitURISchemeRequest, a reference held
  GBytes *body;   // the request's
  int headed, slow;
  Body *answer;  // its body as the app sends it, once headed
  struct Req *next;
} Req;

typedef struct View {
  int vid, kind;
  double x, y, w, h, cx0, cy0, cx1, cy1;
  double r[4];  // its corners (top left, then round it)
  int shown, placed;
  double band_x, band_y, zoom;  // where its widget's part of a page too big for one begins (device pixels); its zoom
  int loaded, failed, told, loading, there, load_broke;
  char *html;  // a page's
  int html_len;
  char *start;  // a site's first path
  GtkWidget *web;  // WebKitWebView
  Box *box;
  // a site's: what it said (JSON, oldest first), its requests waiting on the app
  GQueue said;
  Req *reqs;
  int next_req;
  double backlog;  // the app's setting (view_tell 3): how much of an answer may wait to be read
  // the scripts the app sent (view_tell 1), waiting for the page there; who takes the mouse on it (view_tell 2);
  // where the app draws what takes a press over it (view_tell 4: x0 y0 x1 y1 …, points)
  GPtrArray *scripts;
  char touch[16];
  GArray *covers;
  // a page grabbed (PNG; still_state 1 grabbing, 2 here, -1 failed)
  GBytes *still;
  int still_state;
  struct View *next;  // as they are stacked: the last opened (or raised: view_tell 5) on top
} View;

static View *views;
static int next_vid;
static GQueue told, grabs;  // (id, state) pairs for the app (mb_views_tell), as GINT_TO_POINTER(id), (state)

static View *find(int vid) {
  for (View *v = views; v; v = v->next)
    if (v->vid == vid) return v;
  return NULL;
}

static View *of_web(void *web) {
  for (View *v = views; v; v = v->next)
    if ((void *)v->web == web) return v;
  return NULL;
}

// (kind 1: the video players, GStreamer's)
#include "linux_player.h"

// Its state for the app (host_native.mbt's set_outside, kind 2): 1 ready (a page loaded), -1 failed, 0 waiting on the
// app now (a site's request): told between frames (mb_views_tell).
static void outside(View *v, int state) {
  g_queue_push_tail(&told, GINT_TO_POINTER(v->vid));
  g_queue_push_tail(&told, GINT_TO_POINTER(state));
  vlog("view %d: told %d", v->vid, state);
  mb_host_request_frame();
}

static void tell(View *v, int state) {
  if (v->told && state > 0) return;
  v->told = state > 0;
  outside(v, state);
}

static void fail(View *v, const char *why) {
  if (v->loaded || v->failed) return;
  v->failed = 1;
  vlog("view %d: failed: %s", v->vid, why);
  tell(v, -1);
}

static void say(View *v, GString *e) {
  g_queue_push_tail(&v->said, g_string_free(e, FALSE));
  mb_host_request_frame();
}

// a JSON string's text, quoted
static void jquote(GString *o, const char *s) {
  g_string_append_c(o, '"');
  for (; s && *s; s++) {
    unsigned char c = (unsigned char)*s;
    if (c == '"' || c == '\\') g_string_append_c(o, '\\'), g_string_append_c(o, (char)c);
    else if (c < 0x20) g_string_append_printf(o, "\\u%04x", c);
    else g_string_append_c(o, (char)c);
  }
  g_string_append_c(o, '"');
}

static char *utf8(moonbit_string_t s) {
  return g_utf16_to_utf8((const gunichar2 *)s, Moonbit_array_length(s), NULL, NULL, NULL);
}

static moonbit_string_t mstr(const char *s) {
  glong n = 0;
  gunichar2 *u = g_utf8_to_utf16(s ? s : "", -1, NULL, &n, NULL);
  moonbit_string_t out = moonbit_make_string_raw((int32_t)n);
  if (n) memcpy(out, u, (size_t)n * 2);
  g_free(u);
  return out;
}

// the path (with its query) of a site's URI; NULL when it is not one of its
static char *path_of(const char *uri) {
  size_t n = strlen(SITE_ROOT);
  if (!uri || g_ascii_strncasecmp(uri, SITE_ROOT, n) != 0) return NULL;
  const char *p = uri + n;
  if (*p && *p != '/' && *p != '?' && *p != '#') return NULL;
  GString *out = g_string_new(*p == '/' ? "" : "/");
  g_string_append(out, p);
  char *hash = strchr(out->str, '#');
  if (hash) g_string_truncate(out, (gsize)(hash - out->str));
  return g_string_free(out, FALSE);
}

// The most a view's widget is across, device pixels: what every GL takes as one texture, and cairo (a widget bigger is
// drawn by neither: GTK aborts).
#define MAX_PX 8192

// Along one axis, a page from p0 to p1 seen from v0 to v1 (device pixels): where the part of it its widget shows begins
// when it is too big for one (MAX_PX of it: what is seen and as much around it), kept while what is seen stays in it.
static double band(double p0, double p1, double v0, double v1, double was) {
  if (p1 - p0 <= MAX_PX) return 0;
  double off = was;
  if (v1 > v0 && (v0 - p0 < off || v1 - p0 > off + MAX_PX)) off = round((v0 + v1) / 2 - p0 - MAX_PX / 2.0);
  return fmin(fmax(off, 0), p1 - p0 - MAX_PX);
}

// A page too big for one widget scrolled to the part its widget shows (its CSS pixels: points over its zoom). Its
// part is moved only as what is seen leaves it, and shows the page there once the page has scrolled (a frame after).
static void scroll_band(View *v) {
  if (!v->web || !v->there || (v->band_x == 0 && v->band_y == 0)) return;
  double s = mb_app_scale() > 0 ? mb_app_scale() : 1, z = v->kind == 3 && v->zoom > 0 ? v->zoom : 1;
  char js[96];
  g_snprintf(js, sizeof js, "window.scrollTo(%.1f,%.1f)", v->band_x / s / z, v->band_y / s / z);
  wk.webkit_web_view_evaluate_javascript(v->web, js, -1, NULL, NULL, NULL, NULL, NULL);
}

// Placed as it was last told: its box at the clip (its edges on device pixels), its page at its rect within it,
// hidden while it is not shown.
static void apply_place(View *v) {
  if (!v->box) return;
  double s = mb_app_scale();
  if (s <= 0) s = 1;
  double bx = round(v->cx0 * s), by = round(v->cy0 * s);
  double bw = v->shown ? fmax(0, round(v->cx1 * s) - bx) : 0, bh = v->shown ? fmax(0, round(v->cy1 * s) - by) : 0;
  // its page's edges each on the device pixel nearest it (right minus left, not its width rounded: that can land a
  // pixel off the hole's edge)
  double px0 = round(v->x * s), py0 = round(v->y * s);
  double pw = fmax(0, round((v->x + fmax(0, v->w)) * s) - px0), ph = fmax(0, round((v->y + fmax(0, v->h)) * s) - py0);
  Box *b = v->box;
  b->w = bw / s, b->h = bh / s;
  b->px = (px0 - bx) / s, b->py = (py0 - by) / s, b->pw = pw / s, b->ph = ph / s;
  for (int i = 0; i < 4; i++) b->r[i] = fmax(0, v->r[i]);
  // (a page too big for one widget: the part of it seen and around it, the page scrolled to it)
  if (v->shown) {
    double ox = band(px0, px0 + pw, fmax(bx, px0), fmin(bx + bw, px0 + pw), v->band_x);
    double oy = band(py0, py0 + ph, fmax(by, py0), fmin(by + bh, py0 + ph), v->band_y);
    if (ox != v->band_x || oy != v->band_y) {
      v->band_x = ox, v->band_y = oy;
      scroll_band(v);
    }
  }
  b->ox = (px0 + v->band_x - bx) / s, b->oy = (py0 + v->band_y - by) / s;
  b->cw = fmin(pw, MAX_PX) / s, b->ch = fmin(ph, MAX_PX) / s;
  gtk_fixed_move(GTK_FIXED(mb_app_under()), GTK_WIDGET(b), bx / s, by / s);
  gtk_widget_set_visible(GTK_WIDGET(b), v->shown && bw > 0 && bh > 0);
  gtk_widget_queue_resize(GTK_WIDGET(b));
  // where it is now, in device pixels (scripts/host_contract.sh HOST views compares it with VIEWTOLD)
  if (v->shown)
    vlog("VIEWAT %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", v->vid, px0, py0, pw, ph, bx, by,
         bx + bw, by + bh, fmax(fmax(b->r[0], b->r[1]), fmax(b->r[2], b->r[3])) * s, b->r[0] * s, b->r[1] * s,
         b->r[2] * s, b->r[3] * s);
}

// ---- a site's requests, answered by the app ----

static void respond(void *request, int status, const char *type, const void *data, size_t n) {
  GInputStream *in = g_memory_input_stream_new_from_data(g_memdup2(data, n), (gssize)n, g_free);
  void *r = wk.webkit_uri_scheme_response_new(in, (gint64)n);
  wk.webkit_uri_scheme_response_set_status(r, (guint)status, NULL);
  wk.webkit_uri_scheme_response_set_content_type(r, type);
  wk.webkit_uri_scheme_request_finish_with_response(request, r);
  g_object_unref(r);
  g_object_unref(in);
}

static Req *req_of(View *v, int rid, int unlink);
static void req_free(Req *q);

// {"slow": rid}, {"gone": rid}: the app's to answer (native.mbt: its words, or the request let go)
static void say_req(View *v, const char *what, int rid) {
  GString *e = g_string_new(NULL);
  g_string_printf(e, "{\"%s\":%d}", what, rid);
  say(v, e);
}

// the page let an answer go (it reads no more of it): said, and the request let go of here too
static gboolean body_gone(gpointer ids) {
  int *id = ids;
  View *v = find(id[0]);
  Req *q = req_of(v, id[1], 1);
  if (q) {
    say_req(v, "gone", q->rid);
    req_free(q);
  }
  g_free(ids);
  return G_SOURCE_REMOVE;
}

static void on_scheme(void *request, gpointer data) {
  (void)data;
  View *v = of_web(wk.webkit_uri_scheme_request_get_web_view(request));
  if (!v || v->kind != 3) {
    GError *e = g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED, "no site here");
    wk.webkit_uri_scheme_request_finish_error(request, e);
    g_error_free(e);
    return;
  }
  Req *q = g_new0(Req, 1);
  q->rid = ++v->next_req;
  q->request = g_object_ref(request);
  GByteArray *body = g_byte_array_new();
  GInputStream *in = wk.webkit_uri_scheme_request_get_http_body(request);
  if (in) {
    uint8_t buf[16384];
    gssize n;
    while ((n = g_input_stream_read(in, buf, sizeof buf, NULL, NULL)) > 0) g_byte_array_append(body, buf, (guint)n);
    g_object_unref(in);
  }
  q->body = g_byte_array_free_to_bytes(body);
  const char *method = wk.webkit_uri_scheme_request_get_http_method(request);
  char *path = path_of(wk.webkit_uri_scheme_request_get_uri(request));
  GString *e = g_string_new(NULL);
  g_string_append_printf(e, "{\"req\":%d,\"method\":", q->rid);
  jquote(e, method ? method : "GET");
  g_string_append(e, ",\"path\":");
  jquote(e, path ? path : "/");
  g_free(path);
  g_string_append(e, ",\"headers\":[");
  int page = 0, first = 1;
  SoupMessageHeaders *hs = wk.webkit_uri_scheme_request_get_http_headers(request);
  if (hs) {
    SoupMessageHeadersIter it;
    const char *k, *val;
    soup_message_headers_iter_init(&it, hs);
    while (soup_message_headers_iter_next(&it, &k, &val)) {
      if (!first) g_string_append_c(e, ',');
      first = 0;
      g_string_append_c(e, '[');
      jquote(e, k);
      g_string_append_c(e, ',');
      jquote(e, val);
      g_string_append_c(e, ']');
      if (!g_ascii_strcasecmp(k, "Accept") && !g_ascii_strncasecmp(val, "text/html", 9)) page = 1;
    }
  }
  g_string_append_printf(e, "],\"page\":%s}", page ? "true" : "false");
  q->next = v->reqs;
  v->reqs = q;
  say(v, e);
  // the site waits on the app's answer now
  outside(v, 0);
}

static double v_backlog(int vid) {
  View *v = find(vid);
  return v ? v->backlog : 0;
}

static Req *req_of(View *v, int rid, int unlink) {
  for (Req **p = v ? &v->reqs : NULL; p && *p; p = &(*p)->next)
    if ((*p)->rid == rid) {
      Req *q = *p;
      if (unlink) *p = q->next;
      return q;
    }
  return NULL;
}

static void req_free(Req *q) {
  if (q->answer) g_object_unref(q->answer);
  g_object_unref(q->request);
  g_bytes_unref(q->body);
  g_free(q);
}

// ---- making it ----

// What waits for the page runs, once it is there.
static void run_scripts(View *v) {
  if (!v->there || !v->web) return;
  for (guint i = 0; i < v->scripts->len; i++)
    wk.webkit_web_view_evaluate_javascript(v->web, g_ptr_array_index(v->scripts, i), -1, NULL, NULL, NULL, NULL, NULL);
  g_ptr_array_set_size(v->scripts, 0);
}

// the page's way to the app (mbuiHost.post): its own messages, nothing else of the app's
static void on_said(void *ucm, void *value, gpointer data) {
  (void)ucm;
  View *v = find(GPOINTER_TO_INT(data));
  if (!v) return;
  char *text = wk.jsc_value_to_string(value);
  GString *e = g_string_new("{\"said\":");
  jquote(e, text);
  g_string_append_c(e, '}');
  g_free(text);
  say(v, e);
  v->there = 1;
  run_scripts(v);
}

// a link of a site's elsewhere said to the app (which opens it), not followed; a data:, blob: or javascript: one quietly
static void leave(View *v, const char *u) {
  if (!*u || !g_ascii_strncasecmp(u, "data:", 5) || !g_ascii_strncasecmp(u, "blob:", 5) ||
      !g_ascii_strncasecmp(u, "javascript:", 11))
    return;
  GString *e = g_string_new("{\"leave\":");
  jquote(e, u);
  g_string_append_c(e, '}');
  say(v, e);
}

// whether a site's page may be at `u`: its own scheme's, or about:
static int site_own(const char *u) {
  char *path = path_of(u);
  int own = path || (u && !g_ascii_strncasecmp(u, "about:", 6));
  g_free(path);
  return own;
}

static gboolean on_policy(GtkWidget *web, void *decision, int type, gpointer data) {
  (void)web;
  View *v = find(GPOINTER_TO_INT(data));
  if (!v || (type != WK_POLICY_NAVIGATION && type != WK_POLICY_NEW_WINDOW)) return FALSE;
  void *action = wk.webkit_navigation_policy_decision_get_navigation_action(decision);
  const char *u = wk.webkit_uri_request_get_uri(wk.webkit_navigation_action_get_request(action));
  if (!u) u = "";
  if (v->kind == 2) {
    // only the page given (about:blank, and its frames' about:srcdoc): no link followed, nothing else loaded
    int ok = type == WK_POLICY_NAVIGATION && !g_ascii_strncasecmp(u, "about:", 6);
    if (ok) wk.webkit_policy_decision_use(decision);
    else wk.webkit_policy_decision_ignore(decision), vlog("view %d: navigation to %s cancelled", v->vid, u);
    return TRUE;
  }
  // a site: its own pages, and any frame in it, as Apple's has it. WebKitGTK does not say whether a navigation is its
  // page's or a frame's: one elsewhere the person set off (a link, a form) is said and not followed, any other let go
  // on (a frame's loads; the page's own is stopped as it starts: on_load); a new window (target=_blank, window.open)
  // none, said
  int nav = wk.webkit_navigation_action_get_navigation_type(action);
  int person = nav == WK_NAV_LINK || nav == WK_NAV_FORM || nav == WK_NAV_FORM_AGAIN;
  if (type == WK_POLICY_NAVIGATION && (site_own(u) || !person)) {
    wk.webkit_policy_decision_use(decision);
    return TRUE;
  }
  leave(v, u);
  wk.webkit_policy_decision_ignore(decision);
  return TRUE;
}

static void grab_done(GObject *web, GAsyncResult *res, gpointer data) {
  View *v = find(GPOINTER_TO_INT(data));
  GdkTexture *t = wk.webkit_web_view_get_snapshot_finish(web, res, NULL);
  if (!v) {
    if (t) g_object_unref(t);
    return;
  }
  g_clear_pointer(&v->still, g_bytes_unref);
  if (t) {
    v->still = gdk_texture_save_to_png_bytes(t);
    g_object_unref(t);
  }
  v->still_state = v->still && g_bytes_get_size(v->still) ? 2 : -1;
  vlog("view %d: page %s", v->vid, v->still_state == 2 ? "grabbed" : "not grabbed");
  g_queue_push_tail(&grabs, GINT_TO_POINTER(v->vid));
  g_queue_push_tail(&grabs, GINT_TO_POINTER(v->still_state == 2 ? 1 : -1));
  mb_host_request_frame();
}

// What its page shows now, as a PNG: `still` once it is here, told as a grab.
static void grab_page(View *v) {
  v->still_state = 1;
  g_clear_pointer(&v->still, g_bytes_unref);
  if (!v->web) {
    v->still_state = -1;
    g_queue_push_tail(&grabs, GINT_TO_POINTER(v->vid));
    g_queue_push_tail(&grabs, GINT_TO_POINTER(-1));
    mb_host_request_frame();
    return;
  }
  wk.webkit_web_view_get_snapshot(v->web, WK_SNAPSHOT_VISIBLE, WK_SNAPSHOT_NONE, NULL, grab_done,
                                  GINT_TO_POINTER(v->vid));
}

static void on_load(GtkWidget *web, int event, gpointer data) {
  (void)web;
  View *v = find(GPOINTER_TO_INT(data));
  if (!v) return;
  mb_host_request_frame();
  if (event == WK_LOAD_STARTED) {
    // (a site's page going elsewhere, not set off by the person: stopped, said; the page it was stays)
    const char *u = wk.webkit_web_view_get_uri(v->web);
    if (v->kind == 3 && u && !site_own(u)) {
      leave(v, u);
      wk.webkit_web_view_stop_loading(v->web);
      return;
    }
    v->loading = 1;
    v->there = 0;
    v->load_broke = 0;
    return;
  }
  if (event != WK_LOAD_FINISHED) return;
  v->loading = 0;
  // (one that failed said so: load-failed, before this)
  if (v->load_broke) return;
  v->there = 1;
  run_scripts(v);
  scroll_band(v);
  if (v->kind == 3) tell(v, 1);
  if (v->loaded) return;
  v->loaded = 1;
  vlog("view %d: %s loaded", v->vid, v->kind == 3 ? "site page" : "page");
  tell(v, 1);
}

static gboolean on_load_failed(GtkWidget *web, int event, const char *uri, GError *e, gpointer data) {
  (void)web, (void)event;
  View *v = find(GPOINTER_TO_INT(data));
  if (!v) return FALSE;
  v->load_broke = 1;
  // one it went from (a link not followed, a new one begun) is not a failure
  if ((e->domain == wk.webkit_network_error_quark() && e->code == WK_NETWORK_ERROR_CANCELLED) ||
      (e->domain == wk.webkit_policy_error_quark() && e->code == WK_POLICY_ERROR_INTERRUPTED))
    return FALSE;
  vlog("view %d: %s could not be loaded: %s", v->vid, uri ? uri : "its page", e->message);
  fail(v, "the page could not be loaded");
  return FALSE;
}

static void on_changed(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p, (void)data;
  mb_host_request_frame();
}

// the wheel's upright scroll over a page that gives it to the canvas (a page in a list of messages): the app's
static gboolean on_event(GtkEventControllerLegacy *c, GdkEvent *ev, gpointer data) {
  (void)c;
  View *v = find(GPOINTER_TO_INT(data));
  if (!v || strcmp(v->touch, "vertical") || gdk_event_get_event_type(ev) != GDK_SCROLL) return FALSE;
  double dx = 0, dy = 0;
  GdkScrollDirection d = gdk_scroll_event_get_direction(ev);
  if (d == GDK_SCROLL_SMOOTH) gdk_scroll_event_get_deltas(ev, &dx, &dy);
  else dy = d == GDK_SCROLL_UP || d == GDK_SCROLL_DOWN, dx = !dy;
  if (fabs(dy) < fabs(dx)) return FALSE;
  mb_app_scroll(ev);
  return TRUE;
}

static void make_web(View *v) {
  void *ucm = wk.webkit_user_content_manager_new();
  void *script = wk.webkit_user_script_new(
      "window.mbuiHost={post:function(t){window.webkit.messageHandlers.mbui.postMessage(String(t))}};", WK_TOP_FRAME,
      WK_AT_DOCUMENT_START, NULL, NULL);
  wk.webkit_user_content_manager_add_script(ucm, script);
  wk.webkit_user_script_unref(script);
  wk.webkit_user_content_manager_register_script_message_handler(ucm, "mbui", NULL);
  gpointer id = GINT_TO_POINTER(v->vid);
  g_signal_connect(ucm, "script-message-received::mbui", G_CALLBACK(on_said), id);
  v->web = g_object_new(wk.webkit_web_view_get_type(), "network-session", session, "user-content-manager", ucm, NULL);
  g_object_unref(ucm);
  wk.webkit_settings_set_enable_developer_extras(wk.webkit_web_view_get_settings(v->web), FALSE);
  GdkRGBA white = {1, 1, 1, 1};
  wk.webkit_web_view_set_background_color(v->web, &white);
  g_signal_connect(v->web, "decide-policy", G_CALLBACK(on_policy), id);
  g_signal_connect(v->web, "load-changed", G_CALLBACK(on_load), id);
  g_signal_connect(v->web, "load-failed", G_CALLBACK(on_load_failed), id);
  g_signal_connect(v->web, "notify::title", G_CALLBACK(on_changed), id);
  g_signal_connect(v->web, "notify::uri", G_CALLBACK(on_changed), id);
  v->box = g_object_new(box_get_type(), NULL);
  v->box->child = v->web;
  gtk_widget_set_parent(v->web, GTK_WIDGET(v->box));
  GtkEventController *events = gtk_event_controller_legacy_new();
  gtk_event_controller_set_propagation_phase(events, GTK_PHASE_CAPTURE);
  g_signal_connect(events, "event", G_CALLBACK(on_event), id);
  gtk_widget_add_controller(GTK_WIDGET(v->box), events);
  gtk_widget_set_visible(GTK_WIDGET(v->box), FALSE);
  // over the views opened before it
  gtk_fixed_put(GTK_FIXED(mb_app_under()), GTK_WIDGET(v->box), 0, 0);
  if (v->placed) apply_place(v);
  if (v->kind == 3) {
    char *url = g_strconcat(SITE_ROOT, v->start, NULL);
    wk.webkit_web_view_load_uri(v->web, url);
    g_free(url);
  } else {
    wk.webkit_web_view_load_html(v->web, v->html, NULL);
  }
  vlog("view %d: web view made", v->vid);
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  if (kind == 1) return player_open(arg);
  if (kind != 2 && kind != 3) return 0;
  if (!mb_app_under() || !wk_here()) return 0;
  View *v = g_new0(View, 1);
  v->vid = ++next_vid;
  v->kind = kind;
  v->loading = 1;
  v->scripts = g_ptr_array_new_with_free_func(g_free);
  v->covers = g_array_new(FALSE, FALSE, sizeof(double));
  strcpy(v->touch, "all");
  g_queue_init(&v->said);
  if (kind == 2) {
    v->html = utf8(arg);
    v->html_len = v->html ? (int)strlen(v->html) : 0;
    vlog("view %d: open web page (%d bytes)", v->vid, v->html_len);
  } else {
    v->start = utf8(arg);
    if (!v->start || !*v->start) g_free(v->start), v->start = g_strdup("/");
    vlog("view %d: open site at %s", v->vid, v->start);
  }
  View **end = &views;
  while (*end) end = &(*end)->next;
  *end = v;
  make_web(v);
  return v->vid;
}

void mb_host_view_place(int32_t vid, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, double r0, double r1, double r2, double r3, int32_t shown) {
  Player *pl = player_of(vid);
  if (pl) {
    // (drawn in the canvas where the app paints it: placed as told, on the same device pixels)
    double s = mb_app_scale() > 0 ? mb_app_scale() : 1, px0 = round(x * s), py0 = round(y * s);
    double bx = round(cx0 * s), by = round(cy0 * s);
    double k0 = fmax(0, r0) * s, k1 = fmax(0, r1) * s, k2 = fmax(0, r2) * s, k3 = fmax(0, r3) * s;
    if (shown)
      vlog("VIEWAT %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", vid, px0, py0,
           round((x + fmax(0, w)) * s) - px0, round((y + fmax(0, h)) * s) - py0, bx, by, round(cx1 * s),
           round(cy1 * s), fmax(fmax(k0, k1), fmax(k2, k3)), k0, k1, k2, k3);
    return;
  }
  View *v = find(vid);
  if (!v) return;
  int s = shown != 0;
  if (v->placed && v->shown == s && v->x == x && v->y == y && v->w == w && v->h == h && v->cx0 == cx0 &&
      v->cy0 == cy0 && v->cx1 == cx1 && v->cy1 == cy1 && v->r[0] == r0 && v->r[1] == r1 && v->r[2] == r2 &&
      v->r[3] == r3)
    return;
  v->placed = 1;
  v->shown = s;
  v->x = x, v->y = y, v->w = w, v->h = h;
  v->cx0 = cx0, v->cy0 = cy0, v->cx1 = cx1, v->cy1 = cy1;
  v->r[0] = r0, v->r[1] = r1, v->r[2] = r2, v->r[3] = r3;
  apply_place(v);
}

void mb_host_view_close(int32_t vid) {
  Player *pl = player_of(vid);
  if (pl) {
    player_close(pl);
    return;
  }
  View **p = &views;
  while (*p && (*p)->vid != vid) p = &(*p)->next;
  View *v = *p;
  if (!v) return;
  *p = v->next;
  // what the app had not answered ends broken off (the page sees a network error)
  while (v->reqs) {
    Req *q = v->reqs;
    v->reqs = q->next;
    if (q->answer) {
      body_put(q->answer, NULL, 0, -1);
    } else {
      GError *e = g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED, "the view closed");
      wk.webkit_uri_scheme_request_finish_error(q->request, e);
      g_error_free(e);
    }
    req_free(q);
  }
  if (v->web) {
    wk.webkit_web_view_stop_loading(v->web);
    g_signal_handlers_disconnect_matched(v->web, G_SIGNAL_MATCH_DATA, 0, 0, NULL, NULL, GINT_TO_POINTER(vid));
  }
  if (v->box) gtk_fixed_remove(GTK_FIXED(mb_app_under()), GTK_WIDGET(v->box));
  g_queue_clear_full(&v->said, g_free);
  g_ptr_array_unref(v->scripts);
  g_array_unref(v->covers);
  g_clear_pointer(&v->still, g_bytes_unref);
  g_free(v->html);
  g_free(v->start);
  vlog("view %d: closed", vid);
  g_free(v);
}

void mb_host_view_control(int32_t vid, int32_t op, double value) {
  Player *pl = player_of(vid);
  if (pl) {
    player_control(pl, op, value);
    return;
  }
  View *v = find(vid);
  if (v && op == 21) {
    grab_page(v);
    return;
  }
  if (!v || v->kind != 3 || !v->web) return;
  switch (op) {
    case 5: if (wk.webkit_web_view_can_go_back(v->web)) wk.webkit_web_view_go_back(v->web); break;
    case 6: if (wk.webkit_web_view_can_go_forward(v->web)) wk.webkit_web_view_go_forward(v->web); break;
    case 7: wk.webkit_web_view_reload(v->web); break;
    // laid out at its rect over the scale, drawn at the scale
    case 8:
      if (value > 0) v->zoom = value, wk.webkit_web_view_set_zoom_level(v->web, value), scroll_band(v);
      break;
  }
}

int32_t mb_host_view_info(int32_t vid, double *out) {
  for (int i = 0; i < 10; i++) out[i] = 0;
  out[0] = -1;
  Player *pl = player_of(vid);
  if (pl) {
    // (as it was last looked at: what the app was told of, player_stood)
    if (!pl->stood_told) player_stood(pl);
    memcpy(out, pl->stood, sizeof pl->stood);
    return pl->stood_state;
  }
  View *v = find(vid);
  if (!v) return -1;
  if (v->kind == 2) out[5] = v->html_len;
  out[6] = v->loaded;
  return v->failed ? -1 : v->loaded ? 1 : 0;
}

// a player's reads, the app answering them
int32_t mb_host_view_read_next(int32_t id, double *out) {
  Player *pl = player_of(id);
  return pl ? player_read_next(pl, out) : 0;
}
void mb_host_view_read_answer(int32_t id, int32_t req, moonbit_bytes_t data, double total, int32_t more) {
  Player *pl = player_of(id);
  if (pl) player_read_answer(pl, req, data, total, more);
}

// a grab, a page's (its PNG) or a player's (its frame shown, a JPEG; a frame of its file, a PNG): how it stands (what
// 2); a player's frames' times (what 1), once read
moonbit_string_t mb_host_view_text(int32_t vid, int32_t what) {
  Player *pl = player_of(vid);
  View *v = pl ? NULL : find(vid);
  if (pl && what == 1) return mstr(pl->frames ? pl->frames : "");
  if ((!pl && !v) || what != 2) return moonbit_make_string_raw(0);
  char n[16];
  snprintf(n, sizeof n, "%d", pl ? pl->still_state : v->still_state);
  return mstr(n);
}
int32_t mb_host_view_text_known(int32_t vid, int32_t what) {
  Player *pl = player_of(vid);
  if (pl && what == 1) return pl->frames != NULL;
  return (pl || find(vid)) && what == 2;
}
moonbit_bytes_t mb_host_view_still(int32_t vid) {
  Player *pl = player_of(vid);
  if (pl) {
    gsize n = pl->still ? g_bytes_get_size(pl->still) : 0;
    moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
    if (n) memcpy(out, g_bytes_get_data(pl->still, NULL), n);
    g_clear_pointer(&pl->still, g_bytes_unref);
    if (pl->still_state == 2) pl->still_state = 0;
    return out;
  }
  View *v = find(vid);
  gsize n = v && v->still ? g_bytes_get_size(v->still) : 0;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(out, g_bytes_get_data(v->still, NULL), n);
  if (v) {
    g_clear_pointer(&v->still, g_bytes_unref);
    if (v->still_state == 2) v->still_state = 0;
  }
  return out;
}

// What the app tells a view beyond its controls (host_native.mbt view_tell): a script for its page, who takes the
// mouse on it ("through": the canvas, "vertical": the canvas its wheel's upright scroll), where the app draws what
// takes a press over it (WebKit waits on a request as long as the app takes: no head wait here).
void mb_host_view_tell(int32_t vid, int32_t what, moonbit_string_t text) {
  View *v = find(vid);
  if (!v) return;
  if (what == 5) {
    // raised over all the others (the app paints it after them): last in the list and among the under's children
    View **p = &views;
    while (*p != v) p = &(*p)->next;
    *p = v->next;
    v->next = NULL;
    View **end = &views;
    while (*end) end = &(*end)->next;
    *end = v;
    if (v->box) gtk_widget_insert_before(GTK_WIDGET(v->box), mb_app_under(), NULL);
    // how they are stacked, the lowest first (scripts/host_contract.sh HOST views: as the app told, VIEWSTACKTOLD)
    GString *line = g_string_new("VIEWSTACK");
    for (View *o = views; o; o = o->next) g_string_append_printf(line, " %d", o->vid);
    vlog("%s", line->str);
    g_string_free(line, TRUE);
    return;
  }
  char *t = utf8(text);
  if (!t) return;
  if (what == 1) {
    g_ptr_array_add(v->scripts, t);
    run_scripts(v);
    return;
  }
  if (what == 2) {
    g_strlcpy(v->touch, t, sizeof v->touch);
    char *sp = strchr(v->touch, ' ');
    if (sp) *sp = 0;
  } else if (what == 3) {
    // a site's settings: how much of an answer may wait to be read (its head_wait_ms not: WebKit waits on a request
    // as long as the app takes, as WebView2 does, and nothing here is done a time later)
    jv o = {0};
    const char *p = t;
    if (jparse(&p, &o, 0)) v->backlog = jnum(&o, "backlog", v->backlog);
    jv_free(&o);
  } else if (what == 4) {
    g_array_set_size(v->covers, 0);
    char *s = t, *end = NULL;
    for (double d = g_ascii_strtod(s, &end); end != s; d = g_ascii_strtod(s, &end)) {
      g_array_append_val(v->covers, d);
      s = end;
    }
  }
  g_free(t);
}

// ---- a site's API ----

moonbit_string_t mb_host_view_site_next(int32_t vid) {
  View *v = find(vid);
  if (!v || g_queue_is_empty(&v->said)) return moonbit_make_string_raw(0);
  char *e = g_queue_pop_head(&v->said);
  moonbit_string_t out = mstr(e);
  g_free(e);
  return out;
}

moonbit_bytes_t mb_host_view_site_body(int32_t vid, int32_t req) {
  Req *q = req_of(find(vid), req, 0);
  gsize n = q ? g_bytes_get_size(q->body) : 0;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(out, g_bytes_get_data(q->body, NULL), n);
  return out;
}

// [[k,v]…] as JSON text (the app's head) as the answer's headers, its Content-Type its type
static void head_pairs(const char *json, SoupMessageHeaders *hs, char **type) {
  jv head = {0};
  const char *p = json;
  if (json && jparse(&p, &head, 0) && head.kind == 'a')
    for (int i = 0; i < head.n; i++) {
      const jv *kv = &head.at[i];
      if (kv->kind != 'a' || kv->n < 2 || kv->at[0].kind != 's' || kv->at[1].kind != 's') continue;
      if (!g_ascii_strcasecmp(kv->at[0].s, "Content-Type")) {
        g_free(*type);
        *type = g_strdup(kv->at[1].s);
      }
      soup_message_headers_append(hs, kv->at[0].s, kv->at[1].s);
    }
  jv_free(&head);
}

void mb_host_view_site_head(int32_t vid, int32_t req, int32_t status, moonbit_string_t headers) {
  View *v = find(vid);
  Req *q = req_of(v, req, 0);
  if (!q || q->headed) return;
  q->headed = 1;
  // a redirect's status as Android's: 200
  if (status < 200 || status > 599 || (status >= 300 && status <= 399)) status = 200;
  SoupMessageHeaders *hs = soup_message_headers_new(SOUP_MESSAGE_HEADERS_RESPONSE);
  char *json = utf8(headers), *type = NULL;
  head_pairs(json, hs, &type);
  g_free(json);
  // its body as the app sends it: the page has each part as it comes (an event stream's events as they are sent)
  q->answer = g_object_new(body_get_type(), NULL);
  q->answer->vid = vid, q->answer->rid = req;
  void *r = wk.webkit_uri_scheme_response_new(G_INPUT_STREAM(q->answer), -1);
  wk.webkit_uri_scheme_response_set_status(r, (guint)status, NULL);
  if (type) wk.webkit_uri_scheme_response_set_content_type(r, type);
  wk.webkit_uri_scheme_response_set_http_headers(r, hs);  // (its own now)
  wk.webkit_uri_scheme_request_finish_with_response(q->request, r);
  g_object_unref(r);
  g_free(type);
}

void mb_host_view_site_chunk(int32_t vid, int32_t req, moonbit_bytes_t data) {
  Req *q = req_of(find(vid), req, 0);
  if (!q || !q->answer) return;
  gsize waits = body_put(q->answer, data, (size_t)Moonbit_array_length(data), 0);
  // read too slowly (more of it waiting than the app lets): said, once (the app stops it with its words for that)
  if (v_backlog(vid) > 0 && waits > v_backlog(vid) && !q->slow) {
    q->slow = 1;
    say_req(find(vid), "slow", req);
  }
}

// The request answered to its end, or let go broken off (`error`: a page saying why where nothing was sent yet, as
// Windows' 502; else the page sees its answer cut).
void mb_host_view_site_end(int32_t vid, int32_t req, moonbit_string_t error) {
  View *v = find(vid);
  Req *q = req_of(v, req, 1);
  if (!q) return;
  char *why = utf8(error);
  if (!q->headed) {
    const char *msg = why && *why ? why : "no answer";
    respond(q->request, 502, "text/plain; charset=utf-8", msg, strlen(msg));
  } else {
    if (why && *why) vlog("view %d: request %d broke off: %s", vid, req, why);
    body_put(q->answer, NULL, 0, why && *why ? -1 : 1);
  }
  g_free(why);
  req_free(q);
}

moonbit_string_t mb_host_view_site_state(int32_t vid) {
  View *v = find(vid);
  if (!v || v->kind != 3) return moonbit_make_string_raw(0);
  char *path = NULL;
  const char *title = NULL;
  int back = 0, fwd = 0;
  if (v->web) {
    const char *uri = wk.webkit_web_view_get_uri(v->web);
    if (uri && *uri) {
      path = path_of(uri);
      if (!path) path = g_strdup(uri);
    }
    title = wk.webkit_web_view_get_title(v->web);
    back = wk.webkit_web_view_can_go_back(v->web);
    fwd = wk.webkit_web_view_can_go_forward(v->web);
  }
  GString *e = g_string_new("{\"path\":");
  jquote(e, path ? path : v->start);
  g_string_append_printf(e, ",\"back\":%s,\"forward\":%s,\"loading\":%s,\"title\":", back ? "true" : "false",
                         fwd ? "true" : "false", v->loading ? "true" : "false");
  jquote(e, title ? title : "");
  g_string_append_c(e, '}');
  g_free(path);
  moonbit_string_t out = mstr(e->str);
  g_string_free(e, TRUE);
  return out;
}

void mb_host_view_site_load(int32_t vid, moonbit_string_t path) {
  View *v = find(vid);
  if (!v || v->kind != 3 || !v->web) return;
  char *p = utf8(path);
  char *url = g_strconcat(SITE_ROOT, p && *p ? p : "/", NULL);
  wk.webkit_web_view_load_uri(v->web, url);
  g_free(url);
  g_free(p);
}

// ---------------------------------------------------------------------------
// For the window (linux_app.c)

int mb_views_webkit(void) { return wk_state > 0; }

// whether the app draws something that takes a press over `v` at (x, y) (view_tell 4)
static int covered_at(View *v, double x, double y) {
  const double *r = (const double *)v->covers->data;
  for (guint j = 0; j + 3 < v->covers->len; j += 4)
    if (x >= r[j] && x < r[j + 2] && y >= r[j + 1] && y < r[j + 3]) return 1;
  return 0;
}

// Whether a press at (x, y), points in the canvas, is a view's: one shown there that takes the mouse, where the app
// draws nothing that takes it over the view (the canvas holds no press there, so the view under it has it).
int mb_views_pass_through(double x, double y) {
  int at = 0;
  for (View *v = views; v; v = v->next) {
    if (!v->shown || !v->placed || !v->web || !strcmp(v->touch, "through") || covered_at(v, x, y)) continue;
    double x0 = fmax(v->cx0, v->x), y0 = fmax(v->cy0, v->y);
    double x1 = fmin(v->cx1, v->x + v->w), y1 = fmin(v->cy1, v->y + v->h);
    if (x >= x0 && x < x1 && y >= y0 && y < y1) at = 1;
  }
  return at;
}

// The window's scale changed: each view placed again, on the new scale's device pixels.
void mb_views_rescale(void) {
  for (View *v = views; v; v = v->next)
    if (v->placed) apply_place(v);
}

// What the app awaits of the views, told as it came (f: host_native.mbt's set_outside; NULL: dropped).
void mb_views_tell(mb_outside_fn f) {
  // (each player looked at: what happened since, a frame asked for by it, may have changed how it stands)
  for (Player *p = players; p; p = p->next) player_stood(p);
  while (!g_queue_is_empty(&stoods)) {
    int id = GPOINTER_TO_INT(g_queue_pop_head(&stoods));
    if (f) f(MB_OUTSIDE_STOOD, id, 0);
  }
  while (!g_queue_is_empty(&told)) {
    int id = GPOINTER_TO_INT(g_queue_pop_head(&told)), state = GPOINTER_TO_INT(g_queue_pop_head(&told));
    if (f) f(MB_OUTSIDE_VIEW, id, state);
  }
  while (!g_queue_is_empty(&grabs)) {
    int id = GPOINTER_TO_INT(g_queue_pop_head(&grabs)), state = GPOINTER_TO_INT(g_queue_pop_head(&grabs));
    if (f) f(MB_OUTSIDE_GRAB, id, state);
  }
}
