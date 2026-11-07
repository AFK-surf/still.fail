// A sign-in in the browser that comes back to this machine, for the Linux host (host_native.mbt `browser_login`), on
// the loopback listener of linux_listen.c: win_browser_login.c's way, its Linux twin. Listen on 127.0.0.1 at a port the
// system picks, let the app make its login page with http://127.0.0.1:<port><path> as where to come back, open it in
// the browser, take the one GET that comes back to <path> under that host name, answer it, stop listening. Nothing here
// knows whose sign-in it is: the app checks what came back (its state) and exchanges it. Opening is $BROWSER (a command
// given the address, as a station's remote login sets it, and as CI's runs stand in for a person with it), else the
// system's browser (GIO's default for the URI: the desktop portal's where there is one). The app polls it each frame (a
// frame is asked for when the browser comes back).
#include <gio/gio.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "linux.h"
#include "listen_api.h"

#include "browser_login.h"

static char *utf8(moonbit_string_t s) {
  char *u = g_utf16_to_utf8((const gunichar2 *)s, Moonbit_array_length(s), NULL, NULL, NULL);
  char *out = strdup(u ? u : "");
  g_free(u);
  return out;
}

int32_t mb_host_browser_login_open(int32_t id, moonbit_string_t url) {
  (void)id;
  char *u = utf8(url);
  int ok = 0;
  const char *browser = getenv("BROWSER");
  if (browser && *browser) {
    // its first program (BROWSER is a ':'-separated list), given the address; not waited for: a browser started
    // directly keeps running after us
    char *first = g_strndup(browser, strcspn(browser, ":"));
    char *argv[] = {first, u, NULL};
    GError *e = NULL;
    ok = g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &e);
    if (!ok) fprintf(stderr, "browser login: BROWSER did not start (%s)\n", e ? e->message : "?");
    if (e) g_error_free(e);
    g_free(first);
  } else {
    ok = g_app_info_launch_default_for_uri(u, NULL, NULL);
  }
  free(u);
  return ok;
}

moonbit_string_t mb_host_browser_login_back(int32_t id) {
  pthread_rwlock_rdlock(&lock);
  login *l = find(id);
  glong n = 0;
  gunichar2 *w = l && l->back ? g_utf8_to_utf16(l->back, -1, NULL, &n, NULL) : NULL;
  pthread_rwlock_unlock(&lock);
  moonbit_string_t out = moonbit_make_string_raw(w ? (int32_t)n : 0);
  if (w && n) memcpy(out, w, (size_t)n * 2);
  g_free(w);
  return out;
}


// This device's password manager (host_native.mbt `pw_*`): none here (apple_passwords.m, win_passwords.c).
int32_t mb_host_passwords_able(void) { return 0; }
int32_t mb_host_passwords_run(moonbit_string_t args) { (void)args; return 0; }
moonbit_string_t mb_host_passwords_out(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_passwords_end(int32_t id) { (void)id; }

// The system's autofill (host_native.mbt `af_*`): none here (android_host.c).
int32_t mb_host_autofill_able(void) { return 0; }
int32_t mb_host_autofill_ask(moonbit_string_t host) { (void)host; return 0; }
moonbit_string_t mb_host_autofill_take(void) { return moonbit_make_string_raw(0); }
void mb_host_autofill_end(void) {}

// This device's passkeys (host_native.mbt `wa_*`): none here (win_passkeys.c).
int32_t mb_host_passkeys_able(void) { return 0; }
int32_t mb_host_passkeys_get(moonbit_string_t ask) { (void)ask; return 0; }
moonbit_string_t mb_host_passkeys_out(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_passkeys_end(int32_t id) { (void)id; }
