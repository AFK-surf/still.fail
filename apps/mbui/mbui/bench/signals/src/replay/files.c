// The replay's few needs from the system: a trace file read whole, a monotonic clock.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "moonbit.h"

// the file at `path` (NUL-terminated), whole; empty when it cannot be read
moonbit_bytes_t sbr_read(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "rb");
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  size_t got = fread(b, 1, (size_t)n, f);
  fclose(f);
  if ((long)got != n) return moonbit_make_bytes(0, 0);
  return b;
}

double sbr_now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}
