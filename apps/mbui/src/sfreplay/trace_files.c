// A run's trace file (e2e/traces/NAME.trace) for a native test: from $MBUI_APP_MOD, from the module this file was
// compiled in (__FILE__: src/sfreplay/ under it), or from the directories up from where the test runs.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <direct.h>
#define getcwd _getcwd
#else
#include <unistd.h>
#endif
#include "moonbit.h"

static int32_t found;

static moonbit_bytes_t slurp(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)(n < 0 ? 0 : n), 0);
  size_t got = n > 0 ? fread(out, 1, (size_t)n, f) : 0;
  fclose(f);
  if ((long)got != n) return NULL;
  return out;
}

// dir/e2e/traces/name.trace, if it is there
static moonbit_bytes_t under(const char *dir, const char *name) {
  size_t k = strlen(dir) + strlen(name) + 32;
  char *p = malloc(k);
  snprintf(p, k, "%s/e2e/traces/%s.trace", dir, name);
  moonbit_bytes_t b = slurp(p);
  free(p);
  return b;
}

moonbit_bytes_t sfr_trace_read(moonbit_bytes_t name_b) {
  int32_t n = Moonbit_array_length(name_b);
  char *name = malloc((size_t)n + 1);
  memcpy(name, name_b, (size_t)n);
  name[n] = 0;
  moonbit_bytes_t b = NULL;
  const char *mod = getenv("MBUI_APP_MOD");
  if (mod && *mod) b = under(mod, name);
  if (!b) {
    // (__FILE__: <module>/src/sfreplay/trace_files.c)
    char dir[4096];
    snprintf(dir, sizeof dir, "%s", __FILE__);
    for (int up = 0; up < 3; up++) {
      char *s = strrchr(dir, '/');
      char *t = strrchr(dir, '\\');
      if (t > s) s = t;
      if (!s) {
        dir[0] = 0;
        break;
      }
      *s = 0;
    }
    if (dir[0]) b = under(dir, name);
  }
  if (!b) {
    char dir[4096];
    if (getcwd(dir, sizeof dir)) {
      for (;;) {
        b = under(dir, name);
        if (b) break;
        char *s = strrchr(dir, '/');
        char *t = strrchr(dir, '\\');
        if (t > s) s = t;
        if (!s || s == dir) break;
        *s = 0;
      }
    }
  }
  free(name);
  found = b != NULL;
  return b ? b : moonbit_make_bytes(0, 0);
}

int32_t sfr_trace_found(void) { return found; }

// A flow's steps as a scripted run's (src/sfreplay/emit.mbt, scripts/rerecord.sh): where FLOW_EMIT says (empty: none),
// and the script written there whole.
moonbit_bytes_t sfr_emit_path(void) {
  const char *p = getenv("FLOW_EMIT");
  int32_t n = p ? (int32_t)strlen(p) : 0;
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n > 0) memcpy(out, p, (size_t)n);
  return out;
}

int32_t sfr_write_file(moonbit_bytes_t path_b, moonbit_bytes_t text_b) {
  int32_t n = Moonbit_array_length(path_b);
  char *path = malloc((size_t)n + 1);
  memcpy(path, path_b, (size_t)n);
  path[n] = 0;
  FILE *f = fopen(path, "wb");
  free(path);
  if (!f) return 0;
  size_t len = (size_t)Moonbit_array_length(text_b);
  size_t put = len > 0 ? fwrite(text_b, 1, len, f) : 0;
  fclose(f);
  return put == len;
}
