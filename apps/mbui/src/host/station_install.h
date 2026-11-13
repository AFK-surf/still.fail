// What a desktop's host hands the station's installer for the app's `install {…}` and `update {…}` (local_station's act:
// still.fail cloud's install.sh, install.ps1): worked out here once for the Mac, Windows and Linux, in plain C with
// nothing of a platform's, so a test links it (scripts/station_install_test.c, run by scripts/check.sh) and holds what
// each of the three hands. A test of the app links no host (mbui's AGENTS.md), so this was what nothing held: 2026-11-11
// the three dropped the workspace lock's hash on the way to the installer, the Tester's ask carrying it (#5540, #5545).
//
// The ask: {"origin", "token"?, "lock"? (a safe-mode workspace's lock's hash, which the station pins rather than take
// the cloud's word: workspace.enroll's `lock`), "channel": stable | beta}. What goes into a command is held to what a
// URL or a token is made of (a shell's or PowerShell's quotes are never needed), and an ask with more is refused whole,
// never a field of it dropped; the lock goes only after a token (install.sh's and install.ps1's second).
#ifndef MB_STATION_INSTALL_H
#define MB_STATION_INSTALL_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef MB_MINI_JSON_H
#include "mini_json.h"  // (mbui's src/host, on the include path; or included before this, as mac_station.m does)
#endif

typedef struct {
  char *origin, *token, *lock;  // "" for none
  int beta;
} station_ask;

// nothing but what a URL or a token is made of (ASCII)
static int station_plain(const char *s) {
  for (; *s; s++) {
    char c = *s;
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || strchr(":/.-_~?&=%+", c)))
      return 0;
  }
  return 1;
}

static void station_ask_free(station_ask *a) {
  free(a->origin), free(a->token), free(a->lock);
  a->origin = a->token = a->lock = NULL;
}

static char *station_dup(const char *s) {
  size_t n = strlen(s) + 1;
  char *d = (char *)malloc(n);
  if (d) memcpy(d, s, n);
  return d;
}

// The ask's JSON (UTF-8) read into `out`: 1, or 0 refused (not an object, an origin not http(s), a field with more than
// a URL's or a token's characters), `out` then holding nothing.
static int station_ask_read(const char *json, station_ask *out) {
  memset(out, 0, sizeof *out);
  if (!json) return 0;
  jv ask = {0};
  const char *p = json;
  if (!jparse(&p, &ask, 0)) return 0;
  int ok = ask.kind == 'o';
  if (ok) {
    const char *origin = jtext(&ask, "origin"), *token = jtext(&ask, "token");
    const char *lock = token[0] ? jtext(&ask, "lock") : "";
    ok = (!strncmp(origin, "https://", 8) || !strncmp(origin, "http://", 7)) && station_plain(origin) &&
         station_plain(token) && station_plain(lock);
    if (ok) {
      out->origin = station_dup(origin), out->token = station_dup(token), out->lock = station_dup(lock);
      out->beta = !strcmp(jtext(&ask, "channel"), "beta");
      ok = out->origin && out->token && out->lock;
      if (!ok) station_ask_free(out);
    }
  }
  jv_free(&ask);
  return ok;
}

static char *station_printf2(const char *f, const char *a, const char *b, const char *c) {
  int n = snprintf(NULL, 0, f, a, b, c);
  char *s = n < 0 ? NULL : (char *)malloc((size_t)n + 1);
  if (s) snprintf(s, (size_t)n + 1, f, a, b, c);
  return s;
}

// Linux: what `sh -c` runs (malloc'd).
static char *station_sh_script(const station_ask *a) {
  return station_printf2("curl -fsSL '%s/install.sh' | sh -s -- %s %s", a->origin, a->token, a->lock);
}

// Windows: the command line CreateProcess runs (UTF-8, malloc'd). OutputEncoding: what it says in UTF-8, as
// local_run reads it; by default the system's code page, GBK in Chinese.
static char *station_ps_command(const station_ask *a) {
  return station_printf2(
      "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding = [Text.Encoding]::UTF8; "
      "& ([scriptblock]::Create((irm '%s/install.ps1'))) %s %s\"",
      a->origin, a->token, a->lock);
}

// The Mac: /bin/sh's arguments, into `argv` (6 at least, NULL-ended; into `a` and static text), how many said. The
// script is fetched to a file first and run with sh (`$0` the origin, `$@` the token and the lock).
static int station_mac_args(const station_ask *a, const char **argv) {
  int n = 0;
  argv[n++] = "-c";
  argv[n++] = "f=$(mktemp) && curl -fsSL \"$0/install.sh\" -o \"$f\" && sh \"$f\" \"$@\"; s=$?; rm -f \"$f\"; exit $s";
  argv[n++] = a->origin;
  if (a->token[0]) {
    argv[n++] = a->token;
    if (a->lock[0]) argv[n++] = a->lock;
  }
  argv[n] = NULL;
  return n;
}

#endif
