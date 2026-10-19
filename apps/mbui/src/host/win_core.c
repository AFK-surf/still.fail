// The still.fail client core on Windows (core_api.h), as Android runs it: Hermes 0.81.4 in-process on the Rust shell, in
// the engine prebuilt for Windows (apps/mbui/engine as stillfail_engine.dll, beside stillfail_shell.dll: scripts/native.ts
// parts `engine` and `shell`, win32-x64), the core as Hermes bytecode (core.hbc beside the app, or $MB_CORE_BUNDLE:
// scripts/core.sh hermes). What the core says comes back through the engine's `say`, into core_native.c's queue, and a
// frame is asked for (mb_app_wake), in which the host drains it (mbc_frame, win_app.c); the calls only the app does are
// answered here, as android_core.c's CoreHost and apple_core.m do:
//   secure.* (ember hosts/bridge.ts): what the core keeps out of the files it syncs (the lock's signing seed, a vault's
//     key), sealed with DPAPI for this Windows user (CryptProtectData, no prompt ever) in files of <data>\secure, one a
//     key (its UTF-8 in hex). secure.get {key, user} -> {} + the bytes, or {none: true}; secure.set {key, user} + the
//     bytes -> {}; secure.delete {key} -> {}; asking the person (`user`, secure.ask: Windows Hello) is unsupported yet,
//     as on Android and Apple.
//   listen.* (a login's loopback listener, mbui's win_listen.c): listen.open {port, host} -> {id, port};
//     listen.next {id} -> {request, method, path, headers} + the body, or {end: true}; listen.respond {id, request,
//     status, headers} + the body -> {}; listen.close {id} -> {}.
// The app's files are under %LOCALAPPDATA%\fail.still.mbui\core ($MBUI_CORE_DATA instead), its own, never the desktop
// app's. MB_CORE_TRACE=1 says what the core says (its first 300 bytes) and the app's calls on stderr; MB_CORE_DEBUG=1
// the core's debug lines; MBUI_SECURE_TEST=1 round-trips secure.* once as the core starts (SECURE_TEST … on stderr).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <wincrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "core_api.h"
// mbui's own (scripts/win.sh puts its src/host first in cl's include path, CL): the forwarding listen_api.h beside this
// file names mbui where the module's checkout has it, which win.sh's copy of the module does not
#include <listen_api.h>
#include "engine.h"

#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "uuid.lib")
#pragma comment(lib, "stillfail_engine.lib")

void mb_app_wake(void);  // win_app.c: a frame, from any thread

static struct {
  sf_engine *engine;  // under `gate`: answers from other threads look at it there
  SRWLOCK gate;
  mb_core_message_fn on_message;
  void *ctx;
  WCHAR *secure_dir;
} W = {NULL, SRWLOCK_INIT};

static int tracing(void) {
  static int on = -1;
  if (on < 0) on = getenv("MB_CORE_TRACE") != NULL;
  return on;
}

static WCHAR *wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  WCHAR *w = malloc((size_t)(n ? n : 1) * sizeof(WCHAR));
  if (!MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n)) w[0] = 0;
  return w;
}

static char *utf8(const WCHAR *w) {
  int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
  char *s = malloc((size_t)(n ? n : 1));
  if (!WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL)) s[0] = 0;
  return s;
}

static void say_fatal(const char *why) {
  char buf[600];
  int n = snprintf(buf, sizeof buf, "{\"fatal\":\"%s\"}", why);
  fprintf(stderr, "[core] %s\n", why);
  if (W.on_message) W.on_message(buf, (size_t)n, NULL, 0, W.ctx);
  mb_app_wake();
}

// ── answers, from any thread ──

