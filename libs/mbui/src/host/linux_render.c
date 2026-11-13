// The Linux host's renderer: GLES 3's (gles_render.h, Android's too) in the window's GtkGLArea, whose context GTK
// makes (OpenGL ES 3, asked for: linux_app.c) and makes current while it renders; its functions through epoxy, as
// GTK's own. Without a window (mbui-render, src/render) a context of its own on EGL's surfaceless platform (Mesa's),
// drawn into a framebuffer of its own.
#include <epoxy/gl.h>
#include <epoxy/egl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>
#include "linux.h"
#include "corner_sl.h"

#define LOG(...) (fprintf(stderr, "mbui: " __VA_ARGS__), fputc('\n', stderr))

// The native views' pages are under the canvas (linux_views.c): where one shows, the canvas is taken away
// (gles_render.h); a player's picture is drawn in it (linux_player.h), as Android's views' are.
#define MB_VIEWS_UNDER 1
static GLuint white_tex;  // a page's picture here: one white texel (its coverage is what is drawn), in the context now

static int view_under(int tid) { return !mb_view_is_player(tid - MB_VIEW_TEX); }

// what an instance's image (slot 20) is drawn from: a stream's picture, a decoded image's, a player's frame, a page's
// white texel
static GLuint image_tex(int id) {
  if (id > MB_VIEW_TEX && !view_under(id)) return (GLuint)mb_player_tex(id - MB_VIEW_TEX);
  if (id > MB_VIEW_TEX) {
    if (!white_tex) {
      static const uint8_t white[4] = {255, 255, 255, 255};
      glGenTextures(1, &white_tex);
      glBindTexture(GL_TEXTURE_2D, white_tex);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, white);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    return white_tex;
  }
  if (id > MB_STREAM_TEX) return (GLuint)mb_stream_tex(id - MB_STREAM_TEX);
  return (GLuint)mb_image_tex(id);
}

static void view_parts_in(int tid, int32_t start, int32_t end) { (void)tid, (void)start, (void)end; }

#include "gles_render.h"

// ---- the glyphs put in the atlases (linux_text.c), uploaded as the next frame is drawn ----

typedef struct {
  int colour, x, y, w, h;
  uint8_t *px;
} atlas_put;
static atlas_put *puts_;
static int n_puts, cap_puts;
static int ready;  // gl_setup done in the context now current

void mb_atlas_put(int colour, int x, int y, int w, int h, const uint8_t *px) {
  if (w <= 0 || h <= 0) return;
  if (n_puts == cap_puts) {
    cap_puts = cap_puts ? cap_puts * 2 : 256;
    puts_ = realloc(puts_, sizeof *puts_ * (size_t)cap_puts);
  }
  size_t n = (size_t)w * h * (colour ? 4 : 1);
  uint8_t *copy = malloc(n);
  memcpy(copy, px, n);
  puts_[n_puts++] = (atlas_put){colour, x, y, w, h, copy};
}

static void atlas_upload(void) {
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  for (int i = 0; i < n_puts; i++) {
    atlas_put *p = &puts_[i];
    glBindTexture(GL_TEXTURE_2D, p->colour ? catlas : atlas);
    glTexSubImage2D(GL_TEXTURE_2D, 0, p->x, p->y, p->w, p->h, p->colour ? GL_RGBA : GL_RED, GL_UNSIGNED_BYTE, p->px);
    free(p->px);
  }
  n_puts = 0;
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}

void mb_render_setup(void) {
  gl_setup();
  ready = 1;
  // what the atlases held is gone with the old context (MoonBit draws its glyphs again: linux_text.c's generation)
  for (int i = 0; i < n_puts; i++) free(puts_[i].px);
  n_puts = 0;
  mb_images_lost();
  mb_streams_lost();
  mb_players_lost();
  white_tex = 0;
}

void mb_render_target(int pw, int ph, double w, double h, double scale) {
  GLint fb = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fb);
  target_fb = (GLuint)fb;
  fb_w = pw;
  fb_h = ph;
  cur_w = w;
  cur_h = h;
  cur_scale = scale;
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  if (!ready) return;
  atlas_upload();
  mb_images_upload();
  mb_streams_upload();
  gl_present((double *)inst, count, r, g, b);
}

// (the window's frame is GTK's once drawn: drawn again into a framebuffer of its own)
int mb_render_snapshot(const char *path) {
  if (!ready || kept_count <= 0) return 0;
  GLint was = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &was);
  draw_kept_read();
  int ok = gl_png(path, read_fb);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)was);
  return ok;
}

// ---------------------------------------------------------------------------
// Without a window (mbui-render, src/render): OpenGL ES 3 on EGL's surfaceless platform (Mesa's, its llvmpipe where
// there is no GPU), current on this thread for the whole run, a framebuffer of its own (gles_render.h) the size the
// window would be, the text at the list's scale.

double mb_host_now(void);
void mb_host_present(double *buf, int32_t count, double r, double g, double b);

void mb_render_init_offscreen(double w, double h, double scale) {
  EGLDisplay d = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
  if (d == EGL_NO_DISPLAY || !eglInitialize(d, NULL, NULL)) {
    LOG("mbui-render: no EGL display (surfaceless)");
    exit(1);
  }
  eglBindAPI(EGL_OPENGL_ES_API);
  static const EGLint want[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE};
  EGLConfig cfg = NULL;
  EGLint n = 0;
  eglChooseConfig(d, want, &cfg, 1, &n);
  static const EGLint attrs[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE};
  EGLContext ctx = eglCreateContext(d, n > 0 ? cfg : EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attrs);
  if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
    LOG("mbui-render: no OpenGL ES 3 context");
    exit(1);
  }
  mb_render_setup();
  gl_offscreen(w, h, scale);
  mb_text_set_scale(scale);
}

void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out) {
  double t0 = mb_host_now();
  mb_host_present((double *)inst, count, r, g, b);
  glFinish();
  out[0] = mb_host_now() - t0;
  out[1] = -1;
}

// what was decoded meanwhile made textures (mb_host_present does), then a while for more
void mb_render_spin(double ms) {
  struct timespec t = {(time_t)(ms / 1000), (long)(fmod(ms, 1000) * 1e6)};
  nanosleep(&t, NULL);
}
