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
// renders the last presented frame again into memory and writes a PNG
int mb_render_snapshot(const char *path);
// bands above and under the app's view (points) filled with `ground` (0xRRGGBB) in what snapshots write: a phone's
// system bars round a scripted run's window (mac_app.m MBUI_SAFE)
void mb_render_set_bands(double top, double bottom, uint32_t ground);
void mb_atlas_upload(int x, int y, int w, int h, const void *rgba);
extern int mb_atlas_size;

// images (apple_image.m): the texture of a decoded image, nil if not ready
id<MTLTexture> mb_image_texture(int iid);

// text (apple_text.m)
extern double mb_text_scale;
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