static void answer(uint64_t id, const char *json, const char *error, const uint8_t *bytes, size_t blen) {
  if (tracing()) fprintf(stderr, "[core trace] <- %llu %s%s\n", (unsigned long long)id, error ? "error " : "", error ? error : json);
  AcquireSRWLockShared(&W.gate);
  if (W.engine) sf_engine_complete(W.engine, id, json, json ? strlen(json) : 0, error, error ? strlen(error) : 0, bytes, blen);
  ReleaseSRWLockShared(&W.gate);
}

// ── a little JSON, for the calls' arguments (objects of numbers, strings, booleans and arrays of strings) ──

static const char *ws(const char *p) {
  while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
  return p;
}

static const char *skip_string(const char *p) {
  for (p++; *p; p++) {
    if (*p == '\\' && p[1]) p++;
    else if (*p == '"') return p + 1;
  }
  return NULL;
}

static const char *skip(const char *p) {
  p = ws(p);
  if (*p == '"') return skip_string(p);
  if (*p == '{' || *p == '[') {
    char close = *p == '{' ? '}' : ']';
    int object = *p == '{';
    p = ws(p + 1);
    if (*p == close) return p + 1;
    for (;;) {
      if (object) {
        if (*p != '"' || !(p = skip_string(p))) return NULL;
        p = ws(p);
        if (*p != ':') return NULL;
        p++;
      }
      if (!(p = skip(p))) return NULL;
      p = ws(p);
      if (*p == ',') p = ws(p + 1);
      else if (*p == close) return p + 1;
      else return NULL;
    }
  }
  const char *s = p;
  while (*p && !strchr(",}] \t\r\n", *p)) p++;
  return p == s ? NULL : p;
}

// Where the value of `key` in the object `json` (NUL-terminated) begins; NULL when it has none.
static const char *jget(const char *json, const char *key) {
  const char *p = ws(json);
  if (*p != '{') return NULL;
  p = ws(p + 1);
  size_t kl = strlen(key);
  while (*p == '"') {
    const char *k = p + 1, *e = skip_string(p);
    if (!e) return NULL;
    p = ws(e);
    if (*p != ':') return NULL;
    p = ws(p + 1);
    if ((size_t)(e - 1 - k) == kl && memcmp(k, key, kl) == 0) return p;
    if (!(p = skip(p))) return NULL;
    p = ws(p);
    if (*p != ',') return NULL;
    p = ws(p + 1);
  }
  return NULL;
}

static void put_utf8(char *out, size_t *o, unsigned cp) {
  if (cp < 0x80) out[(*o)++] = (char)cp;
  else if (cp < 0x800) out[(*o)++] = (char)(0xc0 | (cp >> 6)), out[(*o)++] = (char)(0x80 | (cp & 63));
  else if (cp < 0x10000) out[(*o)++] = (char)(0xe0 | (cp >> 12)), out[(*o)++] = (char)(0x80 | ((cp >> 6) & 63)), out[(*o)++] = (char)(0x80 | (cp & 63));
  else out[(*o)++] = (char)(0xf0 | (cp >> 18)), out[(*o)++] = (char)(0x80 | ((cp >> 12) & 63)), out[(*o)++] = (char)(0x80 | ((cp >> 6) & 63)), out[(*o)++] = (char)(0x80 | (cp & 63));
}

// The string at `p` (a JSON string), as UTF-8 (malloc'd); NULL when it is not one.
static char *jstr(const char *p) {
  if (!p || *p != '"') return NULL;
  const char *e = skip_string(p);
  if (!e) return NULL;
  char *out = malloc((size_t)(e - p) * 2 + 1);
  size_t o = 0;
  for (p++; p < e - 1; p++) {
    if (*p != '\\') {
      out[o++] = *p;
      continue;
    }
    p++;
    switch (*p) {
      case 'n': out[o++] = '\n'; break;
      case 't': out[o++] = '\t'; break;
      case 'r': out[o++] = '\r'; break;
      case 'b': out[o++] = '\b'; break;
      case 'f': out[o++] = '\f'; break;
      case 'u': {
        unsigned cp = 0, lo = 0;
        if (sscanf(p + 1, "%4x", &cp) != 1) cp = 0xfffd;
        p += 4;
        if (cp >= 0xd800 && cp < 0xdc00 && p[1] == '\\' && p[2] == 'u' && sscanf(p + 3, "%4x", &lo) == 1 && lo >= 0xdc00 && lo < 0xe000) {
          cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
          p += 6;
        }
        put_utf8(out, &o, cp);
        break;
      }
      default: out[o++] = *p;
    }
  }
  out[o] = 0;
  return out;
}

