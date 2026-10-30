// Linux host: a GTK 4 window (Wayland or X11, as GTK finds the session) whose canvas is a GtkGLArea the app draws in
// with OpenGL ES 3 (linux_render.c), over the native views (linux_views.c: web pages, shown through it); frames from GTK's frame clock, asked for only while the app has something to
// draw; input from the area's events, and the input method (IBus, Fcitx: GTK's) through a GtkIMContext while a field
// has the focus. The window keeps the system's title bar (GTK's own on GNOME's Wayland, the window manager's where it
// draws them): none of its buttons in the app's top row. A program that is an app (MBUI_APP_ID) runs once for its
// person, put away to its icon among the desktop's as its window closes (linux_life.h).
#include <sys/resource.h>
#include <epoxy/gl.h>
#include <gtk/gtk.h>
#include <locale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "linux.h"
#include "post.h"
#include "done_watch.h"

mb_callbacks mb_cb;

// Back (host_native.mbt `set_back`): a mouse's back button and Alt+Left, while the app takes it.
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);
static mb_back_fn back_cb;
static int back_on;
static int go_back(void) {
  if (!back_cb || !back_on) return 0;
  back_cb(2, 0, 1, 0);
  return 1;
}

static GtkWidget *win, *area, *under;  // the window, its canvas, the native views' GtkFixed under it
static GtkIMContext *im;
static GtkEventController *keys;
static int want_frame;
static guint tick_id;
static double wake_at = -1;  // mb_now_ms() of the earliest wake_after, or -1
static double scale = 1;
static int fb_pw, fb_ph;          // the area's framebuffer in pixels, as GTK last sized it
static double frame_w, frame_h;   // the last frame's size in points
static int ime_active;
static double caret[4];  // x, y, w, h in points, from set_ime
static char *ime_words;  // the field's words (UTF-8) and its selection's ends in them, for the input method
static int ime_sel_a, ime_sel_b;
static int marked_len;
static const char *script;
static const char *shot_dir;
// the window as the app asks for it (@hostapi.window_setup), the pointer's shape (@hostapi.set_cursor), whether the
// right button is down
static double setup_w, setup_h, setup_min_w, setup_min_h;
static int right_down, left_down;
static int frames_drawn;
static mb_outside_fn outside_cb;  // who is told as what the host does for the app is done (mb_host_set_outside)
static void (*state_cb)(int32_t);  // the app in front or not (@hostapi.set_app_state)
// the last press, for a move of the window it starts (mb_host_window_drag)
static GdkDevice *press_device;
static double press_x, press_y;  // in the surface's coordinates
static guint32 press_time;
static int press_button;
// an inset window (@hostapi.window_setup's inset): no title bar of the system's, the app's top row is it
static int setup_inset;
// the last press that moved the window: when and where, for the second of a double click there
static guint32 drag_time;
static double drag_x, drag_y;

double mb_now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static moonbit_string_t mstr(const char *s) {
  glong n = 0;
  gunichar2 *u = s ? g_utf8_to_utf16(s, -1, NULL, &n, NULL) : NULL;
  moonbit_string_t out = moonbit_make_string_raw(u ? (int32_t)n : 0);
  if (u && n) memcpy(out, u, (size_t)n * 2);
  g_free(u);
  return out;
}

// MoonBit's words as UTF-8 (a lone surrogate as U+FFFD)
static char *utf8(moonbit_string_t s) {
  int32_t n = Moonbit_array_length(s);
  GString *o = g_string_sized_new((gsize)n * 3 + 1);
  for (int32_t i = 0; i < n; i++) {
    gunichar c = s[i];
    if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000)
      c = 0x10000 + ((c - 0xD800) << 10) + (s[++i] - 0xDC00);
    else if (c >= 0xD800 && c < 0xE000)
      c = 0xFFFD;
    g_string_append_unichar(o, c);
  }
  return g_string_free(o, FALSE);
}

static void send_text(int kind, const char *s, int a, int b) { mb_cb.text(kind, mstr(s), a, b); }

static void run_script_step(int step);
double mb_host_mem_bytes(void);

// ---- frames: GTK's frame clock ticks while one is wanted, and each tick has the area drawn ----

static void canvas_queue_render(GtkWidget *w);

static gboolean on_tick(GtkWidget *w, GdkFrameClock *clock, gpointer data) {
  (void)w, (void)clock, (void)data;
  if (want_frame) {
    canvas_queue_render(area);
    return G_SOURCE_CONTINUE;
  }
  tick_id = 0;
  return G_SOURCE_REMOVE;
}

static void schedule(void) {
  want_frame = 1;
  if (!tick_id && area) tick_id = gtk_widget_add_tick_callback(area, on_tick, NULL, NULL);
}

// asked for from any thread (an image decoded, a message posted): its frame on the main thread
static gint waking;
static gboolean wake_idle(gpointer data) {
  (void)data;
  g_atomic_int_set(&waking, 0);
  schedule();
  return G_SOURCE_REMOVE;
}

void mb_app_wake(void) {
  if (g_atomic_int_compare_and_exchange(&waking, 0, 1)) g_idle_add_full(G_PRIORITY_HIGH_IDLE, wake_idle, NULL, NULL);
}

// A message posted from outside the frames (post.h), on whatever thread: a frame asked for.
static void mb_post_wake(void) { mb_app_wake(); }

double mb_app_scale(void) { return scale; }

void *mb_app_under(void) { return under; }

// The canvas: a GtkGLArea that holds no press where a native view shows (linux_views.c): the view under it has it.
// Drawn at the window's own scale, a fractional one too (GNOME's 125%, 150%, at which GTK draws the window:
// gdk_surface_get_scale): GtkGLArea makes its picture at the whole scale above that (2 for 1.25), which GTK then
// shrinks as it draws the window, softer than the rest of it and over twice the pixels. So the area's GL context is
// kept, but its picture is the canvas's own: a texture of the surface's scale drawn into through a framebuffer of its
// own (on_render), handed to GTK as a GdkGLTexture, which it draws pixel for pixel; upside down as GL draws, flipped
// back as GtkGLArea does. A texture GTK still holds is not drawn into; the last one drawn is drawn again when the
// window is drawn for something else.
typedef struct {
  GLuint id;
  int w, h;
  int held;     // GTK has it (its GdkTexture not released yet)
  GLsync sync;  // the fence GTK waited on for it, let go as it is drawn into again
} CanvasTex;

typedef struct {
  GtkGLArea parent;
  GLuint fbo;
  GPtrArray *texs;    // CanvasTex, made as needed, kept for drawing into again
  GdkTexture *last;   // the picture drawn last
  int needs_render;   // a frame asked for (canvas_queue_render), or none drawn yet
} Canvas;
typedef struct {
  GtkGLAreaClass parent;
} CanvasClass;
G_DEFINE_TYPE(Canvas, canvas, GTK_TYPE_GL_AREA)

static gboolean on_render(GtkGLArea *a, GdkGLContext *c, gpointer data);
static void canvas_resized(int pw, int ph);

static gboolean canvas_contains(GtkWidget *w, double x, double y) {
  return !mb_views_pass_through(x, y) && GTK_WIDGET_CLASS(canvas_parent_class)->contains(w, x, y);
}

// a frame of the canvas asked for: drawn as GTK next draws the window
static void canvas_queue_render(GtkWidget *w) {
  ((Canvas *)w)->needs_render = 1;
  gtk_widget_queue_draw(w);
}

static void canvas_tex_released(gpointer data) { ((CanvasTex *)data)->held = 0; }

// the window's scale now, fractional ones too
static double canvas_scale(GtkWidget *w) {
  GtkNative *n = gtk_widget_get_native(w);
  GdkSurface *s = n ? gtk_native_get_surface(n) : NULL;
  double k = s ? gdk_surface_get_scale(s) : 0;
  return k > 0 ? k : gtk_widget_get_scale_factor(w);
}

