// mbui-render's few needs from the system: a file read whole (as UTF-16 text, or as bytes), a line said, and a while
// for an image's decode to be told. The drawing is the host's offscreen path (mb_render_init_offscreen,
// mb_render_draw_timed, mb_render_snapshot): src/host/apple_render.m on macOS, win_render.cpp on Windows (built by
// scripts/win.sh), android_host.c on Android (scripts/android.sh, this file one of its extra C files:
// scripts/render_android.sh).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#elif defined(__ANDROID__)
#include <android/log.h>
#endif
#include "moonbit.h"

static char *utf8(moonbit_string_t s) {
  int32_t n = Moonbit_array_length(s);
  char *out = malloc((size_t)n * 3 + 1), *o = out;
  for (int32_t i = 0; i < n; i++) {
    uint32_t c = s[i];
    if (c >= 0xD800 && c < 0xDC00 && i + 1 < n) c = 0x10000 + ((c - 0xD800) << 10) + (s[++i] - 0xDC00);
    if (c < 0x80) *o++ = (char)c;
    else if (c < 0x800) { *o++ = 0xC0 | (c >> 6); *o++ = 0x80 | (c & 63); }
    else if (c < 0x10000) { *o++ = 0xE0 | (c >> 12); *o++ = 0x80 | ((c >> 6) & 63); *o++ = 0x80 | (c & 63); }
    else { *o++ = 0xF0 | (c >> 18); *o++ = 0x80 | ((c >> 12) & 63); *o++ = 0x80 | ((c >> 6) & 63); *o++ = 0x80 | (c & 63); }
  }
  *o = 0;
  return out;
}

static unsigned char *slurp(moonbit_string_t path, long *len) {
  char *p = utf8(path);
  FILE *f = fopen(p, "rb");
  free(p);
  *len = -1;
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  *len = ftell(f);
  fseek(f, 0, SEEK_SET);
  unsigned char *buf = malloc(*len > 0 ? *len : 1);
  if (fread(buf, 1, *len, f) != (size_t)*len) *len = -1;
  fclose(f);
  return buf;
}

// the file at `path` as bytes (empty when it cannot be read)
moonbit_bytes_t mbr_read_bytes(moonbit_string_t path) {
  long n;
  unsigned char *b = slurp(path, &n);
  if (n < 0) n = 0;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n > 0) memcpy(out, b, n);
  free(b);
  return out;
}

// the file at `path` (UTF-8) as text ("" when it cannot be read)
moonbit_string_t mbr_read_text(moonbit_string_t path) {
  long n;
  unsigned char *b = slurp(path, &n);
  if (n < 0) n = 0;
  uint16_t *u = malloc(((size_t)n + 1) * 2 * sizeof(uint16_t));
  int32_t k = 0;
  for (long i = 0; i < n;) {
    uint32_t c = b[i];
    int extra = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
    c = extra == 3 ? c & 7 : extra == 2 ? c & 15 : extra == 1 ? c & 31 : c;
    i++;
    for (int e = 0; e < extra && i < n; e++, i++) c = (c << 6) | (b[i] & 63);
    if (c >= 0x10000) {
      c -= 0x10000;
      u[k++] = 0xD800 + (c >> 10);
      u[k++] = 0xDC00 + (c & 1023);
    } else {
      u[k++] = (uint16_t)c;
    }
  }
  moonbit_string_t out = moonbit_make_string(k, 0);
  memcpy(out, u, (size_t)k * 2);
  free(u);
  free(b);
  return out;
}

// the process's environment variable `name` ("" when unset)
moonbit_string_t mbr_arg(moonbit_string_t name) {
  char *n = utf8(name);
  const char *v = getenv(n);
  free(n);
  if (!v) v = "";
  int32_t k = 0;
  size_t len = strlen(v);
  uint16_t *u = malloc((len + 1) * 2 * sizeof(uint16_t));
  for (size_t i = 0; i < len;) {
    uint32_t c = (unsigned char)v[i];
    int extra = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
    c = extra == 3 ? c & 7 : extra == 2 ? c & 15 : extra == 1 ? c & 31 : c;
    i++;
    for (int e = 0; e < extra && i < len; e++, i++) c = (c << 6) | ((unsigned char)v[i] & 63);
    if (c >= 0x10000) {
      c -= 0x10000;
      u[k++] = 0xD800 + (c >> 10);
      u[k++] = 0xDC00 + (c & 1023);
    } else {
      u[k++] = (uint16_t)c;
    }
  }
  moonbit_string_t out = moonbit_make_string(k, 0);
  memcpy(out, u, (size_t)k * 2);
  free(u);
  return out;
}

void mbr_say(moonbit_string_t s) {
  char *u = utf8(s);
#if defined(__ANDROID__)
  // (logcat: where scripts/render_android.sh reads that the picture is written)
  __android_log_print(ANDROID_LOG_INFO, "mbui", "%s", u);
#else
  fprintf(stderr, "%s\n", u);
#endif
  free(u);
}

#if defined(__APPLE__)
// the main run loop turned for `ms` (what is told on the main queue, an image decoded, is handled)
void mbr_spin(double ms) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, ms / 1000.0, false); }

// the last frame drawn, as a PNG (apple_render.m)
int mb_render_snapshot(const char *path);

int32_t mbr_snapshot(moonbit_string_t path) {
  char *p = utf8(path);
  int ok = mb_render_snapshot(p);
  free(p);
  return ok;
}
#elif defined(_WIN32)
// the thread's messages handled for `ms` (WIC's decodes are told to the image table directly: win_image.cpp)
void mbr_spin(double ms) {
  MSG m;
  while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) DispatchMessageW(&m);
  Sleep((DWORD)ms);
}

// the last frame drawn, as a PNG (win_render.cpp), at a path in UTF-16
int mb_render_snapshot(const wchar_t *path);

int32_t mbr_snapshot(moonbit_string_t path) {
  int32_t n = Moonbit_array_length(path);
  wchar_t *w = malloc(((size_t)n + 1) * sizeof(wchar_t));
  memcpy(w, path, (size_t)n * 2);
  w[n] = 0;
  int ok = mb_render_snapshot(w);
  free(w);
  return ok;
}
#else
// Android (android_host.c): the image uploads that came meanwhile done on this thread, the GL one
void mb_render_spin(double ms);
void mbr_spin(double ms) { mb_render_spin(ms); }

int mb_render_snapshot(const char *path);

int32_t mbr_snapshot(moonbit_string_t path) {
  char *p = utf8(path);
  int ok = mb_render_snapshot(p);
  free(p);
  return ok;
}
#endif
