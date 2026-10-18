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
void mb_atlas_upload(int x, int y, int w, int h, const void *rgba);
extern int mb_atlas_size;

// images (apple_image.m): the texture of a decoded image, nil if not ready
id<MTLTexture> mb_image_texture(int iid);

// text (apple_text.m)
extern double mb_text_scale;
CTFontRef mb_platform_font(double size, int weight); // per platform
moonbit_string_t mb_string_from_ns(NSString *s);
NSString *mb_ns_from_string(moonbit_string_t s);

// shared helpers (per platform)
double mb_now_ms(void);