static void canvas_snapshot(GtkWidget *w, GtkSnapshot *snap) {
  Canvas *c = (Canvas *)w;
  GdkGLContext *ctx = gtk_gl_area_get_context(GTK_GL_AREA(w));
  int lw = gtk_widget_get_width(w), lh = gtk_widget_get_height(w);
  if (!ctx || gtk_gl_area_get_error(GTK_GL_AREA(w))) {
    GTK_WIDGET_CLASS(canvas_parent_class)->snapshot(w, snap);
    return;
  }
  if (lw <= 0 || lh <= 0) return;
  double k = canvas_scale(w);
  int pw = (int)lround(lw * k), ph = (int)lround(lh * k);
  if (c->last && (gdk_texture_get_width(c->last) != pw || gdk_texture_get_height(c->last) != ph)) c->needs_render = 1;
  if (c->needs_render || !c->last) {
    gtk_gl_area_make_current(GTK_GL_AREA(w));
    CanvasTex *t = NULL;
    for (guint i = 0; i < c->texs->len && !t; i++) {
      CanvasTex *u = g_ptr_array_index(c->texs, i);
      if (!u->held) t = u;
    }
    if (!t) {
      t = g_new0(CanvasTex, 1);
      glGenTextures(1, &t->id);
      g_ptr_array_add(c->texs, t);
    }
    if (t->sync) glDeleteSync(t->sync), t->sync = NULL;
    glBindTexture(GL_TEXTURE_2D, t->id);
    if (t->w != pw || t->h != ph) {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, pw, ph, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      t->w = pw, t->h = ph;
    }
    if (!c->fbo) glGenFramebuffers(1, &c->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->id, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      fprintf(stderr, "mbui: the canvas's framebuffer is not complete (%dx%d)\n", pw, ph);
      return;
    }
    canvas_resized(pw, ph);
    c->needs_render = 0;
    on_render(GTK_GL_AREA(w), ctx, NULL);
    glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
    GdkGLTextureBuilder *b = gdk_gl_texture_builder_new();
    gdk_gl_texture_builder_set_context(b, ctx);
    gdk_gl_texture_builder_set_id(b, t->id);
    gdk_gl_texture_builder_set_width(b, pw);
    gdk_gl_texture_builder_set_height(b, ph);
    gdk_gl_texture_builder_set_format(b, GDK_MEMORY_R8G8B8A8_PREMULTIPLIED);
    // (GTK draws it once GL is done with it: a fence, which OpenGL ES 3 has)
    t->sync = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    gdk_gl_texture_builder_set_sync(b, t->sync);
    t->held = 1;
    g_clear_object(&c->last);
    c->last = gdk_gl_texture_builder_build(b, canvas_tex_released, t);
    g_object_unref(b);
  }
  gtk_snapshot_save(snap);
  gtk_snapshot_translate(snap, &GRAPHENE_POINT_INIT(0, lh));
  gtk_snapshot_scale(snap, 1, -1);
  gtk_snapshot_append_texture(snap, c->last, &GRAPHENE_RECT_INIT(0, 0, lw, lh));
  gtk_snapshot_restore(snap);
}

// its scale changing (to another monitor's, the desktop's setting changed): drawn anew at it
static void canvas_on_scale(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p;
  canvas_queue_render(data);
}

static void canvas_realize(GtkWidget *w) {
  GTK_WIDGET_CLASS(canvas_parent_class)->realize(w);
  GdkSurface *s = gtk_native_get_surface(gtk_widget_get_native(w));
  if (s) g_signal_connect_object(s, "notify::scale", G_CALLBACK(canvas_on_scale), w, 0);
  ((Canvas *)w)->needs_render = 1;
}

// its context let go: what was made in it with it (a texture GTK holds yet is left to GTK's release of it)
static void canvas_unrealize(GtkWidget *w) {
  Canvas *c = (Canvas *)w;
  if (gtk_gl_area_get_context(GTK_GL_AREA(w))) {
    gtk_gl_area_make_current(GTK_GL_AREA(w));
    if (c->fbo) glDeleteFramebuffers(1, &c->fbo);
    for (guint i = 0; i < c->texs->len; i++) {
      CanvasTex *t = g_ptr_array_index(c->texs, i);
      glDeleteTextures(1, &t->id);
      if (t->sync) glDeleteSync(t->sync);
    }
  }
  c->fbo = 0;
  g_clear_object(&c->last);
  g_ptr_array_set_size(c->texs, 0);
  GTK_WIDGET_CLASS(canvas_parent_class)->unrealize(w);
}

static void canvas_class_init(CanvasClass *k) {
  GTK_WIDGET_CLASS(k)->contains = canvas_contains;
  GTK_WIDGET_CLASS(k)->snapshot = canvas_snapshot;
  GTK_WIDGET_CLASS(k)->realize = canvas_realize;
  GTK_WIDGET_CLASS(k)->unrealize = canvas_unrealize;
}

static void canvas_init(Canvas *c) { c->texs = g_ptr_array_new(); }

static void device_tell(mb_outside_fn tell);  // linux_device.h: the clipboard's reads done
static void pick_tell(mb_outside_fn tell);    // the files picked
static void update_tell(mb_outside_fn tell);  // linux_update.h: how an update goes
void mb_host_set_cursor(int32_t kind);

// The area's context made current again for what is drawn: once WebKit is in the process (linux_views.c), its own GL
// can leave another context current, or none, behind GDK's back, and GDK's make_current, which goes by the one it made
// current last, would do nothing.
static void gl_current(void) {
  if (!mb_views_webkit()) return;
  gdk_gl_context_clear_current();
  gtk_gl_area_make_current(GTK_GL_AREA(area));
}

static gboolean on_render(GtkGLArea *a, GdkGLContext *c, gpointer data) {
  (void)c, (void)data;
  want_frame = 0;
  gl_current();
  // what was decoded meanwhile made textures, then told: the app finds them ready
  mb_images_upload();
  mb_streams_upload();
  mb_players_upload();
  mb_images_tell(outside_cb);
  device_tell(outside_cb);
  pick_tell(outside_cb);
  update_tell(outside_cb);
  mb_views_tell(outside_cb);
  int w = gtk_widget_get_width(GTK_WIDGET(a)), h = gtk_widget_get_height(GTK_WIDGET(a));
  if (w <= 0 || h <= 0 || fb_pw <= 0 || fb_ph <= 0) return TRUE;
  double was = scale;
  scale = fb_pw / (double)w;
  if (scale != was) mb_views_rescale();
  frame_w = w;
  frame_h = h;
  mb_text_set_scale(scale);
  mb_render_target(fb_pw, fb_ph, w, h, scale);
  GdkFrameClock *clock = gtk_widget_get_frame_clock(GTK_WIDGET(a));
  double now = clock ? gdk_frame_clock_get_frame_time(clock) / 1000.0 : mb_now_ms();
  mb_cb.frame(w, h, scale, now);
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
  if (want_frame) schedule();
  return TRUE;
}

// the framebuffer's size in pixels (the canvas's, at the window's scale), as it changes
static void canvas_resized(int pw, int ph) {
  if (pw == fb_pw && ph == fb_ph) return;
  fb_pw = pw;
  fb_ph = ph;
  schedule();
}

static void on_realize(GtkWidget *w, gpointer data) {
  (void)data;
  gtk_gl_area_make_current(GTK_GL_AREA(w));
  GError *e = gtk_gl_area_get_error(GTK_GL_AREA(w));
  if (e) {
    fprintf(stderr, "mbui: no OpenGL ES 3 context: %s\n", e->message);
    exit(1);
  }
  mb_render_setup();
  schedule();
}

// maximized or back, full screen or back: the app's top row and its buttons as it now is
static void on_window_state(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p, (void)data;
  schedule();
}

// ---- the input method ----

static void ime_place(void) {
  if (!ime_active) return;
  GdkRectangle r = {(int)lround(caret[0]), (int)lround(caret[1]), (int)lround(caret[2] > 1 ? caret[2] : 1),
                    (int)lround(caret[3])};
  gtk_im_context_set_cursor_location(im, &r);
}

static void on_commit(GtkIMContext *c, const char *s, gpointer data) {
  (void)c, (void)data;
  marked_len = 0;
  if (!ime_active) return;
  // control characters come as keys (Enter, Backspace) or shortcuts
  if ((unsigned char)s[0] < 0x20 && !s[1]) return;
  send_text(0, s, 0, 0);
}

static void on_preedit(GtkIMContext *c, gpointer data) {
  (void)data;
  char *s = NULL;
  int cursor = 0;
  gtk_im_context_get_preedit_string(c, &s, NULL, &cursor);
  // the cursor in the composition: characters there, UTF-16 units here
  glong n = 0, at = 0;
  gunichar2 *u = g_utf8_to_utf16(s, -1, NULL, &n, NULL);
  const char *p = s;
  for (int i = 0; i < cursor && *p; i++, p = g_utf8_next_char(p)) at += g_utf8_get_char(p) >= 0x10000 ? 2 : 1;
  g_free(u);
  marked_len = (int)n;
  send_text(1, s, (int)at, 0);
  g_free(s);
  ime_place();
}

