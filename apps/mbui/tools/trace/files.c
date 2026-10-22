// What the trace tool asks of the system: a file whole, a file written, stdout and stderr, an exit.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

static int32_t ok;

static char *cstr(moonbit_bytes_t b) {
  int32_t n = Moonbit_array_length(b);
  char *s = malloc((size_t)n + 1);
  memcpy(s, b, (size_t)n);
  s[n] = 0;
  return s;
}

moonbit_bytes_t sft_read(moonbit_bytes_t path) {
  char *p = cstr(path);
  FILE *f = fopen(p, "rb");
  free(p);
  ok = 0;
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)(n < 0 ? 0 : n), 0);
  size_t got = n > 0 ? fread(out, 1, (size_t)n, f) : 0;
  fclose(f);
  ok = (long)got == n;
  return out;
}

int32_t sft_ok(void) { return ok; }

int32_t sft_write(moonbit_bytes_t path, moonbit_bytes_t data) {
  char *p = cstr(path);
  FILE *f = fopen(p, "wb");
  free(p);
  if (!f) return 0;
  size_t n = (size_t)Moonbit_array_length(data);
  int good = fwrite(data, 1, n, f) == n;
  return fclose(f) == 0 && good;
}

void sft_out(moonbit_bytes_t s, int32_t err) {
  FILE *f = err ? stderr : stdout;
  fwrite(s, 1, (size_t)Moonbit_array_length(s), f);
  fflush(f);
}

moonbit_bytes_t sft_getenv(moonbit_bytes_t name) {
  char *n = cstr(name);
  const char *v = getenv(n);
  free(n);
  ok = v != NULL;
  if (!v) return moonbit_make_bytes(0, 0);
  size_t k = strlen(v);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)k, 0);
  memcpy(out, v, k);
  return out;
}

void sft_exit(int32_t code) { exit(code); }

#if defined(_WIN32)
#include <direct.h>
#define getcwd _getcwd
#else
#include <unistd.h>
#endif

moonbit_bytes_t sft_getcwd(void) {
  char buf[4096];
  if (!getcwd(buf, sizeof buf)) buf[0] = 0;
  size_t k = strlen(buf);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)k, 0);
  memcpy(out, buf, k);
  return out;
}
