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
  mb_yuv_lost();
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
// A video's frame made a picture (linux.h's mb_yuv: the streams' H.264, the players' frames): its planes uploaded as
// the decoder gave them (a byte a texel: Y and I420's U and V as R8, NV12's U and V together as RG8), then drawn into
// the frame's RGBA texture by a shader that works out its colours, as Apple's, Android's and Windows' hosts have the
// GPU do it. Its own program, planes (on units 5-7, past the renderer's) and framebuffer; what it changes of the
// context's state is put back as it was.

static GLuint yuv_prog, yuv_vao, yuv_fb, yuv_planes[3];
static int yuv_plane_w[3], yuv_plane_h[3], yuv_plane_rg[3];
static GLint yuv_u_nv12, yuv_u_m, yuv_u_off;

static const char *YUV_VS =
    "#version 300 es\n"
    "out vec2 uv;\n"
    "void main() {\n"
    "  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));\n"
    "  uv = p;\n"
    "  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
    "}\n";
// (the texture's row r is the frame's row r, as the RGBA frames were uploaded: the renderer samples it the same)
static const char *YUV_FS =
    "#version 300 es\n"
    "precision highp float;\n"
    "uniform sampler2D py, pu, pv;\n"
    "uniform int nv12;\n"
    "uniform mat3 m;\n"
    "uniform vec3 off;\n"
    "in vec2 uv;\n"
    "out vec4 o;\n"
    "void main() {\n"
    "  vec2 c = nv12 == 1 ? texture(pu, uv).rg : vec2(texture(pu, uv).r, texture(pv, uv).r);\n"
    "  vec3 rgb = m * (vec3(texture(py, uv).r, c) - off);\n"
    "  o = vec4(clamp(rgb, 0.0, 1.0), 1.0);\n"
    "}\n";

// The frame's colours: rgb = m * (yuv - off), m column by column (as GL takes a mat3), by its matrix and range.
static void yuv_matrix(const mb_yuv *f, float m[9], float off[3]) {
  double kr = 0.299, kb = 0.114;  // BT.601's
  if (f->matrix == 709) kr = 0.2126, kb = 0.0722;
  else if (f->matrix == 2020) kr = 0.2627, kb = 0.0593;
  double kg = 1 - kr - kb;
  double ys = f->full ? 1.0 : 255.0 / 219.0, cs = f->full ? 1.0 : 255.0 / 224.0;
  double rv = (2 - 2 * kr) * cs, bu = (2 - 2 * kb) * cs;
  double gu = -bu * kb / kg, gv = -rv * kr / kg;
  float mm[9] = {(float)ys, (float)ys, (float)ys, 0, (float)gu, (float)bu, (float)rv, (float)gv, 0};
  memcpy(m, mm, sizeof mm);
  off[0] = f->full ? 0.0f : 16.0f / 255.0f;
  off[1] = off[2] = 128.0f / 255.0f;
}

uint8_t *mb_yuv_rgba(const mb_yuv *f) {
  float m[9], off[3];
  yuv_matrix(f, m, off);
  uint8_t *out = malloc((size_t)f->w * f->h * 4);
  if (!out) return NULL;
  for (int y = 0; y < f->h; y++) {
    const uint8_t *py = f->data + f->off[0] + (size_t)y * f->stride[0];
    const uint8_t *pu = f->data + f->off[1] + (size_t)(y / 2) * f->stride[1];
    const uint8_t *pv = f->nv12 ? pu + 1 : f->data + f->off[2] + (size_t)(y / 2) * f->stride[2];
    uint8_t *o = out + (size_t)y * f->w * 4;
    for (int x = 0; x < f->w; x++, o += 4) {
      int ci = f->nv12 ? (x / 2) * 2 : x / 2;
      float v[3] = {py[x] / 255.0f - off[0], pu[ci] / 255.0f - off[1], pv[ci] / 255.0f - off[2]};
      for (int k = 0; k < 3; k++) {
        float c = m[k] * v[0] + m[3 + k] * v[1] + m[6 + k] * v[2];
        o[k] = (uint8_t)lroundf(255.0f * (c < 0 ? 0 : c > 1 ? 1 : c));
      }
      o[3] = 255;
    }
  }
  return out;
}

void mb_yuv_lost(void) {
  yuv_prog = yuv_vao = yuv_fb = 0;
  memset(yuv_planes, 0, sizeof yuv_planes);
  memset(yuv_plane_w, 0, sizeof yuv_plane_w);
}

static GLuint yuv_shader(GLenum kind, const char *src) {
  GLuint s = glCreateShader(kind);
  glShaderSource(s, 1, &src, NULL);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[512] = "";
    glGetShaderInfoLog(s, sizeof log, NULL, log);
    LOG("the video frames' shader did not compile: %s", log);
  }
  return s;
}