static void on_preedit_end(GtkIMContext *c, gpointer data) {
  (void)c, (void)data;
  if (marked_len) send_text(1, "", 0, 0);
  marked_len = 0;
}

static gboolean on_surrounding(GtkIMContext *c, gpointer data) {
  (void)data;
  const char *w = ime_words ? ime_words : "";
  gtk_im_context_set_surrounding_with_selection(c, w, -1, ime_sel_b, ime_sel_a);
  return TRUE;
}

// the input method deleting round the caret (n characters from `offset`): the field's Backspace or Delete
static gboolean on_delete_surrounding(GtkIMContext *c, int offset, int n, gpointer data) {
  (void)c, (void)data;
  int before = offset < 0 ? -offset : 0, after = offset + n > 0 ? offset + n : 0;
  if (before > n) before = n;
  mb_cb.text(4, moonbit_make_string_raw(0), before, after);
  return TRUE;
}

// ---- the clipboard ----

static void paste_done(GObject *src, GAsyncResult *res, gpointer data) {
  (void)data;
  char *s = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(src), res, NULL);
  if (s && *s) {
    GString *t = g_string_new(NULL);
    for (const char *p = s; *p; p++)
      if (!(p[0] == '\r' && p[1] == '\n')) g_string_append_c(t, *p);
    send_text(8, t->str, 0, 0);  // put in as typed, a step of its own to undo
    g_string_free(t, TRUE);
  }
  g_free(s);
}

static int mods_of(GdkModifierType m) {
  return ((m & GDK_SHIFT_MASK) ? 1 : 0) | ((m & GDK_CONTROL_MASK) ? 2 : 0) | ((m & GDK_ALT_MASK) ? 4 : 0) |
         ((m & GDK_SUPER_MASK) ? 8 : 0);
}

// the device beyond the window (device.mbt): a key catcher's keys, the clipboard read
#include "linux_device.h"

// ---- keys ----

static gboolean on_key(GtkEventControllerKey *k, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  (void)k, (void)keycode, (void)data;
  int mods = mods_of(state);
  // a key catcher's focus (linux_device.h): its keys (a composition under way keeps them)
  if (key_catching && ime_active && marked_len == 0 && catch_key(keyval, mods)) return TRUE;
  if ((mods & 4) && !(mods & 2) && keyval == GDK_KEY_Left && go_back()) return TRUE;
  // Alt+Right: forward, the app's key (key_forward)
  if ((mods & 4) && !(mods & 2) && keyval == GDK_KEY_Right) {
    mb_cb.key(40, 0);
    return TRUE;
  }
  if (mods & 2) {
    int ch = key_char(keyval);
    switch (ch) {
      case 'a': mb_cb.key(12, mods); return TRUE;
      case 'c': mb_cb.key(13, mods); return TRUE;
      case 'x': mb_cb.key(14, mods); return TRUE;
      case 'v': {
        // files or a picture on it: the app's Ctrl+V (1000 + v), which reads the clipboard for it (@hostapi.clip_read),
        // as a page's paste takes them as files; else its words
        GdkContentFormats *f = clip_formats();
        int app = gdk_content_formats_contain_gtype(f, GDK_TYPE_FILE_LIST) ||
                  gdk_content_formats_contain_gtype(f, GDK_TYPE_TEXTURE);
        gdk_content_formats_unref(f);
        if (app) mb_cb.key(1000 + 'v', mods);
        else gdk_clipboard_read_text_async(gtk_widget_get_clipboard(area), NULL, paste_done, NULL);
        return TRUE;
      }
    }
    // any other Ctrl key with a character: the app's shortcut (1000 + the character, lower case)
    if (ch && !named_key(keyval)) {
      mb_cb.key(1000 + ch, mods);
      return TRUE;
    }
  }
  int code = named_key(keyval);
  // without a field to type in, these scroll the list under the pointer
  if ((code == 15 || code == 16) && ime_active) code = 0;
  if (code) {
    mb_cb.key(code, mods);
    return TRUE;
  }
  // a character with no field to take it (Space, a letter): the app's, as 1000 + it
  if (!ime_active) {
    int ch = key_char(keyval);
    if (ch) {
      mb_cb.key(1000 + ch, mods);
      return TRUE;
    }
  }
  return FALSE;
}

// ---- the pointer ----

// an event's place in the area's points
static void area_point(GdkEvent *ev, double *x, double *y) {
  double sx = 0, sy = 0, nx = 0, ny = 0;
  gdk_event_get_position(ev, &sx, &sy);
  GtkNative *native = gtk_widget_get_native(area);
  gtk_native_get_surface_transform(native, &nx, &ny);
  graphene_point_t p = GRAPHENE_POINT_INIT((float)(sx - nx), (float)(sy - ny)), out;
  if (gtk_widget_compute_point(GTK_WIDGET(native), area, &p, &out)) {
    *x = out.x;
    *y = out.y;
  } else {
    *x = sx - nx;
    *y = sy - ny;
  }
}

// A wheel's notch: 53 points, as a browser on Linux scrolls by one (Chromium's three lines), eased in by the app
// (phase 4); a touchpad's as it comes, in the surface's points (phase 1, the fingers on it).
#define NOTCH 53.333

static void scroll(GdkEvent *ev, double x, double y) {
  int mods = mods_of(gdk_event_get_modifier_state(ev));
  GdkScrollDirection d = gdk_scroll_event_get_direction(ev);
  double dx = 0, dy = 0;
  int phase = 4;
  if (d == GDK_SCROLL_SMOOTH) {
    gdk_scroll_event_get_deltas(ev, &dx, &dy);
    if (gdk_scroll_event_get_unit(ev) == GDK_SCROLL_UNIT_SURFACE) {
      phase = 1;
    } else {
      dx *= NOTCH;
      dy *= NOTCH;
    }
  } else {
    dy = d == GDK_SCROLL_UP ? -NOTCH : d == GDK_SCROLL_DOWN ? NOTCH : 0;
    dx = d == GDK_SCROLL_LEFT ? -NOTCH : d == GDK_SCROLL_RIGHT ? NOTCH : 0;
  }
  // Shift turns a mouse's wheel sideways, as the system's own widgets do
  if (phase == 4 && (mods & 1) && dx == 0) {
    dx = dy;
    dy = 0;
  }
  if (dx != 0 || dy != 0) mb_cb.wheel(x, y, dx, dy, phase | (mods << 4));
}

// The touches: the first as the pointer, the second as the second finger (4 down, 5 moved, 6 up; the first lifted before it, 8), any more none.
static GdkEventSequence *touch1, *touch2;

static void touch(GdkEvent *ev, GdkEventType t, double x, double y) {
  GdkEventSequence *s = gdk_event_get_event_sequence(ev);
  int end = t == GDK_TOUCH_END || t == GDK_TOUCH_CANCEL;
  if (t == GDK_TOUCH_BEGIN) {
    if (!touch1) {
      touch1 = s;
      gtk_widget_grab_focus(area);
      mb_cb.pointer(0, x, y, 0);
    } else if (!touch2) {
      touch2 = s;
      mb_cb.pointer(4, x, y, 0);
    }
    return;
  }
  if (s == touch1) {
    // (the first lifted while a second is down: 8, where it was, the second the first from here)
    if (end && touch2) {
      mb_cb.pointer(8, x, y, 0);
      touch1 = touch2;
      touch2 = NULL;
      return;
    }
    mb_cb.pointer(end ? 2 : 1, x, y, 0);
    if (end) touch1 = NULL;
  } else if (s == touch2) {
    mb_cb.pointer(end ? 6 : 5, x, y, 0);
    if (end) touch2 = NULL;
  }
}

void mb_app_scroll(void *event) {
  double x = 0, y = 0;
  area_point(event, &x, &y);
  scroll(event, x, y);
}

