// What mbui's tools ask of the system (tools/sys): files whole, a directory's names, a path's kind, the environment,
// the working directory, stdout and stderr, an exit.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#if defined(_WIN32)
#include <direct.h>
#include <windows.h>
#define getcwd _getcwd
#else
#include <dirent.h>
#include <unistd.h>
#endif
#include "moonbit.h"

static int32_t ok;

static char *cstr(moonbit_bytes_t b) {
  int32_t n = Moonbit_array_length(b);
  char *s = malloc((size_t)n + 1);
  memcpy(s, b, (size_t)n);
  s[n] = 0;
  return s;
}

static moonbit_bytes_t bytes_of(const char *s, size_t n) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  memcpy(out, s, n);
  return out;
}

int32_t tsys_ok(void) { return ok; }

moonbit_bytes_t tsys_read(moonbit_bytes_t path) {
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

int32_t tsys_write(moonbit_bytes_t path, moonbit_bytes_t data) {
  char *p = cstr(path);
  FILE *f = fopen(p, "wb");
  free(p);
  if (!f) return 0;
  size_t n = (size_t)Moonbit_array_length(data);
  int good = fwrite(data, 1, n, f) == n;
  return fclose(f) == 0 && good;
}

// 0 none, 1 a file, 2 a directory, 3 something else
int32_t tsys_kind(moonbit_bytes_t path) {
  char *p = cstr(path);
  struct stat st;
  int r = stat(p, &st);
  free(p);
  if (r != 0) return 0;
  if ((st.st_mode & S_IFMT) == S_IFREG) return 1;
  if ((st.st_mode & S_IFMT) == S_IFDIR) return 2;
  return 3;
}

int32_t tsys_mkdir(moonbit_bytes_t path) {
  char *p = cstr(path);
#if defined(_WIN32)
  int r = _mkdir(p);
#else
  int r = mkdir(p, 0777);
#endif
  free(p);
  return r == 0;
}

int32_t tsys_remove(moonbit_bytes_t path) {
  char *p = cstr(path);
  int r = remove(p);
  free(p);
  return r == 0;
}

// the names in a directory (not . and ..), each ended by a NUL
moonbit_bytes_t tsys_list(moonbit_bytes_t path) {
  char *p = cstr(path);
  size_t cap = 4096, len = 0;
  char *buf = malloc(cap);
#if defined(_WIN32)
  char *pat = malloc(strlen(p) + 3);
  sprintf(pat, "%s\\*", p);
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pat, &fd);
  free(pat);
  if (h != INVALID_HANDLE_VALUE) {
    do {
      const char *n = fd.cFileName;
#else
  DIR *d = opendir(p);
  struct dirent *e;
  if (d) {
    while ((e = readdir(d))) {
      const char *n = e->d_name;
#endif
      if (strcmp(n, ".") == 0 || strcmp(n, "..") == 0) continue;
      size_t k = strlen(n) + 1;
      while (len + k > cap) buf = realloc(buf, cap *= 2);
      memcpy(buf + len, n, k);
      len += k;
#if defined(_WIN32)
    } while (FindNextFileA(h, &fd));
    FindClose(h);
  }
#else
    }
    closedir(d);
  }
#endif
  free(p);
  moonbit_bytes_t out = bytes_of(buf, len);
  free(buf);
  return out;
}

moonbit_bytes_t tsys_getenv(moonbit_bytes_t name) {
  char *n = cstr(name);
  const char *v = getenv(n);
  free(n);
  ok = v != NULL;
  return v ? bytes_of(v, strlen(v)) : moonbit_make_bytes(0, 0);
}

moonbit_bytes_t tsys_getcwd(void) {
  char buf[4096];
  if (!getcwd(buf, sizeof buf)) buf[0] = 0;
  return bytes_of(buf, strlen(buf));
}

void tsys_out(moonbit_bytes_t s, int32_t err) {
  FILE *f = err ? stderr : stdout;
  fwrite(s, 1, (size_t)Moonbit_array_length(s), f);
  fflush(f);
}

void tsys_exit(int32_t code) { exit(code); }

// whether path is a symbolic link itself
int32_t tsys_is_link(moonbit_bytes_t path) {
  char *p = cstr(path);
  struct stat st;
  int r = lstat(p, &st);
  free(p);
  return r == 0 && (st.st_mode & S_IFMT) == S_IFLNK;
}
