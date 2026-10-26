// The still.fail client core on Linux (core_api.h), as Windows runs it (win_core.c, whose shape this keeps): Hermes in-process on
// the Rust shell, in the engine prebuilt for Linux (apps/mbui/engine as libstillfail_engine.so, beside
// libstillfail_shell.so: scripts/native.ts parts `engine` and `shell`, linux-x64 and linux-arm64), the core as Hermes
// bytecode (core.hbc beside the app, or $MB_CORE_BUNDLE: scripts/core.sh hermes). What the core says comes back through
// the engine's `say`, through core_native.c into mbui's queue (mb_post), which asks for the frame that takes it
// (linux_app.c); the calls only the app does are answered here, as win_core.c's:
//   secure.* (ember hosts/bridge.ts): what the core keeps out of the files it syncs (the lock's signing seed, a vault's
//     key), in the desktop's Secret Service (libsecret: GNOME Keyring, KWallet), each value a secret of its own under
//     the schema fail.still.mbui.core (its key, and whether it is a `user` one: read only as it was kept); where there is
//     no Secret Service (no session bus, no keyring running), files of <data>/secure readable by this user alone, as
//     the Electron app on Linux kept them where safeStorage had only its plain-text fallback. secure.get {key, user} ->
//     {} + the bytes, or {none: true}; secure.set {key, user} + the bytes -> {}; secure.delete {key} -> {};
//     secure.ask {reason} -> {}: nothing asks the person here, as on Windows (client/core-ts host.ts `secureAsk`).
//     Answered off the core's thread (a locked keyring asks the person to unlock it).
//   kept.read {at, start, end} -> {} + the bytes, or {none: true}: a file the app saved (its path, as mb_host_keep_where
//     said it) read back, bytes start to end (the core's downloads: drive-kept.ts `saved`).
//   listen.* (a login's loopback listener, mbui's linux_listen.c): listen.open {port, host} -> {id, port};
//     listen.next {id} -> {request, method, path, headers} + the body, or {end: true}; listen.respond {id, request,
//     status, headers} + the body -> {}; listen.close {id} -> {}.
// The app's files are under $XDG_DATA_HOME/fail.still.mbui/core ($MBUI_CORE_DATA instead). MB_CORE_TRACE=1 says what
// the core says (its first 300 bytes) and the app's calls on stderr; MB_CORE_DEBUG=1 the core's debug lines;
// MBUI_SECURE_TEST=1 round-trips secure.* once as the core starts (SECURE_TEST … on stderr).
#include <errno.h>
#include <fcntl.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <libsecret/secret.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "core_api.h"
// mbui's own (scripts/linux.sh's stub flags put its src/host in the include path): the forwarding listen_api.h beside
// this file names mbui where the module's checkout has it, which linux.sh's copy of the module does not
#include <listen_api.h>
#include "engine.h"

static struct {
  sf_engine *engine;  // under `gate`: answers from other threads look at it there
  pthread_rwlock_t gate;
  mb_core_message_fn on_message;
  void *ctx;
  char *secure_dir;
} W = {NULL, PTHREAD_RWLOCK_INITIALIZER};

static int tracing(void) {
  static int on = -1;
  if (on < 0) on = getenv("MB_CORE_TRACE") != NULL;
  return on;
}

static void say_fatal(const char *why) {
  char buf[600];
  int n = snprintf(buf, sizeof buf, "{\"fatal\":\"%s\"}", why);
  fprintf(stderr, "[core] %s\n", why);
  if (W.on_message) W.on_message(buf, (size_t)n, NULL, 0, W.ctx);
}

// ── answers, from any thread ──