static gboolean on_event(GtkEventControllerLegacy *c, GdkEvent *ev, gpointer data) {
  (void)c, (void)data;
  GdkEventType t = gdk_event_get_event_type(ev);
  // a pointer the system made of a touch: the touch is had already
  int pointer = t == GDK_BUTTON_PRESS || t == GDK_BUTTON_RELEASE || t == GDK_MOTION_NOTIFY;
  if (pointer && gdk_event_get_pointer_emulated(ev)) return TRUE;
  double x = 0, y = 0;
  switch (t) {
    case GDK_BUTTON_PRESS: {
      area_point(ev, &x, &y);
      guint b = gdk_button_event_get_button(ev);
      press_device = gdk_event_get_device(ev);
      gdk_event_get_position(ev, &press_x, &press_y);
      press_time = gdk_event_get_time(ev);
      press_button = (int)b;
      gtk_widget_grab_focus(area);
      if (b == 1) {
        left_down = 1;
        mb_cb.pointer(0, x, y, 0);
      } else if (b == 3) {
        right_down = 1;
        mb_cb.pointer(0, x, y, 2);
      }
      return TRUE;
    }
    case GDK_BUTTON_RELEASE: {
      area_point(ev, &x, &y);
      guint b = gdk_button_event_get_button(ev);
      if (b == 1 && left_down) {
        left_down = 0;
        mb_cb.pointer(2, x, y, 0);
      } else if (b == 3 && right_down) {
        right_down = 0;
        mb_cb.pointer(2, x, y, 2);
      } else if (b == 8) {
        go_back();
      } else if (b == 9) {
        mb_cb.key(40, 0);
      }
      return TRUE;
    }
    case GDK_MOTION_NOTIFY:
      area_point(ev, &x, &y);
      mb_cb.pointer(1, x, y, 0);
      return TRUE;
    case GDK_LEAVE_NOTIFY:
      if (!left_down) mb_cb.pointer(7, -1, -1, 0);
      return FALSE;
    case GDK_SCROLL:
      area_point(ev, &x, &y);
      scroll(ev, x, y);
      return TRUE;
    case GDK_TOUCH_BEGIN:
    case GDK_TOUCH_UPDATE:
    case GDK_TOUCH_END:
    case GDK_TOUCH_CANCEL:
      area_point(ev, &x, &y);
      touch(ev, t, x, y);
      return TRUE;
    default:
      return FALSE;
  }
}

static void on_focus_in(GtkEventControllerFocus *f, gpointer data) {
  (void)f, (void)data;
  if (ime_active) gtk_im_context_focus_in(im);
}

static void on_focus_out(GtkEventControllerFocus *f, gpointer data) {
  (void)f, (void)data;
  if (ime_active) gtk_im_context_focus_out(im);
}

// the window shown and in front (is-active) or not: 1 while shown, | 2 while in front
static void app_state(void) {
  if (!state_cb || !win) return;
  int shown = gtk_widget_get_mapped(win);
  int front = shown && gtk_window_is_active(GTK_WINDOW(win));
  state_cb((shown ? 1 : 0) | (front ? 2 : 0));
  schedule();
}

static void on_active(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p, (void)data;
  app_state();
}

// the app's life: once for its person, put away to its icon, links, the network, sleep; and its updates
#include "linux_life.h"
#include "linux_update.h"
#include "linux_station.h"

// ---- the system's settings: its colours, its words' size and face, its animations ----

static int portal_dark = -1;  // the desktop portal's color-scheme: 1 dark, 0 not, -1 unknown

static void color_scheme_is(GVariant *v) {
  while (v && g_variant_is_of_type(v, G_VARIANT_TYPE_VARIANT)) {
    GVariant *in = g_variant_get_variant(v);
    g_variant_unref(v);
    v = in;
  }
  if (v && g_variant_is_of_type(v, G_VARIANT_TYPE_UINT32)) portal_dark = g_variant_get_uint32(v) == 1;
  if (v) g_variant_unref(v);
}

static void on_setting_changed(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                               const char *signal, GVariant *params, gpointer data) {
  (void)c, (void)sender, (void)path, (void)iface, (void)signal, (void)data;
  const char *ns = NULL, *key = NULL;
  GVariant *v = NULL;
  g_variant_get(params, "(&s&sv)", &ns, &key, &v);
  if (!strcmp(ns, "org.freedesktop.appearance") && !strcmp(key, "color-scheme")) color_scheme_is(v);
  else if (v) g_variant_unref(v);
  schedule();
}

static void settings_watch(void) {
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
  if (!bus) return;
  GVariant *r = g_dbus_connection_call_sync(
      bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings",
      "ReadOne", g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"), NULL, G_DBUS_CALL_FLAGS_NONE, 500,
      NULL, NULL);
  if (!r)  // (a portal before ReadOne)
    r = g_dbus_connection_call_sync(bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                                    "org.freedesktop.portal.Settings", "Read",
                                    g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"), NULL,
                                    G_DBUS_CALL_FLAGS_NONE, 500, NULL, NULL);
  if (r) {
    GVariant *v = NULL;
    g_variant_get(r, "(v)", &v);
    color_scheme_is(v);
    g_variant_unref(r);
  }
  g_dbus_connection_signal_subscribe(bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Settings",
                                     "SettingChanged", "/org/freedesktop/portal/desktop", NULL,
                                     G_DBUS_SIGNAL_FLAGS_NONE, on_setting_changed, NULL, NULL);
}

static void on_font_name(GObject *o, GParamSpec *p, gpointer data) {
  (void)p, (void)data;
  char *name = NULL;
  g_object_get(o, "gtk-font-name", &name, NULL);
  PangoFontDescription *d = name ? pango_font_description_from_string(name) : NULL;
  if (d && pango_font_description_get_family(d)) mb_text_set_family(pango_font_description_get_family(d));
  if (d) pango_font_description_free(d);
  g_free(name);
  schedule();
}

// ---------------------------------------------------------------------------
// Scripted runs (MBUI_SCRIPT=ime|shot): drive the same paths an input method takes and save snapshots, as the macOS
// and Windows hosts do.

static void shot(const char *name) {
  if (!shot_dir) return;
  char p[1024];
  snprintf(p, sizeof p, "%s/%s.png", shot_dir, name);
  int ok = mb_render_snapshot(p);
  fprintf(stdout, "SHOT %s %s\n", p, ok ? "ok" : "failed");
  fflush(stdout);
}

static void run_script_step(int step) {
  double h = frame_h;
  if (strcmp(script, "ime") == 0) {
    switch (step) {
      case 20: shot("01-start"); break;
      case 21:  // click the composer
        mb_cb.pointer(0, 120, h - 30, 0);
        mb_cb.pointer(2, 120, h - 30, 0);
        break;
      case 30: marked_len = 6; send_text(1, "ni'hao", 6, 0); break;
      case 40: shot("02-composing"); break;
      case 41: marked_len = 0; send_text(0, "\xe4\xbd\xa0\xe5\xa5\xbd", 0, 0); break;  // 你好
      case 42: send_text(0, "\xef\xbc\x8cMoonBit ", 0, 0); break;                     // ，MoonBit
      case 43: marked_len = 7; send_text(1, "shi'jie", 3, 0); break;
      case 50: shot("03-composing-2"); break;
      case 51: marked_len = 0; send_text(0, "\xe4\xb8\x96\xe7\x95\x8c \xf0\x9f\x91\x8b", 0, 0); break;  // 世界 👋
      case 60: shot("04-typed"); break;
      case 61: mb_cb.key(7, 0); break;
      case 100: shot("05-sent"); break;
      case 101:
        for (int i = 0; i < 40; i++) mb_cb.wheel(300, 300, 0, 120, 0);
        break;
      case 140: shot("06-scrolled"); break;
      case 141: exit(0);
    }
    want_frame = 1;
  } else if (strcmp(script, "shot") == 0) {
    // from the 30th frame
    static int done;
    if (step >= 30 && !done) {
      shot(getenv("MBUI_SHOT_NAME") ? getenv("MBUI_SHOT_NAME") : "main");
      done = step;
    } else if (done && step > done) {
      exit(0);
    }
    want_frame = 1;
  }
}

