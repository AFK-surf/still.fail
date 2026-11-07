#include "moonbit.h"
#include <stdint.h>
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
