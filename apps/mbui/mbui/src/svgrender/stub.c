#include "moonbit.h"
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <limits.h>

extern void mbsvg_fonts_add(void *, const uint8_t *, size_t);
extern uint8_t *mbsvg_rasterize_app(void *, const uint8_t *, size_t, uint32_t);
extern void mbsvg_buffer_free(uint8_t *, size_t);

void mbsvg_moon_font(void *db, moonbit_bytes_t data) {
  mbsvg_fonts_add(db, data, Moonbit_array_length(data));
}
moonbit_bytes_t mbsvg_moon_draw(void *db, moonbit_bytes_t data, int32_t side) {
  uint8_t *raw = mbsvg_rasterize_app(db, data, Moonbit_array_length(data), side > 0 ? (uint32_t)side : 0);
  if (!raw) return moonbit_make_bytes(0, 0);
  uint32_t w, h;
  memcpy(&w, raw, 4); memcpy(&h, raw + 4, 4);
  size_t n = 8 + (size_t)w * h * 4;
  if (n > INT32_MAX) { mbsvg_buffer_free(raw, n); return moonbit_make_bytes(0, 0); }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  memcpy(out, raw, n);
  mbsvg_buffer_free(raw, n);
  return out;
}

extern bool mbpng_add(void *, const uint8_t *, size_t, uint32_t);
extern void *mbpng_end(void *);
extern uint8_t *mbpng_output_ptr(void *);
extern size_t mbpng_output_len(void *);
extern void mbpng_output_free(void *);
int32_t mbpng_moon_valid(void *p) { return p != NULL; }
int32_t mbpng_moon_add(void *p, moonbit_bytes_t data, int32_t n) {
  return mbpng_add(p, data, Moonbit_array_length(data), n);
}
moonbit_bytes_t mbpng_moon_end(void *p) {
  void *output = mbpng_end(p);
  if (!output) return moonbit_make_bytes(0, 0);
  size_t n = mbpng_output_len(output);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  memcpy(out, mbpng_output_ptr(output), n);
  mbpng_output_free(output);
  return out;
}