// GLib's loop, run here: its sources (GTK's events, its frame clock, what other threads ask for) as they come, and the
// app's wake (@hostapi.wake_after) as the longest it waits for them, as Windows' loop waits (win_app.c): no timer.
static void run_loop(void) {
  GMainContext *ctx = g_main_context_default();
  g_main_context_acquire(ctx);
  GPollFD *fds = NULL;
  gint alloc = 0;
  for (;;) {
    if (wake_at >= 0 && mb_now_ms() >= wake_at) {
      wake_at = -1;
      schedule();
    }
    gint prio = 0, timeout = -1, n;
    g_main_context_prepare(ctx, &prio);
    while ((n = g_main_context_query(ctx, prio, &timeout, fds, alloc)) > alloc) {
      alloc = n;
      fds = g_renew(GPollFD, fds, alloc);
    }
    if (wake_at >= 0) {
      gint ms = (gint)ceil(wake_at - mb_now_ms());
      if (ms < 0) ms = 0;
      if (timeout < 0 || ms < timeout) timeout = ms;
    }
    g_main_context_get_poll_func(ctx)(fds, n, timeout);
    g_main_context_check(ctx, prio, fds, n);
    g_main_context_dispatch(ctx);
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer_fn, mb_wheel_fn wheel_fn,
                 mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer_fn, wheel_fn, key, text};
  script = getenv("MBUI_SCRIPT");
  shot_dir = getenv("MBUI_SHOT_DIR");
  // this machine's name (MBUI_MACHINE, @ui.env): what a station added from here is called (sfbase local_machine_name)
  if (!getenv("MBUI_MACHINE")) setenv("MBUI_MACHINE", g_get_host_name(), 0);
  setlocale(LC_ALL, "");
  // its icon's name its id (MBUI_APP_ID, as its desktop entry runs it: still.fail's linux/install.sh), which the
  // desktop knows its window by too (life_begin)
  gtk_init();
  if (*app_id()) gtk_window_set_default_icon_name(app_id());
  GtkSettings *gs = gtk_settings_get_default();
  if (gs) {
    on_font_name(G_OBJECT(gs), NULL, NULL);
    g_signal_connect(gs, "notify::gtk-font-name", G_CALLBACK(on_font_name), NULL);
  }
  settings_watch();

  win = gtk_window_new();
  char *t = utf8(title);
  gtk_window_set_title(GTK_WINDOW(win), t);
  // an inset window: its decorations GTK's own (its shadow and the edges it is resized by), a title bar of nothing,
  // the app's top row its title bar and its buttons the app's (@ui.window_keys_own), as Windows' is
  if (setup_inset) {
    GtkWidget *none = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_visible(none, FALSE);
    gtk_window_set_titlebar(GTK_WINDOW(win), none);
  }
  g_signal_connect(win, "notify::maximized", G_CALLBACK(on_window_state), NULL);
  g_signal_connect(win, "notify::fullscreened", G_CALLBACK(on_window_state), NULL);
  // MBUI_WIN=<w>x<h>: the area's size in points (a phone's, for the narrow layouts); else the app's own
  // (@hostapi.window_setup); 900 x 720 by default
  double ww = setup_w > 0 ? setup_w : 900, wh = setup_h > 0 ? setup_h : 720;
  const char *size = getenv("MBUI_WIN");
  if (size) sscanf(size, "%lfx%lf", &ww, &wh);
  gtk_window_set_default_size(GTK_WINDOW(win), (int)lround(ww), (int)lround(wh));
  g_signal_connect(win, "notify::is-active", G_CALLBACK(on_active), NULL);
  g_signal_connect(win, "notify::visible", G_CALLBACK(on_active), NULL);
  life_start(t);
  g_free(t);

  area = g_object_new(canvas_get_type(), NULL);
  gtk_gl_area_set_allowed_apis(GTK_GL_AREA(area), GDK_GL_API_GLES);
  gtk_gl_area_set_required_version(GTK_GL_AREA(area), 3, 0);
  gtk_gl_area_set_auto_render(GTK_GL_AREA(area), FALSE);
  gtk_gl_area_set_has_depth_buffer(GTK_GL_AREA(area), FALSE);
  gtk_gl_area_set_has_stencil_buffer(GTK_GL_AREA(area), FALSE);
  gtk_widget_set_focusable(area, TRUE);
  gtk_widget_set_hexpand(area, TRUE);
  gtk_widget_set_vexpand(area, TRUE);
  if (setup_min_w > 0 || setup_min_h > 0)
    gtk_widget_set_size_request(area, (int)lround(setup_min_w), (int)lround(setup_min_h));
  g_signal_connect(area, "realize", G_CALLBACK(on_realize), NULL);

  im = gtk_im_multicontext_new();
  gtk_im_context_set_client_widget(im, area);
  gtk_im_context_set_use_preedit(im, TRUE);
  g_signal_connect(im, "commit", G_CALLBACK(on_commit), NULL);
  g_signal_connect(im, "preedit-changed", G_CALLBACK(on_preedit), NULL);
  g_signal_connect(im, "preedit-end", G_CALLBACK(on_preedit_end), NULL);
  g_signal_connect(im, "retrieve-surrounding", G_CALLBACK(on_surrounding), NULL);
  g_signal_connect(im, "delete-surrounding", G_CALLBACK(on_delete_surrounding), NULL);

  GtkEventController *events = gtk_event_controller_legacy_new();
  g_signal_connect(events, "event", G_CALLBACK(on_event), NULL);
  gtk_widget_add_controller(area, events);
  keys = gtk_event_controller_key_new();
  g_signal_connect(keys, "key-pressed", G_CALLBACK(on_key), NULL);
  gtk_widget_add_controller(area, keys);
  GtkEventController *focus = gtk_event_controller_focus_new();
  g_signal_connect(focus, "enter", G_CALLBACK(on_focus_in), NULL);
  g_signal_connect(focus, "leave", G_CALLBACK(on_focus_out), NULL);
  gtk_widget_add_controller(area, focus);

  // the native views under the canvas (linux_views.c): the overlay's child, the canvas over it, as big as the canvas
  under = gtk_fixed_new();
  GtkWidget *overlay = gtk_overlay_new();
  gtk_overlay_set_child(GTK_OVERLAY(overlay), under);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), area);
  gtk_overlay_set_measure_overlay(GTK_OVERLAY(overlay), area, TRUE);
  gtk_window_set_child(GTK_WINDOW(win), overlay);
  gtk_window_present(GTK_WINDOW(win));
  gtk_widget_grab_focus(area);
  schedule();
  run_loop();
}

double mb_host_now(void) { return mb_now_ms(); }

double mb_host_wall_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_REALTIME, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

// how far local time is ahead of UTC then, in minutes (@hostapi.utc_offset_min)
int32_t mb_host_utc_offset_min(double at_ms) {
  time_t s = (time_t)(at_ms / 1000.0);
  struct tm local;
  if (!localtime_r(&s, &local)) return 0;
  return (int32_t)(local.tm_gmtoff / 60);
}

double mb_host_event_time(void) { return -1; }

// What a pointer's event came from (@hostapi.event_finger): not said (GTK hands touches as the pointer's here).
int32_t mb_host_event_finger(void) { return -1; }

// (how late the frame before reached the screen: not told here)
double mb_host_frame_late(void) { return 0; }

int32_t mb_host_platform(void) { return 5; }

void mb_host_request_frame(void) { schedule(); }

// (the loop waits no longer than it: run_loop)
void mb_host_wake_after(double ms) {
  double t = mb_now_ms() + ms;
  if (wake_at < 0 || t < wake_at) wake_at = t;
}

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  gl_current();  // (the frame may have opened a web view)
  mb_render_present(buf, count, r, g, b);
}

void mb_host_set_ime(int32_t active, double x, double y, double w, double h, moonbit_string_t text, int32_t a,
                     int32_t b) {
  int was = ime_active;
  ime_active = active != 0;
  caret[0] = x;
  caret[1] = y;
  caret[2] = w;
  caret[3] = h;
  // the field's words and its selection, in UTF-8's bytes, for the input method's surrounding text
  g_free(ime_words);
  ime_words = utf8(text);
  int32_t n = Moonbit_array_length(text);
  ime_sel_a = ime_sel_b = 0;
  const char *p = ime_words;
  for (int32_t i = 0; i < n && *p; p = g_utf8_next_char(p)) {
    if (i < a) ime_sel_a = (int)(g_utf8_next_char(p) - ime_words);
    if (i < b) ime_sel_b = (int)(g_utf8_next_char(p) - ime_words);
    i += g_utf8_get_char(p) >= 0x10000 ? 2 : 1;
  }
  if (ime_active && !was) {
    gtk_event_controller_key_set_im_context(GTK_EVENT_CONTROLLER_KEY(keys), im);
    if (gtk_widget_has_focus(area)) gtk_im_context_focus_in(im);
  } else if (!ime_active && was) {
    gtk_im_context_reset(im);
    gtk_im_context_focus_out(im);
    gtk_event_controller_key_set_im_context(GTK_EVENT_CONTROLLER_KEY(keys), NULL);
    marked_len = 0;
  }
  ime_place();
}

