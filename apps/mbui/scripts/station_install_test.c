// src/host/station_install.h's tests: what the Mac's, Windows' and Linux's hosts hand the station's installer for the
// app's `install {…}` and `update {…}` (the ask as the app sends it: sfbase's local_station.mbt):
//   cc -Wall -I src/host scripts/station_install_test.c -o out/station_install_test && out/station_install_test
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "station_install.h"

static int failed;

#define CHECK(c)                                                      \
  do {                                                                \
    if (!(c)) {                                                       \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                     \
    }                                                                 \
  } while (0)

static void same(int line, const char *what, const char *got, const char *want) {
  if (!got || strcmp(got, want)) {
    fprintf(stderr, "%s:%d: %s\n  gave %s\n  want %s\n", __FILE__, line, what, got ? got : "(null)", want);
    failed = 1;
  }
}
#define SAME(what, got, want) same(__LINE__, what, got, want)

// what each of the three hands for `json`: the Linux script, the Windows command line, the Mac's arguments joined
// by " | "; 0 where the ask is refused
static int hand(const char *json, char **sh, char **ps, char *mac, size_t cap) {
  station_ask a;
  if (!station_ask_read(json, &a)) return 0;
  *sh = station_sh_script(&a);
  *ps = station_ps_command(&a);
  const char *argv[8];
  int n = station_mac_args(&a, argv);
  mac[0] = 0;
  for (int i = 0; i < n; i++) {
    if (i) strncat(mac, " | ", cap - strlen(mac) - 1);
    strncat(mac, argv[i], cap - strlen(mac) - 1);
  }
  int beta = a.beta;
  station_ask_free(&a);
  return 1 + beta;
}

#define MAC_SCRIPT "f=$(mktemp) && curl -fsSL \"$0/install.sh\" -o \"$f\" && sh \"$f\" \"$@\"; s=$?; rm -f \"$f\"; exit $s"
#define PS_HEAD                                                                                     \
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding = " \
  "[Text.Encoding]::UTF8; & ([scriptblock]::Create((irm '"

int main(void) {
  (void)jnum;  // (mini_json.h's, which the header has no use for)
  char *sh = NULL, *ps = NULL, mac[1024];

  // install into a safe-mode workspace: the token, then the workspace lock's hash it pins (#5540)
  CHECK(hand("{\"origin\":\"https://still.fail\",\"token\":\"tok_A1-b.c\",\"lock\":\"9f3a0c\",\"channel\":\"stable\"}",
             &sh, &ps, mac, sizeof mac) == 1);
  SAME("linux, install with a lock", sh, "curl -fsSL 'https://still.fail/install.sh' | sh -s -- tok_A1-b.c 9f3a0c");
  SAME("windows, install with a lock", ps, PS_HEAD "https://still.fail/install.ps1'))) tok_A1-b.c 9f3a0c\"");
  SAME("mac, install with a lock", mac, "-c | " MAC_SCRIPT " | https://still.fail | tok_A1-b.c | 9f3a0c");
  free(sh), free(ps);

  // install into a workspace with no lock; the beta channel
  CHECK(hand("{\"origin\":\"https://beta.still.fail\",\"token\":\"t1\",\"channel\":\"beta\"}", &sh, &ps, mac,
             sizeof mac) == 2);
  SAME("linux, install", sh, "curl -fsSL 'https://beta.still.fail/install.sh' | sh -s -- t1 ");
  SAME("windows, install", ps, PS_HEAD "https://beta.still.fail/install.ps1'))) t1 \"");
  SAME("mac, install", mac, "-c | " MAC_SCRIPT " | https://beta.still.fail | t1");
  free(sh), free(ps);

  // update: no token, and a lock without one is not handed (install.sh's second is after the token only)
  CHECK(hand("{\"origin\":\"http://127.0.0.1:8787\",\"lock\":\"9f3a0c\",\"channel\":\"stable\"}", &sh, &ps, mac,
             sizeof mac) == 1);
  SAME("linux, update", sh, "curl -fsSL 'http://127.0.0.1:8787/install.sh' | sh -s --  ");
  SAME("windows, update", ps, PS_HEAD "http://127.0.0.1:8787/install.ps1')))  \"");
  SAME("mac, update", mac, "-c | " MAC_SCRIPT " | http://127.0.0.1:8787");
  free(sh), free(ps);

  // refused whole, never a field dropped: no origin, one not http(s), a quote, a space, a semicolon, not an object
  const char *refused[] = {
      "{\"token\":\"t\"}",
      "{\"origin\":\"file:///etc\",\"token\":\"t\"}",
      "{\"origin\":\"https://x' ; rm -rf ~ '\",\"token\":\"t\"}",
      "{\"origin\":\"https://x\",\"token\":\"t u\"}",
      "{\"origin\":\"https://x\",\"token\":\"t\",\"lock\":\"a;b\"}",
      "{\"origin\":\"https://x\",\"token\":\"t\",\"lock\":\"a\\\"b\"}",
      "[\"https://x\"]",
      "",
  };
  for (size_t i = 0; i < sizeof refused / sizeof *refused; i++) {
    if (hand(refused[i], &sh, &ps, mac, sizeof mac)) {
      fprintf(stderr, "%s: refused #%zu was handed on: %s\n", __FILE__, i, refused[i]);
      failed = 1;
      free(sh), free(ps);
    }
  }

  if (!failed) printf("station_install: ok\n");
  return failed;
}