static int yuv_ready(void) {
  if (yuv_prog) return 1;
  GLuint vs = yuv_shader(GL_VERTEX_SHADER, YUV_VS), fs = yuv_shader(GL_FRAGMENT_SHADER, YUV_FS);
  GLuint p = glCreateProgram();
  glAttachShader(p, vs);
  glAttachShader(p, fs);
  glLinkProgram(p);
  glDeleteShader(vs);
  glDeleteShader(fs);
  GLint ok = 0;
  glGetProgramiv(p, GL_LINK_STATUS, &ok);
  if (!ok) {
    LOG("the video frames' program did not link");
    glDeleteProgram(p);
    return 0;
  }
  yuv_prog = p;
  GLint was = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &was);
  glUseProgram(p);
  glUniform1i(glGetUniformLocation(p, "py"), 5);
  glUniform1i(glGetUniformLocation(p, "pu"), 6);
  glUniform1i(glGetUniformLocation(p, "pv"), 7);
  glUseProgram((GLuint)was);
  yuv_u_nv12 = glGetUniformLocation(p, "nv12");
  yuv_u_m = glGetUniformLocation(p, "m");
  yuv_u_off = glGetUniformLocation(p, "off");
  glGenVertexArrays(1, &yuv_vao);
  glGenFramebuffers(1, &yuv_fb);
  glGenTextures(3, yuv_planes);
  return 1;
}

// plane `i` (a byte a texel, two where `rg`: w × h of them, rows `stride` bytes apart) uploaded on unit 5 + i
static void yuv_plane(int i, const uint8_t *px, int w, int h, int stride, int rg) {
  glActiveTexture(GL_TEXTURE5 + i);
  glBindTexture(GL_TEXTURE_2D, yuv_planes[i]);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, stride / (rg ? 2 : 1));
  GLenum fmt = rg ? GL_RG : GL_RED;
  if (yuv_plane_w[i] == w && yuv_plane_h[i] == h && yuv_plane_rg[i] == rg) {
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, fmt, GL_UNSIGNED_BYTE, px);
  } else {
    glTexImage2D(GL_TEXTURE_2D, 0, rg ? GL_RG8 : GL_R8, w, h, 0, fmt, GL_UNSIGNED_BYTE, px);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    yuv_plane_w[i] = w, yuv_plane_h[i] = h, yuv_plane_rg[i] = rg;
  }
}

void mb_yuv_draw(const mb_yuv *f, unsigned *tex, int *tw, int *th) {
  if (!f->data || f->w <= 0 || f->h <= 0 || !yuv_ready()) return;
  // (what the renderer has set, put back after)
  GLint was_fb = 0, was_prog = 0, was_vao = 0, was_unit = 0, was_vp[4];
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &was_fb);
  glGetIntegerv(GL_CURRENT_PROGRAM, &was_prog);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &was_vao);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &was_unit);
  glGetIntegerv(GL_VIEWPORT, was_vp);
  GLboolean was_blend = glIsEnabled(GL_BLEND), was_cut = glIsEnabled(GL_SCISSOR_TEST);
  int cw = (f->w + 1) / 2, ch = (f->h + 1) / 2;
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  yuv_plane(0, f->data + f->off[0], f->w, f->h, f->stride[0], 0);
  if (f->nv12) {
    yuv_plane(1, f->data + f->off[1], cw, ch, f->stride[1], 1);
  } else {
    yuv_plane(1, f->data + f->off[1], cw, ch, f->stride[1], 0);
    yuv_plane(2, f->data + f->off[2], cw, ch, f->stride[2], 0);
  }
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  // its picture: made, or made anew at its size
  glActiveTexture(GL_TEXTURE1);
  GLint was_tex1 = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &was_tex1);
  if (!*tex) {
    glGenTextures(1, tex);
    *tw = *th = 0;
  }
  glBindTexture(GL_TEXTURE_2D, *tex);
  if (*tw != f->w || *th != f->h) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, f->w, f->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    *tw = f->w, *th = f->h;
  }
  glBindTexture(GL_TEXTURE_2D, (GLuint)was_tex1);
  glBindFramebuffer(GL_FRAMEBUFFER, yuv_fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
  glViewport(0, 0, f->w, f->h);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glUseProgram(yuv_prog);
  float m[9], off[3];
  yuv_matrix(f, m, off);
  glUniform1i(yuv_u_nv12, f->nv12 ? 1 : 0);
  glUniformMatrix3fv(yuv_u_m, 1, GL_FALSE, m);
  glUniform3fv(yuv_u_off, 1, off);
  glBindVertexArray(yuv_vao);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
  glBindVertexArray((GLuint)was_vao);
  glUseProgram((GLuint)was_prog);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)was_fb);
  glViewport(was_vp[0], was_vp[1], was_vp[2], was_vp[3]);
  if (was_blend) glEnable(GL_BLEND);
  if (was_cut) glEnable(GL_SCISSOR_TEST);
  glActiveTexture((GLenum)was_unit);
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
