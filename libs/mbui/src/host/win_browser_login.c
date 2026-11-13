// A sign-in in the browser that comes back to this machine, for the Windows host (host_native.mbt `browser_login`), on
// the loopback listener of win_listen.c: apple_browser_login.m's way. Listen on 127.0.0.1 at a port the system picks,
// let the app make its login page with http://127.0.0.1:<port><path> as where to come back, open it in the browser,
// take the one GET that comes back to <path> under that host name, answer it, stop listening. Nothing here knows whose
// sign-in it is: the app checks what came back (its state) and exchanges it. Opening is $BROWSER (a command given the
// address, as a station's remote login sets it, and as CI's runs stand in for a person with it), else the system's
// browser (ShellExecute). The app polls it each frame (a frame is asked for when the browser comes back).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "listen_api.h"
#include "win.h"

#pragma comment(lib, "shell32.lib")

typedef struct login {
  struct login *next;
  int id, lid, port;
  char *path;
  char *done;  // where the browser is sent on to once it has come back ("": this host's page)
  char *back;  // where the browser came back to, once it has (under `lock`)
} login;

static SRWLOCK lock = SRWLOCK_INIT;
static login *logins;
static int login_next;

static login *find(int id) {
  for (login *l = logins; l; l = l->next)
    if (l->id == id) return l;
  return NULL;
}

static char *utf8(moonbit_string_t s) {
  int n = Moonbit_array_length(s);
  int bytes = WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, NULL, 0, NULL, NULL);
  char *u = malloc((size_t)bytes + 1);
  WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, u, bytes, NULL, NULL);
  u[bytes] = 0;
  return u;
}

static WCHAR *wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  WCHAR *w = malloc((size_t)n * sizeof(WCHAR));
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}

// The JSON string after `"key":` in win_listen.c's request (`from` onward), unescaped into `out` (cap bytes): its end,
// or NULL when there is none.
static const char *json_string(const char *from, const char *key, char *out, size_t cap) {
  char pat[64];
  snprintf(pat, sizeof pat, "\"%s\":\"", key);
  const char *p = strstr(from, pat);
  if (!p) return NULL;
  p += strlen(pat);
  size_t o = 0;
  for (; *p && *p != '"'; p++) {
    char c = *p;
    if (c == '\\' && p[1]) {
      p++;
      if (*p == 'u') {
        unsigned v = 0;
        sscanf(p + 1, "%4x", &v);
        p += 4;
        c = (char)v;  // only control characters are escaped so
      } else {
        c = *p;
      }
    }
    if (o + 1 < cap) out[o++] = c;
  }
  out[o] = 0;
  return p;
}

static const char page_ok[] =
    "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>Signed in</title>"
    "<body style=\"font:16px system-ui,sans-serif;margin:3em 2em;color:#1c1c1e\"><p>"
    "\xe5\xb7\xb2\xe5\x9b\x9e\xe5\x88\xb0 app\xef\xbc\x8c\xe5\x8f\xaf\xe4\xbb\xa5\xe5\x85\xb3\xe6\x8e\x89\xe8\xbf\x99\xe4\xb8\xaa\xe9\xa1\xb5\xe9\x9d\xa2"
    " \xc2\xb7 Back in the app: you can close this page</p></body>";
static const char page_no[] =
    "<!doctype html><meta charset=utf-8><title>Not found</title><body style=\"font:16px system-ui,sans-serif;margin:3em 2em\"><p>"
    "\xe8\xbf\x99\xe4\xb8\x8d\xe6\x98\xaf\xe8\xbf\x99\xe6\xac\xa1\xe7\x99\xbb\xe5\xbd\x95\xe7\x9a\x84\xe5\x9c\xb0\xe5\x9d\x80"
    " \xc2\xb7 Not this sign-in</p></body>";