static void answer(uint64_t id, const char *json, const char *error, const uint8_t *bytes, size_t blen) {
  if (tracing()) fprintf(stderr, "[core trace] <- %llu %s%s\n", (unsigned long long)id, error ? "error " : "", error ? error : json);
  pthread_rwlock_rdlock(&W.gate);
  if (W.engine) sf_engine_complete(W.engine, id, json, json ? strlen(json) : 0, error, error ? strlen(error) : 0, bytes, blen);
  pthread_rwlock_unlock(&W.gate);
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

static const SecretSchema *schema(void) {
  static const SecretSchema s = {"fail.still.mbui.core",
                                 SECRET_SCHEMA_NONE,
                                 {{"key", SECRET_SCHEMA_ATTRIBUTE_STRING}, {"user", SECRET_SCHEMA_ATTRIBUTE_BOOLEAN}, {NULL, 0}}};
  return &s;
}

// Whether the Secret Service answers (once: a session without one keeps files)
static int keyring(void) {
  static int there = -1;
  if (there >= 0) return there;
  GError *e = NULL;
  SecretService *s = secret_service_get_sync(SECRET_SERVICE_NONE, NULL, &e);
  there = s != NULL;
  if (!there) fprintf(stderr, "[core] no Secret Service (%s): secure values kept in %s\n", e ? e->message : "?", W.secure_dir);
  if (e) g_error_free(e);
  if (s) g_object_unref(s);
  return there;
}

// <data>/secure/<the key's UTF-8 in hex>, `.user` after a `user` one's
static char *secure_path(const char *key, int user) {
  GString *p = g_string_new(W.secure_dir);
  g_string_append_c(p, '/');
  for (const unsigned char *c = (const unsigned char *)key; *c; c++) g_string_append_printf(p, "%02x", *c);
  if (user) g_string_append(p, ".user");
  return g_string_free(p, FALSE);
}

// 1 and the bytes, 0 none, -1 failed (why in `why`).
static int secure_get(const char *key, int user, uint8_t **out, size_t *len, char *why, size_t wl) {
  if (keyring()) {
    GError *e = NULL;
    SecretValue *v = secret_password_lookup_binary_sync(schema(), NULL, &e, "key", key, "user", user ? TRUE : FALSE, NULL);
    if (e) {
      snprintf(why, wl, "secure.get: %s", e->message);
      g_error_free(e);
      return -1;
    }
    if (!v) return 0;
    gsize n = 0;
    const gchar *p = secret_value_get(v, &n);
    *out = malloc(n ? n : 1);
    memcpy(*out, p, n);
    *len = n;
    secret_value_unref(v);
    return 1;
  }
  char *path = secure_path(key, user);
  gchar *d = NULL;
  gsize n = 0;
  GError *e = NULL;
  int ok = g_file_get_contents(path, &d, &n, &e);
  g_free(path);
  if (!ok) {
    int none = e && e->domain == G_FILE_ERROR && e->code == G_FILE_ERROR_NOENT;
    if (!none) snprintf(why, wl, "secure.get: not read (%s)", e ? e->message : "?");
    if (e) g_error_free(e);
    return none ? 0 : -1;
  }
  *out = malloc(n ? n : 1);
  memcpy(*out, d, n);
  *len = n;
  memset(d, 0, n);
  g_free(d);
  return 1;
}

static int secure_set(const char *key, int user, const uint8_t *bytes, size_t blen, char *why, size_t wl) {
  if (keyring()) {
    GError *e = NULL;
    SecretValue *v = secret_value_new((const gchar *)bytes, (gssize)blen, "application/octet-stream");
    char *label = g_strdup_printf("still.fail: %s", key);
    int ok = secret_password_store_binary_sync(schema(), SECRET_COLLECTION_DEFAULT, label, v, NULL, &e, "key", key,
                                               "user", user ? TRUE : FALSE, NULL);
    g_free(label);
    secret_value_unref(v);
    if (!ok) snprintf(why, wl, "secure.set: %s", e ? e->message : "not stored");
    if (e) g_error_free(e);
    return ok;
  }
  g_mkdir_with_parents(W.secure_dir, 0700);
  char *path = secure_path(key, user), *tmp = g_strdup_printf("%s.new", path);
  // whole or not at all, readable by this user alone
  int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  int ok = fd >= 0;
  for (size_t put = 0; ok && put < blen;) {
    ssize_t w = write(fd, bytes + put, blen - put);
    if (w <= 0) ok = 0;
    else put += (size_t)w;
  }
  if (fd >= 0) ok = fsync(fd) == 0 && ok, close(fd);
  ok = ok && rename(tmp, path) == 0;
  if (!ok) snprintf(why, wl, "secure.set: not written (%s)", strerror(errno)), remove(tmp);
  g_free(tmp);
  g_free(path);
  return ok;
}

// Both values under `key`, whichever there is.
static void secure_delete(const char *key) {
  for (int user = 0; user < 2; user++) {
    if (keyring()) {
      secret_password_clear_sync(schema(), NULL, NULL, "key", key, "user", user ? TRUE : FALSE, NULL);
    } else {
      char *path = secure_path(key, user);
      remove(path);
      g_free(path);
    }
  }
}

typedef struct {
  uint64_t id;
  char *op, *json;
  uint8_t *bytes;
  size_t blen;
  int has_bytes;
} secure_call;

static gpointer secure_run(gpointer arg) {
  secure_call *c = arg;
  const char *op = c->op, *json = c->json;
  uint64_t id = c->id;
  char *key = jstr(jget(json, "key"));
  int user = jtrue(jget(json, "user"));
  char why[300] = "";
  if (strcmp(op, "secure.ask") == 0) {
    answer(id, "{}", NULL, NULL, 0);
  } else if (!key || !*key) {
    snprintf(why, sizeof why, "%s: no key", op);
    answer(id, NULL, why, NULL, 0);
  } else if (strcmp(op, "secure.get") == 0) {
    uint8_t *out = NULL;
    size_t len = 0;
    int got = secure_get(key, user, &out, &len, why, sizeof why);
    static const uint8_t none = 0;
    if (got > 0) answer(id, "{}", NULL, len ? out : &none, len);
    else if (got == 0) answer(id, "{\"none\":true}", NULL, NULL, 0);
    else answer(id, NULL, why, NULL, 0);
    if (out) memset(out, 0, len), free(out);
  } else if (strcmp(op, "secure.set") == 0) {
    static const uint8_t none = 0;
    if (secure_set(key, user, c->has_bytes ? c->bytes : &none, c->has_bytes ? c->blen : 0, why, sizeof why))
      answer(id, "{}", NULL, NULL, 0);
    else answer(id, NULL, why, NULL, 0);
  } else if (strcmp(op, "secure.delete") == 0) {
    secure_delete(key);
    answer(id, "{}", NULL, NULL, 0);
  } else {
    answer(id, NULL, "unsupported", NULL, 0);
  }
  free(key);
  if (c->bytes) memset(c->bytes, 0, c->blen);
  free(c->bytes);
  free(c->op);
  free(c->json);
  free(c);
  return NULL;
}

// Off the core's thread, in a thread of its own (answered from there).
static void core_secure(uint64_t id, const char *op, const char *json, const uint8_t *bytes, size_t blen) {
  secure_call *c = calloc(1, sizeof *c);
  c->id = id;
  c->op = strdup(op);
  c->json = strdup(json);
  c->has_bytes = bytes != NULL;
  c->blen = blen;
  c->bytes = malloc(blen ? blen : 1);
  if (blen) memcpy(c->bytes, bytes, blen);
  g_thread_unref(g_thread_new("core-secure", secure_run, c));
}

// MBUI_SECURE_TEST=1: set, get, delete, get once, through the same paths the core's calls take.
static void secure_test(void) {
  static const uint8_t seed[] = {1, 2, 3, 250, 0, 7};
  char why[200] = "";
  uint8_t *out = NULL;
  size_t len = 0;
  int set = secure_set("mbui-secure-test", 0, seed, sizeof seed, why, sizeof why);
  int got = secure_get("mbui-secure-test", 0, &out, &len, why, sizeof why);
  int same = got == 1 && len == sizeof seed && memcmp(out, seed, len) == 0;
  free(out);
  out = NULL;
  // read only as it was kept: asked as the person's, it is none
  int apart = secure_get("mbui-secure-test", 1, &out, &len, why, sizeof why) == 0;
  free(out);
  out = NULL;
  secure_delete("mbui-secure-test");
  int gone = secure_get("mbui-secure-test", 0, &out, &len, why, sizeof why) == 0;
  free(out);
  fprintf(stderr, "SECURE_TEST %s (set %d, read back %d, apart %d, deleted %d, in %s)%s%s\n",
          set && same && apart && gone ? "ok" : "FAILED", set, same, apart, gone, keyring() ? "the Secret Service" : "files",
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

static pthread_mutex_t listen_lock = PTHREAD_MUTEX_INITIALIZER;
static listening *listens;

static listening *find_listen(int lid) {
  for (listening *l = listens; l; l = l->next)
    if (l->lid == lid && !l->ended) return l;
  return NULL;
}

// What a listener says, from its queue: a request (handed to a waiting listen.next, else kept), or its end.
static void listen_took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  listening *l = ctx;
  pthread_mutex_lock(&listen_lock);
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
    pthread_mutex_unlock(&listen_lock);
    for (waiter *n; w; w = n) n = w->next, answer(w->id, "{\"end\":true}", NULL, NULL, 0), free(w);
    free(l);
    return;
  }
  if (l->waiting) {
    waiter *w = l->waiting;
    l->waiting = w->next;
    if (!l->waiting) l->waiting_tail = NULL;
    pthread_mutex_unlock(&listen_lock);
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
  pthread_mutex_unlock(&listen_lock);
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
    pthread_mutex_lock(&listen_lock);
    l->lid = -1;
    l->next = listens;
    listens = l;
    pthread_mutex_unlock(&listen_lock);
    int lid = mb_listen_open(host, (int)port, listen_took, l, &bound, why, sizeof why);
    free(host);
    pthread_mutex_lock(&listen_lock);
    if (!lid) {
      for (listening **p = &listens; *p; p = &(*p)->next)
        if (*p == l) {
          *p = l->next;
          break;
        }
      pthread_mutex_unlock(&listen_lock);
      free(l);
      answer(id, NULL, why, NULL, 0);
      return;
    }
    l->lid = lid;
    pthread_mutex_unlock(&listen_lock);
    snprintf(buf, sizeof buf, "{\"id\":%d,\"port\":%d}", lid, bound);
    answer(id, buf, NULL, NULL, 0);
  } else if (strcmp(op, "listen.next") == 0) {
    pthread_mutex_lock(&listen_lock);
    listening *l = has_id ? find_listen((int)which) : NULL;
    if (!l) {
      pthread_mutex_unlock(&listen_lock);
      answer(id, "{\"end\":true}", NULL, NULL, 0);
      return;
    }
    if (l->requests) {
      request *r = l->requests;
      l->requests = r->next;
      if (!l->requests) l->requests_tail = NULL;
      pthread_mutex_unlock(&listen_lock);
      answer(id, r->json, NULL, r->body, r->blen);
      free(r->json), free(r->body), free(r);
      return;
    }
    waiter *w = calloc(1, sizeof *w);
    w->id = id;
    if (l->waiting_tail) l->waiting_tail->next = w;
    else l->waiting = w;
    l->waiting_tail = w;
    pthread_mutex_unlock(&listen_lock);
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
  pthread_mutex_lock(&listen_lock);
  for (listening *l = listens; l && n < 64; l = l->next)
    if (l->lid > 0 && !l->ended) lids[n++] = l->lid;
  pthread_mutex_unlock(&listen_lock);
  for (int i = 0; i < n; i++) mb_listen_close(lids[i]);
}

// ── the engine's host ──

static void on_say(void *ctx, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)ctx;
  if (tracing()) fprintf(stderr, "[core trace] says %.*s%s\n", (int)(len < 300 ? len : 300), json, len > 300 ? "..." : "");
  if (W.on_message) W.on_message(json, len, bytes, blen, W.ctx);
}

// ── kept.read ──

static void core_kept(uint64_t id, const char *op, const char *json) {
  if (strcmp(op, "kept.read") != 0) {
    answer(id, NULL, "unsupported", NULL, 0);
    return;
  }
  char *at = jstr(jget(json, "at"));
  double start = 0, end = 0;
  if (!at || !jnum(jget(json, "start"), &start) || !jnum(jget(json, "end"), &end) || end < start || end - start > 64.0 * 1024 * 1024) {
    free(at);
    answer(id, NULL, "kept.read: at, start and end", NULL, 0);
    return;
  }
  int fd = open(at, O_RDONLY | O_CLOEXEC);
  free(at);
  if (fd < 0) {
    answer(id, "{\"none\":true}", NULL, NULL, 0);
    return;
  }
  size_t want = (size_t)(end - start), got = 0;
  uint8_t *buf = malloc(want ? want : 1);
  int ok = lseek(fd, (off_t)start, SEEK_SET) == (off_t)start;
  while (ok && got < want) {
    ssize_t n = read(fd, buf + got, want - got);
    if (n <= 0) break;
    got += (size_t)n;
  }
  close(fd);
  if (!ok) answer(id, "{\"none\":true}", NULL, NULL, 0);
  else answer(id, "{}", NULL, buf, got);
  free(buf);
}

static void on_app_call(void *ctx, uint64_t id, const char *op, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)ctx;
  char *j = malloc(len + 1);
  memcpy(j, json, len);
  j[len] = 0;
  if (tracing()) fprintf(stderr, "[core trace] -> %llu %s %.*s (here)\n", (unsigned long long)id, op, (int)(len < 120 ? len : 120), j);
  if (strncmp(op, "secure.", 7) == 0) core_secure(id, op, j, bytes, blen);
  else if (strncmp(op, "kept.", 5) == 0) core_kept(id, op, j);
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
static char *script_path(void) {
  const char *env = getenv("MB_CORE_BUNDLE");
  if (env && *env) return strdup(env);
  char exe[4096];
  ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
  if (n < 0) n = 0;
  exe[n] = 0;
  char *dir = g_path_get_dirname(exe), *p = g_build_filename(dir, "core.hbc", NULL), *out = strdup(p);
  g_free(p);
  g_free(dir);
  return out;
}

static uint8_t *read_all(const char *path, size_t *len) {
  gchar *d = NULL;
  gsize n = 0;
  if (!g_file_get_contents(path, &d, &n, NULL)) return NULL;
  uint8_t *b = malloc(n ? n : 1);
  memcpy(b, d, n);
  g_free(d);
  *len = n;
  return b;
}

/// $XDG_DATA_HOME/fail.still.mbui/core, or $MBUI_CORE_DATA (engine->data_dir in core_client.h): kept once asked.
const char *mb_core_data_dir(void) {
  static char *dir;
  if (dir) return dir;
  const char *env = getenv("MBUI_CORE_DATA");
  char *path = env && *env ? g_strdup(env) : g_build_filename(g_get_user_data_dir(), "fail.still.mbui", "core", NULL);
  g_mkdir_with_parents(path, 0700);
  dir = strdup(path);
  g_free(path);
  return dir;
}

void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  if (W.engine) return;
  W.on_message = on_message;
  W.ctx = ctx;
  g_mkdir_with_parents(data_dir, 0700);
  free(W.secure_dir);
  W.secure_dir = g_strdup_printf("%s/secure", data_dir);
  if (getenv("MBUI_SECURE_TEST")) secure_test();
  char *where = script_path();
  size_t len = 0;
  uint8_t *script = read_all(where, &len);
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
  sf_engine *e = sf_engine_start(script, len, "core.hbc", data_dir, cloud_origin, beta, "linux", &host);
  free(script);
  if (!e) {
    free(where);
    say_fatal("the core's thread did not start");
    return;
  }
  pthread_rwlock_wrlock(&W.gate);
  W.engine = e;
  pthread_rwlock_unlock(&W.gate);
  fprintf(stderr, "[core] started in Hermes (%zu bytes of bytecode, %s), its files in %s, cloud %s%s\n", len, where, data_dir, cloud_origin,
          beta ? " (beta)" : "");
  free(where);
}

void mb_core_send(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  pthread_rwlock_rdlock(&W.gate);
  if (W.engine) sf_engine_receive(W.engine, json, len, bytes, blen);
  pthread_rwlock_unlock(&W.gate);
}

void mb_core_stop(void) {
  pthread_rwlock_wrlock(&W.gate);
  sf_engine *e = W.engine;
  W.engine = NULL;  // no answer reaches it after this
  pthread_rwlock_unlock(&W.gate);
  if (!e) return;
  listen_close_all();
  sf_engine_stop(e);  // joins the core's thread
  W.on_message = NULL;
  fprintf(stderr, "[core] stopped\n");
}