static int jnum(const char *p, double *out) {
  if (!p) return 0;
  char *end;
  *out = strtod(p, &end);
  return end != p;
}

static int jtrue(const char *p) { return p && strncmp(p, "true", 4) == 0; }

// ── secure.* ──

// <data>\secure\<the key's UTF-8 in hex>
static WCHAR *secure_path(const char *key) {
  size_t n = wcslen(W.secure_dir), k = strlen(key);
  WCHAR *p = malloc((n + 2 + 2 * k) * sizeof(WCHAR));
  memcpy(p, W.secure_dir, n * sizeof(WCHAR));
  p[n] = L'\\';
  for (size_t i = 0; i < k; i++) swprintf(p + n + 1 + 2 * i, 3, L"%02x", (unsigned char)key[i]);
  p[n + 1 + 2 * k] = 0;
  return p;
}

// What DPAPI mixes in (nothing secret: it keeps another program's blobs out of ours).
static DATA_BLOB entropy(void) {
  static char e[] = "fail.still.mbui.core";
  DATA_BLOB b = {(DWORD)strlen(e), (BYTE *)e};
  return b;
}

// 1 and the bytes, 0 none, -1 failed (why in `why`).
static int secure_get(const char *key, uint8_t **out, size_t *len, char *why, size_t wl) {
  WCHAR *path = secure_path(key);
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
  free(path);
  if (f == INVALID_HANDLE_VALUE) {
    DWORD e = GetLastError();
    if (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) return 0;
    snprintf(why, wl, "secure.get: not read (%lu)", e);
    return -1;
  }
  LARGE_INTEGER size;
  GetFileSizeEx(f, &size);
  BYTE *sealed = malloc((size_t)size.QuadPart + 1);
  DWORD got = 0;
  BOOL ok = ReadFile(f, sealed, (DWORD)size.QuadPart, &got, NULL);
  CloseHandle(f);
  DATA_BLOB in = {got, sealed}, plain = {0}, e = entropy();
  if (!ok || !CryptUnprotectData(&in, NULL, &e, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &plain)) {
    snprintf(why, wl, "secure.get: not unsealed (%lu)", GetLastError());
    free(sealed);
    return -1;
  }
  free(sealed);
  *out = malloc(plain.cbData ? plain.cbData : 1);
  memcpy(*out, plain.pbData, plain.cbData);
  *len = plain.cbData;
  SecureZeroMemory(plain.pbData, plain.cbData);
  LocalFree(plain.pbData);
  return 1;
}

