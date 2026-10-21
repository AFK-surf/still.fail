// Shared by the Windows host files: the callbacks into MoonBit, the
// Direct3D 11 renderer and the DirectWrite glyph atlas.
#pragma once
#include <stdint.h>
#include <wchar.h>
#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mb_frame_fn)(double, double, double, double);
typedef void (*mb_pointer_fn)(int32_t, double, double, int32_t);
typedef void (*mb_wheel_fn)(double, double, double, double, int32_t);
typedef void (*mb_key_fn)(int32_t, int32_t);
typedef void (*mb_text_fn)(int32_t, moonbit_string_t, int32_t, int32_t);
typedef void (*mb_outside_fn)(int32_t, int32_t, int32_t);
// the kinds of what the host does for the app, named as src/ui/hostcall.mbt's outside_* (this host has no picker,
// gallery, marks or update of its own yet)
enum { MB_OUTSIDE_IMAGE = 1, MB_OUTSIDE_VIEW = 2, MB_OUTSIDE_GRAB = 6, MB_OUTSIDE_CLIP = 9 };

typedef struct {
  mb_frame_fn frame;
  mb_pointer_fn pointer;
  mb_wheel_fn wheel;
  mb_key_fn key;
  mb_text_fn text;
} mb_callbacks;

extern mb_callbacks mb_cb;

// renderer (win_render.cpp)
int mb_render_init(void *hwnd);
// pw, ph: the client area in pixels; w, h: the same in points
void mb_render_set_size(int pw, int ph, double w, double h, double scale);
void mb_render_present(const double *inst, int32_t count, double r, double g, double b);
// renders the last presented frame again into a texture and writes a PNG
int mb_render_snapshot(const wchar_t *path);
// what the screen shows of the window's client area, as a PNG
int mb_screen_snapshot(void *hwnd, const wchar_t *path);
void mb_atlas_upload(int x, int y, int w, int h, const void *rgba);
extern int mb_atlas_size;
void *mb_render_device(void);  // ID3D11Device *
// the composition (IDCompositionDevice *) and the visual the native views go in, under the canvas
// (IDCompositionVisual *); NULL where the canvas is the window's own swap chain (no native views)
void *mb_render_dcomp(void);
void *mb_render_views_visual(void);
void mb_render_commit(void);  // the composition's changes shown

// images (win_image.cpp): the ID3D11ShaderResourceView * of a ready one
void *mb_image_srv(int id);
// streams (win_stream.cpp): what stream id is drawn with now (ID3D11ShaderResourceView *), NULL before a frame shows;
// an instance's image MB_STREAM_TEX + id is it (src/host/stream.mbt)
#define MB_STREAM_TEX 4194304
void *mb_stream_srv(int id);
// the images decoded (or failed) since the last call, each told once to f(1, id, state) on the calling thread (the
// UI thread, between frames: host_native.mbt's set_outside); freed ones are not told
void mb_images_tell(mb_outside_fn f);

// app (win_app.c): asks for a frame from any thread
void mb_app_wake(void);
// the window (HWND) and its scale (pixels per point)
void *mb_app_hwnd(void);
double mb_app_scale(void);

// native views (win_views.cpp): web pages in WebView2 under the canvas, seen through its holes (kind 9)
int mb_views_count(void);
int mb_views_pass_through(double x, double y);
// a mouse message (WM_*) handed to the web view under it: 1 when it took it
int mb_views_input(unsigned msg, uintptr_t wp, intptr_t lp);
void *mb_views_cursor(double x, double y);  // HCURSOR of the page under (x, y), or NULL
void mb_views_rescale(void);
// what the app awaits of them told as it came, each to f(2, id, state) (host_native.mbt's set_outside; NULL: dropped),
// on the UI thread between frames
void mb_views_tell(mb_outside_fn f);
int mb_views_busy(void);       // one still opening, or its picture being taken
void mb_views_snap_all(void);  // pictures taken anew before a snapshot
// their pictures into w × h premultiplied BGRA (zeroed), for a snapshot
void mb_views_draw_under(uint8_t *out, int w, int h, double scale);

// text (win_text.cpp)
// rasterize at this many pixels per point; a change starts a new atlas
void mb_text_set_scale(double scale);

#ifdef __cplusplus
}
#endif
