// A file's bytes for the skia tests on native (files.mbt), empty when it cannot be read. Plain C: no host's.
#include <stdio.h>
#include "moonbit.h"

moonbit_bytes_t mbui_skiatest_read_file(moonbit_bytes_t path) {
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

// Writes a file (for looking at a test's picture); 0 when it could not.
int32_t mbui_skiatest_write_file(moonbit_bytes_t path, moonbit_bytes_t data) {
  FILE *f = fopen((const char *)path, "wb");
  if (!f) return 0;
  size_t n = Moonbit_array_length(data);
  size_t put = n ? fwrite(data, 1, n, f) : 0;
  fclose(f);
  return put == n;
}