static int secure_set(const char *key, const uint8_t *bytes, size_t blen, char *why, size_t wl) {
  SHCreateDirectoryExW(NULL, W.secure_dir, NULL);
  DATA_BLOB in = {(DWORD)blen, (BYTE *)bytes}, sealed = {0}, e = entropy();
  if (!CryptProtectData(&in, L"still.fail mbui core", &e, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &sealed)) {
    snprintf(why, wl, "secure.set: not sealed (%lu)", GetLastError());
    return 0;
  }
  WCHAR *path = secure_path(key);
  size_t n = wcslen(path);
  WCHAR *tmp = malloc((n + 5) * sizeof(WCHAR));
  swprintf(tmp, n + 5, L"%ls.new", path);
  HANDLE f = CreateFileW(tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  DWORD put = 0;
  BOOL ok = f != INVALID_HANDLE_VALUE && WriteFile(f, sealed.pbData, sealed.cbData, &put, NULL) && put == sealed.cbData;
  if (f != INVALID_HANDLE_VALUE) ok = FlushFileBuffers(f) && ok, CloseHandle(f);
  // whole or not at all
  ok = ok && MoveFileExW(tmp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
  if (!ok) snprintf(why, wl, "secure.set: not written (%lu)", GetLastError()), DeleteFileW(tmp);
  LocalFree(sealed.pbData);
  free(tmp);
  free(path);
  return ok;
}

static void secure_delete(const char *key) {
  WCHAR *path = secure_path(key);
  DeleteFileW(path);
  free(path);
}

static void core_secure(uint64_t id, const char *op, const char *json, const uint8_t *bytes, size_t blen) {
  char *key = jstr(jget(json, "key"));
  char why[200] = "";
  if (strcmp(op, "secure.ask") == 0 || jtrue(jget(json, "user"))) {
    answer(id, NULL, "unsupported", NULL, 0);
  } else if (!key || !*key) {
    snprintf(why, sizeof why, "%s: no key", op);
    answer(id, NULL, why, NULL, 0);
  } else if (strcmp(op, "secure.get") == 0) {
    uint8_t *out = NULL;
    size_t len = 0;
    int got = secure_get(key, &out, &len, why, sizeof why);
    if (got > 0) answer(id, "{}", NULL, out, len);
    else if (got == 0) answer(id, "{\"none\":true}", NULL, NULL, 0);
    else answer(id, NULL, why, NULL, 0);
    if (out) SecureZeroMemory(out, len), free(out);
  } else if (strcmp(op, "secure.set") == 0) {
    static const uint8_t none = 0;
    if (secure_set(key, bytes ? bytes : &none, bytes ? blen : 0, why, sizeof why)) answer(id, "{}", NULL, NULL, 0);
    else answer(id, NULL, why, NULL, 0);
  } else if (strcmp(op, "secure.delete") == 0) {
    secure_delete(key);
    answer(id, "{}", NULL, NULL, 0);
  } else {
    answer(id, NULL, "unsupported", NULL, 0);
  }
  free(key);
}

// MBUI_SECURE_TEST=1: set, get, delete, get once, through the same paths the core's calls take.
static void secure_test(void) {
  static const uint8_t seed[] = {1, 2, 3, 250, 0, 7};
  char why[200] = "";
  uint8_t *out = NULL;
  size_t len = 0;
  int set = secure_set("mbui-secure-test", seed, sizeof seed, why, sizeof why);
  int got = secure_get("mbui-secure-test", &out, &len, why, sizeof why);
  int same = got == 1 && len == sizeof seed && memcmp(out, seed, len) == 0;
  free(out);
  out = NULL;
  secure_delete("mbui-secure-test");
  int gone = secure_get("mbui-secure-test", &out, &len, why, sizeof why) == 0;
  free(out);
  fprintf(stderr, "SECURE_TEST %s (set %d, read back %d, deleted %d)%s%s\n", set && same && gone ? "ok" : "FAILED", set, same, gone,
          why[0] ? ": " : "", why);
}

// ── listen.* ──

typedef struct request {
  struct request *next;
  char *json;
  uint8_t *body;
  size_t blen;
} request;

typedef struct waiter {
  struct waiter *next;
  uint64_t id;
} waiter;

typedef struct listening {
  struct listening *next;
  int lid;
  int ended;
  request *requests, *requests_tail;  // come, not yet taken by a listen.next
  waiter *waiting, *waiting_tail;     // listen.next calls waiting for one
} listening;

static CRITICAL_SECTION listen_lock;
static listening *listens;

static listening *find_listen(int lid) {
  for (listening *l = listens; l; l = l->next)
    if (l->lid == lid && !l->ended) return l;
  return NULL;
}

// What a listener says, from its queue: a request (handed to a waiting listen.next, else kept), or its end.
static void listen_took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  listening *l = ctx;
  EnterCriticalSection(&listen_lock);
  if (!json) {
    l->ended = 1;
    waiter *w = l->waiting;
    l->waiting = l->waiting_tail = NULL;
    for (request *r = l->requests, *n; r; r = n) n = r->next, free(r->json), free(r->body), free(r);
    l->requests = l->requests_tail = NULL;
    for (listening **p = &listens; *p; p = &(*p)->next)
      if (*p == l) {
        *p = l->next;
        break;
      }
    LeaveCriticalSection(&listen_lock);
    for (waiter *n; w; w = n) n = w->next, answer(w->id, "{\"end\":true}", NULL, NULL, 0), free(w);
    free(l);
    return;
  }
  if (l->waiting) {
    waiter *w = l->waiting;
    l->waiting = w->next;
    if (!l->waiting) l->waiting_tail = NULL;
    LeaveCriticalSection(&listen_lock);
    char *j = malloc(len + 1);
    memcpy(j, json, len);
    j[len] = 0;
    static const uint8_t none = 0;
    answer(w->id, j, NULL, blen ? body : &none, blen);
    free(j);
    free(w);
    return;
  }
  request *r = calloc(1, sizeof *r);
  r->json = malloc(len + 1);
  memcpy(r->json, json, len);
  r->json[len] = 0;
  r->body = malloc(blen ? blen : 1);
  if (blen) memcpy(r->body, body, blen);
  r->blen = blen;
  if (l->requests_tail) l->requests_tail->next = r;
  else l->requests = r;
  l->requests_tail = r;
  LeaveCriticalSection(&listen_lock);
}

static void core_listen(uint64_t id, const char *op, const char *json, const uint8_t *bytes, size_t blen) {
  double which = 0;
  int has_id = jnum(jget(json, "id"), &which);
  char buf[160];
  if (strcmp(op, "listen.open") == 0) {
    double port = -1;
    char *host = jstr(jget(json, "host"));
    if (!jnum(jget(json, "port"), &port) || !host) {
      answer(id, NULL, "listen.open: port and host", NULL, 0);
      free(host);
      return;
    }
    listening *l = calloc(1, sizeof *l);
    char why[160] = "";
    int bound = 0;
    // in the list before it can say anything
    EnterCriticalSection(&listen_lock);
    l->lid = -1;
    l->next = listens;
    listens = l;
    LeaveCriticalSection(&listen_lock);
    int lid = mb_listen_open(host, (int)port, listen_took, l, &bound, why, sizeof why);
    free(host);
    EnterCriticalSection(&listen_lock);
    if (!lid) {
      for (listening **p = &listens; *p; p = &(*p)->next)
        if (*p == l) {
          *p = l->next;
          break;
        }
      LeaveCriticalSection(&listen_lock);
      free(l);
      answer(id, NULL, why, NULL, 0);
      return;
    }
    l->lid = lid;
    LeaveCriticalSection(&listen_lock);
    snprintf(buf, sizeof buf, "{\"id\":%d,\"port\":%d}", lid, bound);
    answer(id, buf, NULL, NULL, 0);
  } else if (strcmp(op, "listen.next") == 0) {
    EnterCriticalSection(&listen_lock);
    listening *l = has_id ? find_listen((int)which) : NULL;
    if (!l) {
      LeaveCriticalSection(&listen_lock);
      answer(id, "{\"end\":true}", NULL, NULL, 0);
      return;
    }
    if (l->requests) {
      request *r = l->requests;
      l->requests = r->next;
      if (!l->requests) l->requests_tail = NULL;
      LeaveCriticalSection(&listen_lock);
      answer(id, r->json, NULL, r->body, r->blen);
      free(r->json), free(r->body), free(r);
      return;
    }
    waiter *w = calloc(1, sizeof *w);
    w->id = id;
    if (l->waiting_tail) l->waiting_tail->next = w;
    else l->waiting = w;
    l->waiting_tail = w;
    LeaveCriticalSection(&listen_lock);
  } else if (strcmp(op, "listen.respond") == 0) {
    double req = 0, status = 502;
    jnum(jget(json, "status"), &status);
    const char *names[64];
    char *kept[64];
    int n = 0;
    const char *h = jget(json, "headers");
    if (h && *h == '[') {
      h = ws(h + 1);
      while (*h == '[' && n + 2 <= 64) {
        const char *k = ws(h + 1);
        const char *ke = skip(k);
        const char *v = ke ? ws(*ws(ke) == ',' ? ws(ke) + 1 : ke) : NULL;
        char *ks = jstr(k), *vs = jstr(v);
        if (ks && vs) kept[n] = ks, names[n] = ks, n++, kept[n] = vs, names[n] = vs, n++;
        else free(ks), free(vs);
        if (!(h = skip(h))) break;
        h = ws(h);
        if (*h == ',') h = ws(h + 1);
      }
    }
    if (has_id && jnum(jget(json, "request"), &req)) mb_listen_respond((int)which, (long)req, (int)status, names, n / 2, bytes, bytes ? blen : 0);
    for (int i = 0; i < n; i++) free(kept[i]);
    answer(id, "{}", NULL, NULL, 0);
  } else if (strcmp(op, "listen.close") == 0) {
    if (has_id) mb_listen_close((int)which);
    answer(id, "{}", NULL, NULL, 0);
  } else {
    answer(id, NULL, "unsupported", NULL, 0);
  }
}

// Every listener of this core closed (the core ends).
static void listen_close_all(void) {
  int lids[64], n = 0;
  EnterCriticalSection(&listen_lock);
  for (listening *l = listens; l && n < 64; l = l->next)
    if (l->lid > 0 && !l->ended) lids[n++] = l->lid;
  LeaveCriticalSection(&listen_lock);
  for (int i = 0; i < n; i++) mb_listen_close(lids[i]);
}

// ── the engine's host ──

static void on_say(void *ctx, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)ctx;
  if (tracing()) fprintf(stderr, "[core trace] says %.*s%s\n", (int)(len < 300 ? len : 300), json, len > 300 ? "..." : "");
  if (W.on_message) W.on_message(json, len, bytes, blen, W.ctx);
  mb_app_wake();
}

