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
void mb_atlas_upload(int x, int y, int w, int h, const void *rgba);
extern int mb_atlas_size;

// text (win_text.cpp)
// rasterize at this many pixels per point; a change starts a new atlas
void mb_text_set_scale(double scale);

#ifdef __cplusplus
}
#endif