// no floating text menu of the system's here (the field's own keys and shortcuts do what it would)
void mb_host_text_menu(int32_t shown, double x, double y, double w, double h, int32_t can) {
  (void)shown, (void)x, (void)y, (void)w, (void)h, (void)can;
}

// no menu bar of the app's here
void mb_host_edit_can(int32_t can) { (void)can; }

// whether the clipboard's words are the last secret this app copied, to be taken off (while the clipboard is the
// app's still: gdk_clipboard_is_local)
static int secret_on;

void mb_host_clipboard_set(moonbit_string_t s) {
  char *u = utf8(s);
  gdk_clipboard_set_text(gtk_widget_get_clipboard(area), u);
  g_free(u);
  secret_on = 0;
}

// A secret on the clipboard (@hostapi.clipboard_set_secret): as any words here (no sensitive mark).
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  mb_host_clipboard_set(s);
  secret_on = clear_ms > 0;
}

// The last secret copied taken off (@hostapi.clipboard_secret_off), unless something else was copied since.
void mb_host_clipboard_secret_off(void) {
  GdkClipboard *cb = gtk_widget_get_clipboard(area);
  if (secret_on && gdk_clipboard_is_local(cb)) gdk_clipboard_set_content(cb, NULL);
  secret_on = 0;
}

// A picture on the clipboard (@hostapi.clipboard_set_image): a PNG's, as a picture GTK offers in the formats other
// programs paste (image/png first); what is not a picture is put nowhere.
void mb_host_clipboard_image(moonbit_bytes_t data) {
  GBytes *b = g_bytes_new(data, Moonbit_array_length(data));
  GdkTexture *t = gdk_texture_new_from_bytes(b, NULL);
  g_bytes_unref(b);
  if (!t) return;
  gdk_clipboard_set_texture(gtk_widget_get_clipboard(area), t);
  secret_on = 0;
  g_object_unref(t);
}

void mb_host_log(moonbit_string_t s) {
  char *u = utf8(s);
  fprintf(stdout, "%s\n", u);
  fflush(stdout);
  g_free(u);
}

// The app over another app done (@hostapi.over_done): it never is here.
void mb_host_over_done(int32_t open_app) { (void)open_app; }

// A URL handed to the system (@hostapi.open_url): the default browser or the app that takes it (GIO's, through the
// desktop portal where there is one); only http, https and mailto.
int32_t mb_host_open_url(moonbit_string_t s) {
  char *u = utf8(s);
  int ok = 0;
  if (!g_ascii_strncasecmp(u, "http://", 7) || !g_ascii_strncasecmp(u, "https://", 8) ||
      !g_ascii_strncasecmp(u, "mailto:", 7)) {
    fprintf(stdout, "%s\n", u);
    fflush(stdout);
    ok = g_app_info_launch_default_for_uri(u, NULL, NULL);
  }
  g_free(u);
  return ok;
}

// A page in a browser's tab over the app (@hostapi.open_tab): the default browser, as open_url.
int32_t mb_host_open_tab(moonbit_string_t s) { return mb_host_open_url(s); }

// What holds the app up while it listens for a browser (@hostapi.hold_words): nothing here, the app runs on.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {
  (void)channel, (void)title, (void)body;
}

// The word around an offset (@hostapi.word_at): none from the host here (the app's own rule, words.mbt).
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  (void)text, (void)off;
  return -1;
}

// Whether the run is on its own clock (host_native.mbt's own_clock): no run here is yet.
int32_t mb_host_own_clock(void) { return 0; }

// the system's animations off (GNOME's "Reduce animation" sets GTK's gtk-enable-animations)
int32_t mb_host_reduce_motion(void) {
  gboolean on = TRUE;
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_get(s, "gtk-enable-animations", &on, NULL);
  return on ? 0 : 1;
}

// What the host did for the app is done (host_native.mbt's set_outside): an image decoded (linux_image.c), the
// clipboard read (linux_device.h); told as each frame begins, on this thread.
int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}

// How many of the app's asks are not answered yet (host_native.mbt's frame_awaiting): nothing here waits on it yet.
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) { (void)awaiting, (void)what; }

int32_t mb_host_bench_mode(void) {
  const char *b = getenv("MBUI_BENCH");
  return b ? atoi(b) : 0;
}

void mb_host_exit(int32_t code) { exit(code); }

void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

void mb_host_set_app_state(void (*f)(int32_t)) {
  state_cb = f;
  app_state();
}

// Whether the system is set to dark (@hostapi.system_dark): the desktop portal's color-scheme, else GTK's own
// preference.
int32_t mb_host_system_dark(void) {
  if (portal_dark >= 0) return portal_dark;
  gboolean dark = FALSE;
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_get(s, "gtk-application-prefer-dark-theme", &dark, NULL);
  return dark ? 1 : 0;
}

// Words as the app sizes them (@hostapi.font_scale): the system's text scale (GNOME's "Large Text", its scaling
// factor), as Xft's DPI over 96.
double mb_host_font_scale(void) {
  int dpi = 0;
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_get(s, "gtk-xft-dpi", &dpi, NULL);
  return dpi > 0 ? dpi / 1024.0 / 96.0 : 1.0;
}

// What the app was started to be used with (@hostapi.native_pointing): keyboard and mouse.
int32_t mb_host_native_pointing(void) { return 2; }
// Whether a keyboard is at hand (@hostapi.keyboard): a computer's, always.
int32_t mb_host_keyboard(void) { return 1; }
// The app's widgets for the system's accessibility (@hostapi.a11y_on, a11y_tree): not told here yet.
int32_t mb_host_a11y_on(void) { return 0; }
void mb_host_a11y_tree(moonbit_string_t s) { (void)s; }

// Sharing (@hostapi.share, @hostapi.shared_in): no share sheet on Linux; nothing comes in.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)text, (void)name, (void)mime, (void)data;
  return 0;
}
moonbit_string_t mb_host_shared_in(void) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_shared_in_file(int32_t i) {
  (void)i;
  return moonbit_make_bytes(0, 0);
}

// A package for the system's installer (@hostapi.install_package): none here, said on the system channel (system.mbt):
// its name, escaped for JSON.
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  (void)data;
  char *u = utf8(name);
  GString *out = g_string_new("{\"install\":{\"name\":\"");
  json_put(out, u);
  g_string_append(out, "\",\"error\":\"unsupported\"}}");
  mb_post("system", out->str, out->len, NULL, 0);
  g_string_free(out, TRUE);
  g_free(u);
}


// Turned sideways for a film (@hostapi.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }
// Let turn as held (@hostapi.set_turnable): a window does not turn, and is not held upright.
int32_t mb_host_set_turnable(int32_t on) { (void)on; return 0; }

// The app drawn dark (@hostapi.set_dark): GTK's own parts (the title bar) drawn as dark.
void mb_host_set_dark(int32_t dark) {
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_set(s, "gtk-application-prefer-dark-theme", dark ? TRUE : FALSE, NULL);
}

// Scripted runs' input given to the host (src/ui/drive.mbt): the window's picture saved (4), a notification clicked
// (6) or looked for (7) by its words (linux_life.h), the window resized to "<w>x<h>" points (8), the runner's directory
// watched (9); the rest is sent to the app itself.
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  if (kind == 9) return mb_done_watch(text);
  char *u = utf8(text);
  int done = 0;
  if (kind == 6 || kind == 7) {
    done = notice_drive(kind == 6, u);
  } else if (kind == 4) {
    int ok = mb_render_snapshot(u);
    fprintf(stdout, "SHOT %s %s\n", u, ok ? "ok" : "failed");
    fflush(stdout);
    done = 1;
  } else if (kind == 8) {
    double cw = 0, ch = 0;
    if (sscanf(u, "%lfx%lf", &cw, &ch) == 2 && cw > 0 && ch > 0) {
      gtk_window_set_default_size(GTK_WINDOW(win), (int)lround(cw), (int)lround(ch));
      fprintf(stdout, "RESIZED %.0fx%.0f\n", cw, ch);
      fflush(stdout);
      schedule();
      done = 1;
    }
  }
  g_free(u);
  return done;
}