static void on_app_call(void *ctx, uint64_t id, const char *op, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)ctx;
  char *j = malloc(len + 1);
  memcpy(j, json, len);
  j[len] = 0;
  if (tracing()) fprintf(stderr, "[core trace] -> %llu %s %.*s (here)\n", (unsigned long long)id, op, (int)(len < 120 ? len : 120), j);
  if (strncmp(op, "secure.", 7) == 0) core_secure(id, op, j, bytes, blen);
  else core_listen(id, op, j, bytes, blen);
  free(j);
}

static void on_log(void *ctx, int level, const char *text, size_t len) {
  (void)ctx;
  static int debug = -1;
  if (debug < 0) debug = getenv("MB_CORE_DEBUG") != NULL;
  if (level < 1 && !debug) return;
  fprintf(stderr, "[core %s] %.*s\n", level >= 3 ? "error" : level == 2 ? "warn" : level == 1 ? "info" : "debug", (int)len, text);
}

// $MB_CORE_BUNDLE, else core.hbc beside the app.
static WCHAR *script_path(void) {
  const WCHAR *env = _wgetenv(L"MB_CORE_BUNDLE");
  if (env && *env) return _wcsdup(env);
  WCHAR exe[MAX_PATH * 2];
  DWORD n = GetModuleFileNameW(NULL, exe, MAX_PATH * 2);
  while (n > 0 && exe[n - 1] != L'\\' && exe[n - 1] != L'/') n--;
  wcscpy_s(exe + n, MAX_PATH * 2 - n, L"core.hbc");
  return _wcsdup(exe);
}

