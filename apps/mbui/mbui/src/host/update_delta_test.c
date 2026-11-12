// update_delta.h run from the command line, for test/delta-c.test.ts (which compiles it with cc and holds it to
// scripts/delta.ts and node's zlib). Not part of any app.
//   update_delta_test apply OLD_DIR DELTA OUT [MADE_SIZE]   0 made, else the reason on stderr and 1
//   update_delta_test inflate IN OUT CAP                    a raw deflate stream inflated (at most CAP bytes)
//   update_delta_test sha256 FILE                           its SHA-256 in hex
#include "update_delta.h"

static unsigned char *read_file(const char *path, size_t *n) {
  FILE *f = fopen(path, "rb");
  unsigned char *b = NULL;
  size_t cap = 0, have = 0;
  if (!f) return NULL;
  for (;;) {
    size_t k;
    if (have == cap) {
      unsigned char *g = (unsigned char *)realloc(b, cap = cap ? cap * 2 : 65536);
      if (!g) {
        free(b);
        fclose(f);
        return NULL;
      }
      b = g;
    }
    k = fread(b + have, 1, cap - have, f);
    if (k == 0) break;
    have += k;
  }
  fclose(f);
  *n = have;
  return b;
}

static unsigned char *read_old(void *ctx, const char *path, size_t *size) {
  const char *dir = (const char *)ctx;
  size_t dn = strlen(dir), pn = strlen(path);
  char *full = (char *)malloc(dn + pn + 2);
  unsigned char *b;
  if (!full) return NULL;
  memcpy(full, dir, dn);
  full[dn] = '/';
  memcpy(full + dn + 1, path, pn + 1);
  b = read_file(full, size);
  free(full);
  return b;
}

static int write_out(void *ctx, const unsigned char *b, size_t n) { return fwrite(b, 1, n, (FILE *)ctx) == n; }

int main(int argc, char **argv) {
  size_t n = 0;
  unsigned char *in;
  if (argc >= 5 && !strcmp(argv[1], "apply")) {
    const char *why;
    FILE *out;
    in = read_file(argv[3], &n);
    if (!in) return fprintf(stderr, "no %s\n", argv[3]), 2;
    out = fopen(argv[4], "wb");
    if (!out) return fprintf(stderr, "can't write %s\n", argv[4]), 2;
    why = ud_apply(in, n, read_old, argv[2], write_out, out, argc >= 6 ? strtoull(argv[5], NULL, 10) : 0);
    if (fclose(out) != 0 && !why) why = "the made package could not be written";
    free(in);
    if (why) return fprintf(stderr, "%s\n", why), 1;
    return 0;
  }
  if (argc >= 5 && !strcmp(argv[1], "inflate")) {
    size_t cap = (size_t)strtoull(argv[4], NULL, 10), made = 0, took = 0;
    unsigned char *out = (unsigned char *)malloc(cap ? cap : 1);
    const char *why;
    FILE *f;
    in = read_file(argv[2], &n);
    if (!in || !out) return fprintf(stderr, "no %s\n", argv[2]), 2;
    why = ud_inflate(in, n, out, cap, &made, &took);
    free(in);
    if (!why && took != n) why = "it holds more than its deflate stream";
    f = why ? NULL : fopen(argv[3], "wb");
    if (f && fwrite(out, 1, made, f) != made) why = "not written";
    if (f) fclose(f);
    free(out);
    if (why) return fprintf(stderr, "%s\n", why), 1;
    return 0;
  }
  if (argc >= 3 && !strcmp(argv[1], "sha256")) {
    ud_sha256 s;
    unsigned char md[32];
    size_t at = 0;
    int i;
    in = read_file(argv[2], &n);
    if (!in) return fprintf(stderr, "no %s\n", argv[2]), 2;
    ud_sha256_init(&s);
    // (in uneven pieces, so the buffering is tried)
    for (i = 0; at < n; i++) {
      size_t k = (size_t)(i * 37 % 200 + 1);
      if (k > n - at) k = n - at;
      ud_sha256_update(&s, in + at, k);
      at += k;
    }
    ud_sha256_final(&s, md);
    free(in);
    for (i = 0; i < 32; i++) printf("%02x", md[i]);
    printf("\n");
    return 0;
  }
  fprintf(stderr, "usage: update_delta_test apply OLD_DIR DELTA OUT [MADE_SIZE] | inflate IN OUT CAP | sha256 FILE\n");
  return 2;
}
