// The bench's few needs from the system: process CPU time, the wall clock,
// appending a line to a file. The renderer's offscreen path is in
// src/host/apple_render.m (mb_render_init_offscreen, mb_render_draw_timed).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/resource.h>
#include "moonbit.h"

// user + system time of the process, in ms
double mbb_cpu_ms(void) {
  struct rusage ru;
  getrusage(RUSAGE_SELF, &ru);
  return (ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000.0 +
         (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1000.0;
}

double mbb_unix_time(void) { return (double)time(NULL); }

// UTF-16 to UTF-8 (BMP and surrogate pairs), NUL-terminated; free it
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

// appends `line` and a newline to the file at `path`; 0 when it could not
int32_t mbb_append(moonbit_string_t path, moonbit_string_t line) {
  char *p = utf8(path), *l = utf8(line);
  FILE *f = fopen(p, "a");
  int ok = 0;
  if (f) {
    ok = fprintf(f, "%s\n", l) >= 0;
    fclose(f);
  }
  free(p);
  free(l);
  return ok;
}

// stdout, unbuffered by line, for a progress line rewritten in place
void mbb_print(moonbit_string_t s) {
  char *u = utf8(s);
  fputs(u, stderr);
  fflush(stderr);
  free(u);
}

// the last frame drawn, as a PNG (apple_render.m), to look at a scene
int mb_render_snapshot(const char *path);

int32_t mbb_snapshot(moonbit_string_t path) {
  char *p = utf8(path);
  int ok = mb_render_snapshot(p);
  free(p);
  return ok;
}