static uint8_t *read_all(const WCHAR *path, size_t *len) {
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
  if (f == INVALID_HANDLE_VALUE) return NULL;
  LARGE_INTEGER size;
  GetFileSizeEx(f, &size);
  uint8_t *b = malloc((size_t)size.QuadPart + 1);
  DWORD got = 0;
  BOOL ok = ReadFile(f, b, (DWORD)size.QuadPart, &got, NULL);
  CloseHandle(f);
  if (!ok) {
    free(b);
    return NULL;
  }
  *len = got;
  return b;
}

/// %LOCALAPPDATA%\fail.still.mbui\core, or $MBUI_CORE_DATA (engine->data_dir in core_client.h): kept once asked.
const char *mb_core_data_dir(void) {
  static char *dir;
  if (dir) return dir;
  const WCHAR *env = _wgetenv(L"MBUI_CORE_DATA");
  WCHAR *path = NULL;
  if (env && *env) {
    path = _wcsdup(env);
  } else {
    PWSTR local = NULL;
    if (SHGetKnownFolderPath(&FOLDERID_LocalAppData, 0, NULL, &local) != S_OK) return NULL;
    size_t n = wcslen(local) + 40;
    path = malloc(n * sizeof(WCHAR));
    swprintf(path, n, L"%ls\\fail.still.mbui\\core", local);
    CoTaskMemFree(local);
  }
  SHCreateDirectoryExW(NULL, path, NULL);
  dir = utf8(path);
  free(path);
  return dir;
}

