// Shared by the macOS and iOS hosts: the callbacks into MoonBit, the Metal
// renderer and the Core Text glyph atlas.
#pragma once
#include <stdint.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#include "moonbit.h"

typedef void (*mb_frame_fn)(double, double, double, double);
typedef void (*mb_pointer_fn)(int32_t, double, double, int32_t);
typedef void (*mb_wheel_fn)(double, double, double, double, int32_t);
typedef void (*mb_key_fn)(int32_t, int32_t);
typedef void (*mb_text_fn)(int32_t, moonbit_string_t, int32_t, int32_t);
typedef void (*mb_outside_fn)(int32_t, int32_t, int32_t);

typedef struct {
  mb_frame_fn frame;
  mb_pointer_fn pointer;
  mb_wheel_fn wheel;
  mb_key_fn key;
  mb_text_fn text;
} mb_callbacks;

extern mb_callbacks mb_cb;

// renderer (apple_render.m)
void mb_render_init(CAMetalLayer *layer);
id<MTLDevice> mb_render_device(void);
void mb_render_set_size(double w, double h, double scale);
void mb_render_present(const double *inst, int32_t count, double r, double g, double b);
// what drawing holds (the spare drawables, the glass's levels) given back, the frame shown kept (the window not in front)
void mb_render_trim(void);
// renders the last presented frame again into memory and writes a PNG
int mb_render_snapshot(const char *path);
// bands above and under the app's view (points) filled with `ground` (0xRRGGBB) in what snapshots write: a phone's
// system bars round a scripted run's window (mac_app.m MBUI_SAFE)
void mb_render_set_bands(double top, double bottom, uint32_t ground);
// The glyphs' atlases, square, what goes where in them MoonBit's (hostapi's atlas.mbt): the words' (a byte a texel, how
// much of it the glyph covers: drawn in the text's colour; as many bytes as one RGBA atlas half as wide) and colour
// glyphs' (RGBA: an emoji's own). A colour glyph's place across is MB_ATLAS_COLOR_U past its place in its atlas (what
// MoonBit says of it, @hostapi.colour_atlas_u): the shader takes the atlas by it.
#define MB_ATLAS_SIDE 4096
#define MB_ATLAS_COLOR_SIDE 1024
#define MB_ATLAS_COLOR_U 16384
void mb_atlas_upload(int color, int x, int y, int w, int h, const void *px);

// images (apple_image.m): the texture of a decoded image, nil if not ready
id<MTLTexture> mb_image_texture(int iid);
// streams (apple_stream.m): what stream sid is drawn with now, nil before a frame shows; an instance's image
// MB_STREAM_TEX + sid is it (src/hostapi/stream.mbt)
#define MB_STREAM_TEX 4194304
id<MTLTexture> mb_stream_texture(int sid);
// the layer stream sid's frames are put on as they are shown as well (their IOSurfaces, the contents of a native view's
// of kind 4, apple_views.m), nil none: what it shows now on it at once
void mb_stream_attach_layer(int sid, CALayer *layer);
// that layer placed anew (its view's rect: apple_views.m): what is over it on it (its pointer) put where it goes
void mb_stream_layout(int sid, double w, double h);
// a stream's records from another thread, an app's engine's (its shell reads a remote screen itself): record `kind` of
// route `route` (2 a video frame, `key`, `ts`, its access unit; 6 a sound packet; 1 and 5 their configs, which stop the
// route's frames or sound being taken until the app has taken them), the `seq`th of all said; 1 when it was taken (fed
// to the stream the app routed it to, @hostapi.stream_direct: decoded, shown or played and acknowledged here), 0 when
// it is the app's to take. Any thread, a route's in order.
int mb_stream_route_take(uint64_t route, int kind, int key, uint64_t seq, uint64_t ts, const uint8_t *bytes, size_t len);
// how a frame taken so is acknowledged to its sender (`ack(route, ts)`, on the main thread), handed over by the engine
void mb_stream_route_acks(int (*ack)(double route, double ts));

// text (apple_text.m)
// drawn at this many pixels a point; a change draws every glyph again
void mb_text_set_scale(double scale);
CTFontRef mb_platform_font(double size, int weight, int mono); // per platform, retained
moonbit_string_t mb_string_from_ns(NSString *s);
NSString *mb_ns_from_string(moonbit_string_t s);

// shared helpers (per platform)
double mb_now_ms(void);

// What the host did for the app is done (host_native.mbt's set_outside; its kinds named as src/ui/hostcall.mbt's
// outside_*): an image or a PDF's page decoded (id: the image), a native view ready (a page loaded and its picture
// taken, a video's first frame), what the pickers gave, marks drawn, a video's frame grabbed (id: its view); state 1
// done, -1 failed, 0 (a view) waiting on the app now (bytes a player reads, a site's answer): the host's work for it
// stops until the app answers. On the main thread, between frames (per platform).
enum {
  MB_OUTSIDE_IMAGE = 1,
  MB_OUTSIDE_VIEW = 2,
  MB_OUTSIDE_PICK = 3,
  MB_OUTSIDE_GALLERY = 4,
  MB_OUTSIDE_MARKS = 5,
  MB_OUTSIDE_GRAB = 6,
  MB_OUTSIDE_UPDATE = 7,
  MB_OUTSIDE_CLIP = 9,
  MB_OUTSIDE_POSTED = 11,
  MB_OUTSIDE_STREAMED = 12,
};
void mb_host_outside(int32_t kind, int32_t id, int32_t state);
// whether a native view's picture for snapshots is being taken (apple_views.m): a snapshot waits for it
int mb_views_snapping(void);
// every loaded page's picture taken anew, before a snapshot (apple_views.m)
void mb_views_snap_all(void);

// native views (apple_views.m), kept under the canvas's view and seen through
// its holes (kind 9 instances)
// the view they go in, made once, as big as the canvas's view and placed just
// under it (flipped on macOS: coordinates from the top left, as the app's)
id mb_views_root(CGRect frame);
// whether the pointer at (x, y) (the app's points) goes to a web view under
// the canvas (the canvas's view lets it through)
int mb_views_pass_through(double x, double y);
// who takes a finger (or the wheel) at (x, y) over a page under the canvas: "all", "through", "pinch" or "vertical"
// (ui's NativeView::touch), its slop in points; NULL where there is no page
const char *mb_views_touch_at(double x, double y, double *slop);
// how many views are open; their current content drawn into ctx (a bitmap of
// the canvas's size in pixels, scale pixels per point), for snapshots
int mb_views_count(void);
void mb_views_draw_under(CGContextRef ctx, double scale);
// whether a view was put elsewhere on the screen (moved, shown, hidden, closed) since this was last asked: the frame
// presented now shows its hole there, so it is presented in the same Core Animation transaction (apple_render.m)
int mb_views_take_moved(void);
// the image of a native view's hole (kind 9: this + the view's id; src/hostapi/host.mbt view_tex_base)
#define MB_VIEW_TEX 8388608
// The frosts of glass over native views (apple_render.m glass_through), as a frame is presented: n of them, each
// MB_FROST_N numbers (what of it shows x0 y0 x1 y1, its rect x y w h, its corners (top left, then round it), its blur,
// saturation, opacity, and the view over which it goes: the last whose hole was painted before it), the others gone.
// Whether it can (else glass over a view frosts it as before: none of the view).
#define MB_FROSTS 16
#define MB_FROST_N 16
int mb_views_frost(int n, const double *frosts);