// The window held till the app shows it (@hostapi.window_hold): the system shows the app's own here, as it opens.
void mb_host_window_hold(void) {}
void mb_host_window_show(void) {}

// The window as the app wants it, asked before `run` (@hostapi.window_setup): with `inset`, no title bar of the
// system's, the app's top row is it, its buttons the app's.
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  setup_inset = inset != 0;
  setup_min_w = min_w;
  setup_min_h = min_h;
  setup_w = w;
  setup_h = h;
}

// Whether the window's buttons are in the app's top row now: an inset window, not full screen.
int32_t mb_host_window_inset(void) { return setup_inset && !(win && gtk_window_is_fullscreen(GTK_WINDOW(win))); }

// A window filling the screen (@hostapi.full_screen).
int32_t mb_host_full_screen(void) { return win && gtk_window_is_fullscreen(GTK_WINDOW(win)) ? 1 : 0; }
void mb_host_set_full_screen(int32_t on) {
  if (!win) return;
  if (on) gtk_window_fullscreen(GTK_WINDOW(win));
  else gtk_window_unfullscreen(GTK_WINDOW(win));
}

// How round the system draws the window's corners (@hostapi.window_corner): its content's are square under the title
// bar.
double mb_host_window_corner(void) { return 0; }
double mb_host_window_corner_at(int k) { (void)k; return 0; }

void mb_host_window_act(int32_t what);

// The press under way moves the window (the app's top row), as the title bar's would; the second press of a double
// click there (the desktop's own time and distance for one), what the title bar's double click does: maximized, or
// back as it was.
void mb_host_window_drag(void) {
  GdkSurface *s = win ? gtk_native_get_surface(GTK_NATIVE(win)) : NULL;
  if (!s || !GDK_IS_TOPLEVEL(s) || !press_device) return;
  left_down = 0;
  int dt = 400, dd = 5;
  GtkSettings *gs = gtk_settings_get_default();
  if (gs) g_object_get(gs, "gtk-double-click-time", &dt, "gtk-double-click-distance", &dd, NULL);
  if (drag_time && press_time - drag_time <= (guint32)dt && fabs(press_x - drag_x) <= dd && fabs(press_y - drag_y) <= dd) {
    drag_time = 0;
    mb_host_window_act(2);
    return;
  }
  drag_time = press_time, drag_x = press_x, drag_y = press_y;
  gdk_toplevel_begin_move(GDK_TOPLEVEL(s), press_device, press_button, press_x, press_y, press_time);
}

// The window's own buttons, the app's in an inset window (@hostapi.window_act, window_zoomed): minimized, maximized or
// back as it was, closed as the system's close button closes it (put away to its icon among the desktop's:
// linux_life.h); no Snap Layouts here (window_snap, window_snap_state: Windows').
void mb_host_window_act(int32_t what) {
  if (!win) return;
  if (what == 1) gtk_window_minimize(GTK_WINDOW(win));
  else if (what == 2 && gtk_window_is_maximized(GTK_WINDOW(win))) gtk_window_unmaximize(GTK_WINDOW(win));
  else if (what == 2) gtk_window_maximize(GTK_WINDOW(win));
  else if (what == 3) gtk_window_close(GTK_WINDOW(win));
}
int32_t mb_host_window_zoomed(void) { return win && gtk_window_is_maximized(GTK_WINDOW(win)) ? 1 : 0; }
void mb_host_window_snap(double x, double y, double w, double h) { (void)x, (void)y, (void)w, (void)h; }
int32_t mb_host_window_snap_state(void) { return 0; }

// (the number on the app's icon: linux_life.h)
// (this machine's station: linux_station.h)

// The keys held now (@hostapi.mods_held), as a key's are told.
int32_t mb_host_mods_held(void) {
  GdkDisplay *d = gdk_display_get_default();
  GdkSeat *seat = d ? gdk_display_get_default_seat(d) : NULL;
  GdkDevice *kb = seat ? gdk_seat_get_keyboard(seat) : NULL;
  return kb ? mods_of(gdk_device_get_modifier_state(kb)) : 0;
}

// The pointer's shape (@hostapi.set_cursor): CSS's names, as GTK takes them.
void mb_host_set_cursor(int32_t kind) {
  static int now = -1;
  if (!area || kind == now) return;
  now = kind;
  static const char *names[] = {"default", "pointer", "text", "ew-resize", "ns-resize", "move"};
  gtk_widget_set_cursor_from_name(area, names[kind >= 0 && kind < 6 ? kind : 0]);
}

moonbit_string_t mb_host_env(moonbit_string_t name) {
  char *k = utf8(name);
  moonbit_string_t out = mstr(getenv(k));
  g_free(k);
  return out;
}

int32_t mb_host_reduce_transparency(void) { return 0; }

double mb_host_gpu_ms(void) { return -1; }

// what the process keeps in memory (its resident pages)
// The CPU's time the whole process has had, every thread's (@hostapi.cpu_ms: MBUI_PROBE's share of a CPU), in ms.
double mb_host_cpu_ms(void) {
  struct rusage u;
  if (getrusage(RUSAGE_SELF, &u) != 0) return -1;
  return (u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1000.0 + (u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1000.0;
}

double mb_host_mem_bytes(void) {
  long pages = 0, resident = 0;
  FILE *f = fopen("/proc/self/statm", "r");
  if (!f) return 0;
  int n = fscanf(f, "%ld %ld", &pages, &resident);
  fclose(f);
  return n == 2 ? (double)resident * sysconf(_SC_PAGESIZE) : 0;
}

// Files picked (pick.mbt): GTK's file dialog (the desktop portal's chooser where there is one), more than one; pictures
// for the photo picker, anything for the file picker, no camera. Each read whole as the dialog answers (no file held
// by the host yet), told as the next frame begins (pick_tell).
typedef struct {
  int state;  // 0 asking, 1 answered, -1 called off or failed
  int told;
  GPtrArray *names;  // char *
  GPtrArray *bytes;  // GBytes *
} pick;
static pick *picks;
static int npicks = 1;  // ids from 1

static pick *pick_of(int32_t id) { return id > 0 && id < npicks ? &picks[id] : NULL; }

static void pick_done(GObject *src, GAsyncResult *res, gpointer data) {
  pick *k = pick_of(GPOINTER_TO_INT(data));
  GListModel *files = gtk_file_dialog_open_multiple_finish(GTK_FILE_DIALOG(src), res, NULL);
  if (k && k->state == 0) {
    k->state = files ? 1 : -1;
    for (guint i = 0; files && i < g_list_model_get_n_items(files); i++) {
      GFile *f = g_list_model_get_item(files, i);
      char *data_ = NULL;
      gsize n = 0;
      if (g_file_load_contents(f, NULL, &data_, &n, NULL, NULL)) {
        g_ptr_array_add(k->names, g_file_get_basename(f));
        g_ptr_array_add(k->bytes, g_bytes_new_take(data_, n));
      }
      g_object_unref(f);
    }
  }
  if (files) g_object_unref(files);
  g_object_unref(src);
  schedule();
}

int32_t mb_host_pick_start(int32_t kind) {
  int what = kind & 15;
  if (!win || (what != 1 && what != 2)) return 0;
  picks = realloc(picks, sizeof(pick) * (size_t)(npicks + 1));
  int id = npicks++;
  picks[id] = (pick){0, 0, g_ptr_array_new_with_free_func(g_free),
                     g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref)};
  GtkFileDialog *d = gtk_file_dialog_new();
  if (what == 1) {
    GtkFileFilter *f = gtk_file_filter_new();
    gtk_file_filter_add_mime_type(f, "image/*");
    GListStore *filters = g_list_store_new(GTK_TYPE_FILE_FILTER);
    g_list_store_append(filters, f);
    gtk_file_dialog_set_filters(d, G_LIST_MODEL(filters));
    gtk_file_dialog_set_default_filter(d, f);
    g_object_unref(filters);
    g_object_unref(f);
  }
  gtk_file_dialog_open_multiple(d, GTK_WINDOW(win), NULL, pick_done, GINT_TO_POINTER(id));
  return id;
}

// The picks answered since the last frame, told before it is drawn.
static void pick_tell(mb_outside_fn tell) {
  for (int i = 1; i < npicks; i++)
    if (picks[i].state != 0 && !picks[i].told) {
      picks[i].told = 1;
      if (tell) tell(MB_OUTSIDE_PICK, i, picks[i].state);
    }
}

int32_t mb_host_pick_state(int32_t id) {
  pick *k = pick_of(id);
  return k ? k->state : -1;
}
int32_t mb_host_pick_count(int32_t id) {
  pick *k = pick_of(id);
  return k && k->state == 1 ? (int32_t)k->names->len : 0;
}
moonbit_string_t mb_host_pick_name(int32_t id, int32_t i) {
  pick *k = pick_of(id);
  return k && i >= 0 && i < mb_host_pick_count(id) ? mstr(g_ptr_array_index(k->names, i)) : moonbit_make_string_raw(0);
}
moonbit_bytes_t mb_host_pick_bytes(int32_t id, int32_t i) {
  pick *k = pick_of(id);
  if (!k || i < 0 || i >= mb_host_pick_count(id)) return moonbit_make_bytes(0, 0);
  gsize n = 0;
  const void *p = g_bytes_get_data(g_ptr_array_index(k->bytes, i), &n);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, p, n);
  return b;
}
// (every one read whole: none held)
moonbit_string_t mb_host_pick_info(int32_t id, int32_t i) {
  (void)id, (void)i;
  return moonbit_make_string_raw(0);
}
void mb_host_pick_end(int32_t id) {
  pick *k = pick_of(id);
  if (!k) return;
  g_ptr_array_set_size(k->names, 0);
  g_ptr_array_set_size(k->bytes, 0);
  k->state = -1;
  k->told = 1;
}