void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  if (W.engine) return;
  static int once;
  if (!once) InitializeCriticalSection(&listen_lock), once = 1;
  W.on_message = on_message;
  W.ctx = ctx;
  WCHAR *dir = wide(data_dir);
  SHCreateDirectoryExW(NULL, dir, NULL);
  free(W.secure_dir);
  size_t n = wcslen(dir) + 10;
  W.secure_dir = malloc(n * sizeof(WCHAR));
  swprintf(W.secure_dir, n, L"%ls\\secure", dir);
  free(dir);
  if (getenv("MBUI_SECURE_TEST")) secure_test();
  WCHAR *path = script_path();
  size_t len = 0;
  uint8_t *script = read_all(path, &len);
  char *where = utf8(path);
  free(path);
  if (!script) {
    char why[400];
    snprintf(why, sizeof why, "no core script (core.hbc beside the app, or MB_CORE_BUNDLE): %s", where);
    for (char *c = why; *c; c++)
      if (*c == '\\' || *c == '"') *c = '/';
    free(where);
    say_fatal(why);
    return;
  }
  sf_engine_host host = {NULL, on_say, on_app_call, on_log};
  sf_engine *e = sf_engine_start(script, len, "core.hbc", data_dir, cloud_origin, beta, "windows", &host);
  free(script);
  if (!e) {
    free(where);
    say_fatal("the core's thread did not start");
    return;
  }
  AcquireSRWLockExclusive(&W.gate);
  W.engine = e;
  ReleaseSRWLockExclusive(&W.gate);
  fprintf(stderr, "[core] started in Hermes (%zu bytes of bytecode, %s), its files in %s, cloud %s%s\n", len, where, data_dir, cloud_origin,
          beta ? " (beta)" : "");
  free(where);
}

void mb_core_send(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  AcquireSRWLockShared(&W.gate);
  if (W.engine) sf_engine_receive(W.engine, json, len, bytes, blen);
  ReleaseSRWLockShared(&W.gate);
}

void mb_core_stop(void) {
  AcquireSRWLockExclusive(&W.gate);
  sf_engine *e = W.engine;
  W.engine = NULL;  // no answer reaches it after this
  ReleaseSRWLockExclusive(&W.gate);
  if (!e) return;
  listen_close_all();
  sf_engine_stop(e);  // joins the core's thread
  W.on_message = NULL;
  fprintf(stderr, "[core] stopped\n");
}
