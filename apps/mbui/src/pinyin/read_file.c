// A file's bytes (the keyboard's words, where its host put them: load_native.mbt), empty when it cannot be read.
#include <stdio.h>
#include "moonbit.h"

moonbit_bytes_t stillfail_pinyin_read_file(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "rb");
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n < 0) n = 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  size_t got = n ? fread(b, 1, (size_t)n, f) : 0;
  fclose(f);
  if ((long)got != n) return moonbit_make_bytes(0, 0);
  return b;
}

// `data` written to the file at `path` (the keyboard's own: what the person picked), through a file beside it put in
// its place, so a write cut short leaves the last one whole. 1 when written.
int32_t stillfail_pinyin_write_file(moonbit_bytes_t path, moonbit_bytes_t data) {
  char tmp[4096];
  int n = snprintf(tmp, sizeof tmp, "%s.new", (const char *)path);
  if (n < 0 || n >= (int)sizeof tmp) return 0;
  FILE *f = fopen(tmp, "wb");
  if (!f) return 0;
  size_t len = Moonbit_array_length(data);
  size_t put = len ? fwrite(data, 1, len, f) : 0;
  if (fclose(f) != 0 || put != len) return 0;
  return rename(tmp, (const char *)path) == 0;
}