// On the listener's queue: the request that came, answered at once (only the one this sign-in waits for is taken).
static void took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  (void)body, (void)blen;
  if (!json) return;
  int id = (int)(intptr_t)ctx;
  char *j = malloc(len + 1);
  memcpy(j, json, len);
  j[len] = 0;
  AcquireSRWLockShared(&lock);
  login *l = find(id);
  int lid = l ? l->lid : 0, port = l ? l->port : 0;
  char *want = l ? _strdup(l->path) : NULL;
  char *done = l ? _strdup(l->done) : NULL;
  ReleaseSRWLockShared(&lock);
  if (!l) {
    free(j);
    return;
  }
  char method[16] = "", path[4096] = "", host[300] = "", request[24] = "";
  json_string(j, "method", method, sizeof method);
  json_string(j, "path", path, sizeof path);
  const char *r = strstr(j, "\"request\":");
  if (r) snprintf(request, sizeof request, "%s", r + 10);
  // the Host header, whatever its case: ["Host","127.0.0.1:<port>"]
  const char *hs = strstr(j, "\"headers\":[");
  for (const char *h = hs; h && (h = strstr(h, "[\"")) != NULL; h += 2) {
    if (_strnicmp(h + 2, "host\",\"", 7) != 0) continue;
    const char *v = h + 9;
    size_t o = 0;
    while (*v && *v != '"' && *v != '\\' && o + 1 < sizeof host) host[o++] = *v++;
    host[o] = 0;
    break;
  }
  char *q = strchr(path, '?');
  size_t bare = q ? (size_t)(q - path) : strlen(path);
  char a[64], b[64];
  snprintf(a, sizeof a, "127.0.0.1:%d", port);
  snprintf(b, sizeof b, "localhost:%d", port);
  // Only the browser coming back to this sign-in: its address (a page elsewhere naming 127.0.0.1 by another name,
  // DNS rebinding, is not), its path, a GET.
  int ours = (strcmp(host, a) == 0 || strcmp(host, b) == 0) && strcmp(method, "GET") == 0 && strlen(want) == bare &&
             strncmp(path, want, bare) == 0;
  if (ours && *done) {
    // on to the app's page saying it is done (in its look, the browser's language)
    const char *headers[] = {"Location", done, "Cache-Control", "no-store"};
    mb_listen_respond(lid, strtol(request, NULL, 10), 302, headers, 2, NULL, 0);
  } else {
    const char *headers[] = {"Content-Type", "text/html; charset=utf-8", "Cache-Control", "no-store"};
    const char *page = ours ? page_ok : page_no;
    mb_listen_respond(lid, strtol(request, NULL, 10), ours ? 200 : 404, headers, 2, (const uint8_t *)page, strlen(page));
  }
  if (ours) {
    // After the answer (the same queue): nothing else is taken.
    mb_listen_close(lid);
    char *back = malloc(strlen(path) + 64);
    sprintf(back, "http://127.0.0.1:%d%s", port, path);
    AcquireSRWLockExclusive(&lock);
    l = find(id);
    if (l && !l->back) l->back = back, back = NULL;
    ReleaseSRWLockExclusive(&lock);
    free(back);
    mb_app_wake();
  }
  free(want);
  free(done);
  free(j);
}

int32_t mb_host_browser_login_start(moonbit_string_t path, moonbit_string_t done) {
  login *l = calloc(1, sizeof *l);
  l->path = utf8(path);
  l->done = utf8(done);
  AcquireSRWLockExclusive(&lock);
  l->id = ++login_next;
  l->next = logins;
  logins = l;
  ReleaseSRWLockExclusive(&lock);
  char why[160];
  int port = 0;
  int lid = mb_listen_open("127.0.0.1", 0, took, (void *)(intptr_t)l->id, &port, why, sizeof why);
  AcquireSRWLockExclusive(&lock);
  if (!lid) {
    for (login **p = &logins; *p; p = &(*p)->next)
      if (*p == l) {
        *p = l->next;
        break;
      }
    ReleaseSRWLockExclusive(&lock);
    fprintf(stderr, "browser login: %s\n", why);
    free(l->path);
    free(l->done);
    free(l);
    return 0;
  }
  // Set before any request can come: one comes only once the browser has the page, which the port is needed for.
  l->lid = lid;
  l->port = port;
  ReleaseSRWLockExclusive(&lock);
  return l->id;
}

int32_t mb_host_browser_login_port(int32_t id) {
  AcquireSRWLockShared(&lock);
  login *l = find(id);
  int port = l ? l->port : 0;
  ReleaseSRWLockShared(&lock);
  return port;
}

int32_t mb_host_browser_login_open(int32_t id, moonbit_string_t url) {
  (void)id;
  char *u = utf8(url);
  WCHAR *w = wide(u);
  int ok = 0;
  const WCHAR *browser = _wgetenv(L"BROWSER");
  if (browser && *browser) {
    // its first program (BROWSER's list is ':'-separated elsewhere; a Windows path has its own ':', so all of it here)
    size_t n = wcslen(browser) + wcslen(w) + 8;
    WCHAR *cmd = malloc(n * sizeof(WCHAR));
    _snwprintf(cmd, n, L"\"%ls\" \"%ls\"", browser, w);
    cmd[n - 1] = 0;
    STARTUPINFOW si = {sizeof si};
    PROCESS_INFORMATION pi;
    // Not waited for: a browser started directly keeps running after us.
    ok = CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi) != 0;
    if (ok) CloseHandle(pi.hThread), CloseHandle(pi.hProcess);
    else fprintf(stderr, "browser login: BROWSER did not start (%lu)\n", GetLastError());
    free(cmd);
  } else {
    ok = (INT_PTR)ShellExecuteW(NULL, L"open", w, NULL, NULL, SW_SHOWNORMAL) > 32;
  }
  free(w);
  free(u);
  return ok;
}

moonbit_string_t mb_host_browser_login_back(int32_t id) {
  AcquireSRWLockShared(&lock);
  login *l = find(id);
  WCHAR *w = l && l->back ? wide(l->back) : NULL;
  ReleaseSRWLockShared(&lock);
  int n = w ? (int)wcslen(w) : 0;
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, w, (size_t)n * sizeof(WCHAR));
  free(w);
  return out;
}

void mb_host_browser_login_end(int32_t id) {
  AcquireSRWLockExclusive(&lock);
  login *l = find(id);
  if (l)
    for (login **p = &logins; *p; p = &(*p)->next)
      if (*p == l) {
        *p = l->next;
        break;
      }
  ReleaseSRWLockExclusive(&lock);
  if (!l) return;
  mb_listen_close(l->lid);
  free(l->path);
  free(l->done);
  free(l->back);
  free(l);
}
