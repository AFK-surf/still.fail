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
// the kinds of what the host does for the app, named as src/ui/hostcall.mbt's outside_* (this host has no gallery,
// marks or update of its own yet)
enum {
  MB_OUTSIDE_IMAGE = 1,
  MB_OUTSIDE_VIEW = 2,
  MB_OUTSIDE_PICK = 3,
  MB_OUTSIDE_GRAB = 6,
  MB_OUTSIDE_CLIP = 9,
  MB_OUTSIDE_POSTED = 11,
  MB_OUTSIDE_STREAMED = 12,
  MB_OUTSIDE_STOOD = 13,
};

typedef struct {
  mb_frame_fn frame;
  mb_pointer_fn pointer;
  mb_wheel_fn wheel;
  mb_key_fn key;
  mb_text_fn text;
} mb_callbacks;

extern mb_callbacks mb_cb;
int32_t mb_host_window_key(int32_t code, int32_t mods);
int32_t mb_host_mods_held(void);

// renderer (win_render.cpp)
int mb_render_init(void *hwnd);
// pw, ph: the client area in pixels; w, h: the same in points
void mb_render_set_size(int pw, int ph, double w, double h, double scale);
void mb_render_present(const double *inst, int32_t count, double r, double g, double b);
// renders the last presented frame again into a texture and writes a PNG
int mb_render_snapshot(const wchar_t *path);
// renders the last presented frame again and reads the rectangle x, y, w × h of its pixels (from its top left) into
// `out`: RGBA, premultiplied, rows from the top (host_native.mbt drawn_pixels); 1 when read
int32_t mb_render_drawn_pixels(int32_t x, int32_t y, int32_t w, int32_t h, moonbit_bytes_t out);
// draws instances never presented (a shot's) as a frame is, but `scale` pixels a point into a picture of their own
// w × h, and reads its pixels as mb_render_drawn_pixels does the frame's; 1 when read
int32_t mb_render_pixels_of(const double *inst, int32_t count, double r, double g, double b, double scale, int32_t w,
                            int32_t h, moonbit_bytes_t out);
// what the screen shows of the window's client area, as a PNG
int mb_screen_snapshot(void *hwnd, const wchar_t *path);
void mb_atlas_upload(int x, int y, int w, int h, const void *rgba);
extern int mb_atlas_size;
void *mb_render_device(void);  // ID3D11Device *
void *mb_render_context(void);  // ID3D11DeviceContext *, the UI thread's
// the composition (IDCompositionDevice *) and the visual the native views go in, under the canvas
// (IDCompositionVisual *); NULL where the canvas is the window's own swap chain (no native views)
void *mb_render_dcomp(void);
void *mb_render_views_visual(void);
void mb_render_commit(void);  // the composition's changes shown
// the composition's changes shown with the next frame presented (just after its Present): a view moved as the hole
// the canvas paints for it moves, not a frame before it
void mb_render_commit_with_frame(void);
// the composition's changes shown now, unless a frame presented next is to show the views' (then with it): a stream's
// layer changed between frames (win_stream.cpp)
void mb_render_commit_soon(void);

// images (win_image.cpp): the ID3D11ShaderResourceView * of a ready one
void *mb_image_srv(int id);
// a bitmap the clipboard holds (CF_DIB) as a PNG's bytes (malloc'd): 1 when made (win_image.cpp)
int mb_png_of_dib(const void *dib, size_t n, unsigned char **png, size_t *len);
// a PNG's bytes as a bitmap the clipboard takes (CF_DIB), in memory SetClipboardData takes: NULL where it cannot be
// read (win_image.cpp)
HGLOBAL mb_dib_of_png(const void *png, size_t n);
// streams (win_stream.cpp): what stream id is drawn with now (ID3D11ShaderResourceView *), NULL before a frame shows;
// an instance's image MB_STREAM_TEX + id is it (src/hostapi/stream.mbt)
#define MB_STREAM_TEX 4194304
void *mb_stream_srv(int id);
// the images decoded (or failed) since the last call, each told once to f(1, id, state) on the calling thread (the
// UI thread, between frames: host_native.mbt's set_outside); freed ones are not told
void mb_images_tell(mb_outside_fn f);

// app (win_app.c): asks for a frame from any thread
void mb_app_wake(void);
// stream id, shown by its system video layer, said something (win_stream.cpp), from any thread: the app told between
// frames (MB_OUTSIDE_STREAMED: ui's streams_said), a frame asked for only where what it said changes what is drawn
void mb_app_streamed(int id);
// fn(arg) run on the window's thread between frames, from any thread (a stream's routed frame shown: win_stream.cpp)
void mb_app_call(void (*fn)(void *), void *arg);
// the app's identity and its name ("" none: win_life.h), and the window's message that a notification was tapped
// (win_notify.cpp: the window brought back)
const wchar_t *mb_win_app_id(void);
const wchar_t *mb_win_app_name(void);
// a name of the program's environment as the process's says it, else as the program's own (win_life.h): NULL none
const wchar_t *mb_win_env(const wchar_t *name);
#define WM_MB_TAPPED (0x8000 + 4)  /* WM_APP + 4 */
// notifications (win_notify.cpp): a scripted run's tap (1) or look (0) at the one whose words hold `text`: 1 found
int32_t mb_notice_drive(int32_t tap, const wchar_t *text);
// the number on the window's taskbar button (win_notify.cpp: its overlay; 0 none), and put on again as the taskbar
// makes the button anew
void mb_win_badge(void *hwnd, int n);
void mb_win_badge_again(void *hwnd);
// the window (HWND) and its scale (pixels per point)
void *mb_app_hwnd(void);
double mb_app_scale(void);

// native views (win_views.cpp): web pages in WebView2 under the canvas, seen through its holes (kind 9)
int mb_views_count(void);
int mb_views_pass_through(double x, double y);
// a mouse message (WM_*) handed to the web view under it: 1 when it took it
int mb_views_input(unsigned msg, uintptr_t wp, intptr_t lp);
// UI Automation (win_a11y.cpp): WM_GETOBJECT's ask for the window's widgets answered (1, its answer in *r)
int mb_a11y_object(void *hwnd, uintptr_t wp, intptr_t lp, intptr_t *r);
void *mb_views_cursor(double x, double y);  // HCURSOR of the page under (x, y), or NULL
void mb_views_rescale(void);
// what the app awaits of them told as it came, each to f(2, id, state) (host_native.mbt's set_outside; NULL: dropped),
// on the UI thread between frames
void mb_views_tell(mb_outside_fn f);
int mb_views_busy(void);       // one still opening, or its picture being taken
void mb_views_snap_all(void);  // pictures taken anew before a snapshot
// their pictures into w × h premultiplied BGRA (zeroed), for a snapshot
void mb_views_draw_under(uint8_t *out, int w, int h, double scale);
// streams' system video layers (win_stream.cpp): whether there are any here (a composition, the GPU's video side);
// stream sid's put in a view's (kind 4: win_views.cpp) content visual (IDCompositionVisual *; NULL, taken off it as the
// view closes), and that visual placed w × h device pixels at `scale` pixels a point (the views' commit, with the
// frame's, shows it)
int mb_stream_layers_here(void);
void mb_stream_attach(int sid, void *content);
void mb_stream_placed(int sid, double w, double h, double scale);

// text (win_text.cpp)
// rasterize at this many pixels per point; a change starts a new atlas
void mb_text_set_scale(double scale);

#ifdef __cplusplus
}
#endif