// The gallery (gallery.mbt): none on this host; no photo of it picked.
int32_t mb_host_gallery_access(void) { return -1; }
void mb_host_gallery_ask(void) {}
int32_t mb_host_gallery_answers(void) { return 0; }
int32_t mb_host_gallery_read(void) { return 0; }
int32_t mb_host_gallery_read_state(int32_t id) {
  (void)id;
  return -1;
}
moonbit_string_t mb_host_gallery_read_rows(int32_t id) {
  (void)id;
  return moonbit_make_string_raw(0);
}
void mb_host_gallery_read_end(int32_t id) { (void)id; }
int32_t mb_host_pick_photo(moonbit_string_t src) {
  (void)src;
  return 0;
}

// Marks drawn onto an image (marks.mbt): none on this host yet.
int32_t mb_host_marks_start(moonbit_bytes_t image, moonbit_string_t marks) {
  (void)image, (void)marks;
  return 0;
}
int32_t mb_host_marks_state(int32_t id) {
  (void)id;
  return -1;
}
moonbit_bytes_t mb_host_marks_png(int32_t id) {
  (void)id;
  return moonbit_make_bytes(0, 0);
}

// Text in a legacy encoding (charset.mbt): iconv's, by IANA's names (a byte with no mapping: U+FFFD).
int32_t mb_host_charset_known(moonbit_string_t charset) {
  char *c = utf8(charset);
  GIConv cd = g_iconv_open("UTF-8", c);
  g_free(c);
  if (cd == (GIConv)-1) return 0;
  g_iconv_close(cd);
  return 1;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  char *c = utf8(charset);
  gsize n = 0;
  char *u = g_convert_with_fallback((const char *)data, Moonbit_array_length(data), "UTF-8", c, "\xef\xbf\xbd", NULL,
                                    &n, NULL);
  g_free(c);
  moonbit_string_t s = mstr(u ? u : "");
  g_free(u);
  return s;
}

// ---------------------------------------------------------------------------
// Files kept (keep.mbt) and saved (save_file): into the user's Downloads folder (XDG's; MBUI_DOWNLOADS_DIR instead,
// for scripted runs), either way (no save dialog yet); a name taken gets " (2)", " (3)"… before its extension.

static char *keep_dir(void) {
  const char *over = getenv("MBUI_DOWNLOADS_DIR");
  const char *d = over && *over ? over : g_get_user_special_dir(G_USER_DIRECTORY_DOWNLOAD);
  char *dir = d ? g_strdup(d) : g_build_filename(g_get_home_dir(), "Downloads", NULL);
  g_mkdir_with_parents(dir, 0755);
  return dir;
}

// the app's name for a file made safe for a folder (no separator, never empty, ".", "..")
static char *keep_safe(moonbit_string_t name) {
  char *n = utf8(name);
  for (char *c = n; *c; c++)
    if (*c == '/' || (unsigned char)*c < 32) *c = '_';
  if (!*n || !strcmp(n, ".") || !strcmp(n, "..")) {
    g_free(n);
    n = g_strdup("file");
  }
  return n;
}

// the i-th name tried in `dir` for `n`: n, then "base (2).ext"…
static char *keep_name(const char *dir, const char *n, int i) {
  if (i == 1) return g_build_filename(dir, n, NULL);
  const char *dot = strrchr(n, '.');
  if (!dot || dot == n) dot = n + strlen(n);
  char *name = g_strdup_printf("%.*s (%d)%s", (int)(dot - n), n, i, dot);
  char *p = g_build_filename(dir, name, NULL);
  g_free(name);
  return p;
}

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  char *dir = keep_dir(), *n = keep_safe(name);
  int ok = 0;
  for (int i = 1; i < 10000 && !ok; i++) {
    char *path = keep_name(dir, n, i);
    FILE *f = fopen(path, "wbx");
    if (f) {
      size_t len = (size_t)Moonbit_array_length(data);
      ok = fwrite(data, 1, len, f) == len;
      ok = fclose(f) == 0 && ok;
      if (!ok) remove(path);
      g_free(path);
      break;
    }
    g_free(path);
  }
  g_free(n);
  g_free(dir);
  return ok;
}

// each keep: its state (0 keeping, 1 kept, -1 failed), its name, its part file while its bytes come, where it went
typedef struct {
  int state;
  FILE *part;
  char *name, *tmp, *where;
} keep;
static keep *keeps;
static int nkeeps = 1;  // ids from 1

static keep *keep_of(int32_t id) { return id > 0 && id < nkeeps ? &keeps[id] : NULL; }

static void keep_fail(keep *k) {
  if (k->part) fclose(k->part);
  k->part = NULL;
  if (k->tmp) remove(k->tmp);
  k->state = -1;
}

int32_t mb_host_keep_begin(moonbit_string_t name, moonbit_string_t mime, int32_t way) {
  (void)mime, (void)way;
  keeps = realloc(keeps, sizeof(keep) * (size_t)(nkeeps + 1));
  int id = nkeeps++;
  keep *k = &keeps[id];
  memset(k, 0, sizeof *k);
  k->name = keep_safe(name);
  char *dir = keep_dir();
  k->tmp = g_strdup_printf("%s/.mbui-keep-%d-%d.part", dir, (int)getpid(), id);
  g_free(dir);
  k->part = fopen(k->tmp, "wb");
  k->state = k->part ? 0 : -1;
  return id;
}

int32_t mb_host_keep_append(int32_t id, moonbit_bytes_t data) {
  keep *k = keep_of(id);
  if (!k || k->state != 0 || !k->part) return 0;
  size_t n = (size_t)Moonbit_array_length(data);
  if (fwrite(data, 1, n, k->part) == n) return 1;
  keep_fail(k);
  return 0;
}

// finished: the part file named as asked, under a name not taken
void mb_host_keep_finish(int32_t id) {
  keep *k = keep_of(id);
  if (!k || k->state != 0 || !k->part) return;
  int ok = fclose(k->part) == 0;
  k->part = NULL;
  char *dir = keep_dir();
  for (int i = 1; ok && i < 10000; i++) {
    char *path = keep_name(dir, k->name, i);
    // (link: fails when the name is taken, never over another's file)
    if (link(k->tmp, path) == 0) {
      remove(k->tmp);
      k->where = path;
      k->state = 1;
      break;
    }
    g_free(path);
  }
  g_free(dir);
  if (k->state != 1) keep_fail(k);
  schedule();
}

int32_t mb_host_keep_state(int32_t id) {
  keep *k = keep_of(id);
  return k ? k->state : -1;
}

moonbit_string_t mb_host_keep_where(int32_t id) {
  keep *k = keep_of(id);
  return k && k->state == 1 ? mstr(k->where) : moonbit_make_string_raw(0);
}

void mb_host_keep_end(int32_t id) {
  keep *k = keep_of(id);
  if (k && k->state == 0) keep_fail(k);
  if (k) k->state = -1;
}
