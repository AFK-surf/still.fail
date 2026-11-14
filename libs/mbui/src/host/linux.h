// Shared by the Linux host files (scripts/linux.sh): the callbacks into MoonBit, the GLES renderer in the window's
// GtkGLArea (linux_render.c), the glyphs' atlases (linux_text.c) and the images (linux_image.c).
#pragma once
#include <stdint.h>
#include "moonbit.h"

typedef void (*mb_frame_fn)(double, double, double, double);
typedef void (*mb_pointer_fn)(int32_t, double, double, int32_t);
typedef void (*mb_wheel_fn)(double, double, double, double, int32_t);
typedef void (*mb_key_fn)(int32_t, int32_t);
typedef void (*mb_text_fn)(int32_t, moonbit_string_t, int32_t, int32_t);
typedef void (*mb_outside_fn)(int32_t, int32_t, int32_t);
// the kinds of what the host does for the app, named as src/ui/hostcall.mbt's outside_* (this host has no gallery,
// marks or update of its own yet)
enum { MB_OUTSIDE_IMAGE = 1, MB_OUTSIDE_VIEW = 2, MB_OUTSIDE_PICK = 3, MB_OUTSIDE_GRAB = 6, MB_OUTSIDE_UPDATE = 7,
       MB_OUTSIDE_STREAM = 8, MB_OUTSIDE_CLIP = 9, MB_OUTSIDE_POSTED = 11,
       MB_OUTSIDE_STOOD = 13 };

typedef struct {
  mb_frame_fn frame;
  mb_pointer_fn pointer;
  mb_wheel_fn wheel;
  mb_key_fn key;
  mb_text_fn text;
} mb_callbacks;

extern mb_callbacks mb_cb;

// ---- the renderer (linux_render.c), in the GtkGLArea's context: only while it renders (a frame) ----
// the context's GL made ready (its programs, atlases); again for a new context, whose textures the images make again
void mb_render_setup(void);
// what the frame is drawn into: the framebuffer bound, pw × ph pixels, w × h points at `scale`
void mb_render_target(int pw, int ph, double w, double h, double scale);
void mb_render_present(const double *inst, int32_t count, double r, double g, double b);
// the frame presented last drawn again and written as a PNG: 1 when written
int mb_render_snapshot(const char *path);
// a glyph's picture put in its atlas (colour: the colour glyphs' RGBA one, else the words' one byte a pixel), uploaded
// before the next frame is drawn
void mb_atlas_put(int colour, int x, int y, int w, int h, const uint8_t *px);
#define MB_ATLAS 4096
#define MB_ATLAS_COLOR 1024
#define MB_ATLAS_COLOR_U 16384

// ---- images (linux_image.c): decoded off the main thread, their textures made in the GL context ----
// a ready one's texture (0: none, decoding, failed)
unsigned mb_image_tex(int id);
// the decoded ones' textures made (GL context current), and each decode done told once to f(1, id, state)
void mb_images_upload(void);
void mb_images_tell(mb_outside_fn f);
// a new context: the textures of the old one gone, made again from the pictures kept
void mb_images_lost(void);
// streams (src/hostapi/stream.mbt): an instance's image MB_STREAM_TEX + its id is its picture now
#define MB_STREAM_TEX 4194304
#define MB_VIEW_TEX 8388608
unsigned mb_stream_tex(int id);
void mb_streams_upload(void);
void mb_streams_lost(void);

// ---- a video's frame as its decoder gave it (the streams', the players'): YUV planes, made a picture on the GPU ----
// NV12 (Y, then U and V interleaved) or I420 (Y, U, V), w × h, each plane at `off` with rows `stride` bytes apart in
// `data` (`size` bytes, the frame's own); its colours by the matrix (601, 709 or 2020) and range (full, else 16-235)
// its caps said
typedef struct {
  int w, h, nv12, matrix, full;
  size_t off[3];
  int stride[3];
  size_t size;
  uint8_t *data;
} mb_yuv;
// (linux_render.c, the GL context current) frame `f` drawn into *tex as its RGBA picture, made or sized anew to the
// frame (*tw × *th): the planes uploaded as they are and their colours worked out by a shader, nothing of it by the CPU
void mb_yuv_draw(const mb_yuv *f, unsigned *tex, int *tw, int *th);
// (linux_render.c) its picture as RGBA on the CPU, w × h (a frame grabbed as a picture: rare, never what is drawn)
uint8_t *mb_yuv_rgba(const mb_yuv *f);
// a new context: the converter's program and planes gone with the old one
void mb_yuv_lost(void);

// ---- the app (linux_app.c) ----
// a frame asked for, from any thread
void mb_app_wake(void);
double mb_app_scale(void);
double mb_now_ms(void);
// the native views' GtkFixed, under the canvas (NULL before the window is made)
void *mb_app_under(void);
// a GdkEvent of a view's, a scroll the app takes (a page that gives it the wheel's upright scroll), as the canvas's own
void mb_app_scroll(void *event);

// ---- the native views (linux_views.c): widgets under the canvas ----
// whether WebKitGTK is loaded (its GL in the process)
int mb_views_webkit(void);
// whether a press at (x, y), points in the canvas, is a view's (the canvas holds none there)
int mb_views_pass_through(double x, double y);
// each view placed again on the window's new scale
void mb_views_rescale(void);
// what was done for the app told: f(MB_OUTSIDE_VIEW or MB_OUTSIDE_GRAB, id, state)
void mb_views_tell(mb_outside_fn f);
// a player's (linux_player.h): whether a view is one, its picture's texture (GL context current; 0 none yet), the
// textures of those closed deleted as a frame begins, a new context's
int mb_view_is_player(int vid);
unsigned mb_player_tex(int vid);
void mb_players_upload(void);
void mb_players_lost(void);

// ---- text (linux_text.c) ----
// drawn at this many pixels per point; a change starts a new atlas
void mb_text_set_scale(double scale);
// the system's font for the app's words (GTK's gtk-font-name family), before the first is shaped
void mb_text_set_family(const char *family);
