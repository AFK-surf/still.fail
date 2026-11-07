// Shared Linux/Windows loopback sign-in state and request handling.
// Platform files supply UTF-8 conversion, browser launching and the platform lock declarations.
#ifndef MBUI_BROWSER_LOGIN_H
#define MBUI_BROWSER_LOGIN_H
static char *utf8(moonbit_string_t s);

typedef struct login {
  struct login *next;
  int id, lid, port;
  char *path;
  char *done;  // where the browser is sent on to once it has come back ("": this host's page)
  char *back;  // where the browser came back to, once it has (under `lock`)
} login;

#ifdef _WIN32
static SRWLOCK lock = SRWLOCK_INIT;
#define LOGIN_READ() AcquireSRWLockShared(&lock)
#define LOGIN_READ_END() ReleaseSRWLockShared(&lock)
#define LOGIN_WRITE() AcquireSRWLockExclusive(&lock)
#define LOGIN_WRITE_END() ReleaseSRWLockExclusive(&lock)
#define LOGIN_DUP _strdup
#define LOGIN_CASECMP _strnicmp
#else
static pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;
#define LOGIN_READ() pthread_rwlock_rdlock(&lock)
#define LOGIN_READ_END() pthread_rwlock_unlock(&lock)
#define LOGIN_WRITE() pthread_rwlock_wrlock(&lock)
#define LOGIN_WRITE_END() pthread_rwlock_unlock(&lock)
#define LOGIN_DUP strdup
#define LOGIN_CASECMP strncasecmp
#endif
static login *logins;
static int login_next;

static login *find(int id) {
  for (login *l = logins; l; l = l->next)
    if (l->id == id) return l;
  return NULL;
}

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
  LOGIN_READ();
  login *l = find(id);
  int lid = l ? l->lid : 0, port = l ? l->port : 0;
  char *want = l ? LOGIN_DUP(l->path) : NULL;
  char *done = l ? LOGIN_DUP(l->done) : NULL;
  LOGIN_READ_END();
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
    if (LOGIN_CASECMP(h + 2, "host\",\"", 7) != 0) continue;
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
    LOGIN_WRITE();
    l = find(id);
    if (l && !l->back) l->back = back, back = NULL;
    LOGIN_WRITE_END();
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
  LOGIN_WRITE();
  l->id = ++login_next;
  l->next = logins;
  logins = l;
  LOGIN_WRITE_END();
  char why[160];
  int port = 0;
  int lid = mb_listen_open("127.0.0.1", 0, took, (void *)(intptr_t)l->id, &port, why, sizeof why);
  LOGIN_WRITE();
  if (!lid) {
    for (login **p = &logins; *p; p = &(*p)->next)
      if (*p == l) {
        *p = l->next;
        break;
      }
    LOGIN_WRITE_END();
    fprintf(stderr, "browser login: %s\n", why);
    free(l->path);
    free(l->done);
    free(l);
    return 0;
  }
  // Set before any request can come: one comes only once the browser has the page, which the port is needed for.
  l->lid = lid;
  l->port = port;
  LOGIN_WRITE_END();
  return l->id;
}

int32_t mb_host_browser_login_port(int32_t id) {
  LOGIN_READ();
  login *l = find(id);
  int port = l ? l->port : 0;
  LOGIN_READ_END();
  return port;
}

void mb_host_browser_login_end(int32_t id) {
  LOGIN_WRITE();
  login *l = find(id);
  if (l)
    for (login **p = &logins; *p; p = &(*p)->next)
      if (*p == l) {
        *p = l->next;
        break;
      }
  LOGIN_WRITE_END();
  if (!l) return;
  mb_listen_close(l->lid);
  free(l->path);
  free(l->done);
  free(l->back);
  free(l);
}

#undef LOGIN_READ
#undef LOGIN_READ_END
#undef LOGIN_WRITE
#undef LOGIN_WRITE_END
#undef LOGIN_DUP
#undef LOGIN_CASECMP
#endif
