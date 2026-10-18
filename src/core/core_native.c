// mbui/core's native side: the engine's messages, which come on the core's own thread, copied into a queue that the
// UI thread drains (core.mbt `pump`). On Apple's systems the main queue is woken to drain it, once per run of messages
// (`scheduled`); elsewhere the engine asks the host for a frame and the host calls mbc_frame as each begins (Android's
// GL thread: android_host.c), which drains it when something came. The engine itself is the app's (core_client.h, mbc_use).
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "moonbit.h"
#include "core_client.h"
#ifdef __APPLE__
#include <dispatch/dispatch.h>
#endif

typedef struct msg {
  struct msg *next;
  size_t len;
  size_t blen; // the bytes beside it, after the JSON
  char json[];
} msg;

// The bytes beside the message mbc_next took last, for mbc_next_bytes.
static msg *taken;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static msg *head, *tail;
static atomic_int scheduled;
static void (*wake)(void);
static const mbc_engine *engine;

void mbc_use(const mbc_engine *e) { engine = e; }

void mbc_set_wake(void (*f)(void)) { wake = f; }

#ifdef __APPLE__
static void on_main(void *ctx) {
  // Cleared first: a message queued while the UI drains wakes it again.
  atomic_store(&scheduled, 0);
  if (wake) wake();
}
#endif

static void push_with(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  msg *m = malloc(sizeof(msg) + len + blen);
  m->next = NULL;
  m->len = len;
  m->blen = bytes ? blen : 0;
  memcpy(m->json, json, len);
  if (m->blen) memcpy(m->json + len, bytes, blen);
  pthread_mutex_lock(&lock);
  if (tail) tail->next = m;
  else head = m;
  tail = m;
  pthread_mutex_unlock(&lock);
#ifdef __APPLE__
  if (!atomic_exchange(&scheduled, 1)) dispatch_async_f(dispatch_get_main_queue(), NULL, on_main);
#else
  atomic_store(&scheduled, 1);
#endif
}

#ifndef __APPLE__
// As a frame begins, on the UI thread: what the core said since the last one (core.mbt `pump`, through `wake`).
void mbc_frame(void) {
  if (wake && atomic_exchange(&scheduled, 0)) wake();
}
#endif

static void push(const char *json, size_t len) { push_with(json, len, NULL, 0); }

// With the bytes beside a message (a picture, a file read), which the UI takes after its JSON (mbc_next_bytes).
static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  push_with(json, len, bytes, blen);
}

static void drop_all(void) {
  pthread_mutex_lock(&lock);
  msg *m = head;
  head = tail = NULL;
  pthread_mutex_unlock(&lock);
  while (m) {
    msg *next = m->next;
    free(m);
    m = next;
  }
}

// ── strings: MoonBit's are UTF-16, the core's UTF-8 ──

static char *utf8_of(moonbit_string_t s, size_t *out_len) {
  int32_t n = Moonbit_array_length(s);
  char *out = malloc((size_t)n * 3 + 1);
  size_t o = 0;
  for (int32_t i = 0; i < n; i++) {
    uint32_t c = s[i];
    if (c >= 0xd800 && c < 0xdc00 && i + 1 < n && s[i + 1] >= 0xdc00 && s[i + 1] < 0xe000) {
      c = 0x10000 + ((c - 0xd800) << 10) + (s[++i] - 0xdc00);
    } else if (c >= 0xd800 && c < 0xe000) {
      c = 0xfffd;
    }
    if (c < 0x80) out[o++] = (char)c;
    else if (c < 0x800) out[o++] = (char)(0xc0 | (c >> 6)), out[o++] = (char)(0x80 | (c & 63));
    else if (c < 0x10000) out[o++] = (char)(0xe0 | (c >> 12)), out[o++] = (char)(0x80 | ((c >> 6) & 63)), out[o++] = (char)(0x80 | (c & 63));
    else out[o++] = (char)(0xf0 | (c >> 18)), out[o++] = (char)(0x80 | ((c >> 12) & 63)), out[o++] = (char)(0x80 | ((c >> 6) & 63)), out[o++] = (char)(0x80 | (c & 63));
  }
  out[o] = 0;
  if (out_len) *out_len = o;
  return out;
}

static moonbit_string_t string_of(const char *p, size_t len) {
  const uint8_t *b = (const uint8_t *)p;
  uint16_t *tmp = malloc((len ? len : 1) * sizeof(uint16_t));
  size_t n = 0;
  for (size_t i = 0; i < len;) {
    uint32_t c = b[i], cp = 0xfffd;
    size_t k = 1;
    if (c < 0x80) cp = c;
    else if (c >= 0xc2 && c < 0xe0 && i + 1 < len && (b[i + 1] & 0xc0) == 0x80) cp = ((c & 31) << 6) | (b[i + 1] & 63), k = 2;
    else if (c >= 0xe0 && c < 0xf0 && i + 2 < len && (b[i + 1] & 0xc0) == 0x80 && (b[i + 2] & 0xc0) == 0x80) {
      cp = ((c & 15) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63), k = 3;
      if (cp < 0x800 || (cp >= 0xd800 && cp < 0xe000)) cp = 0xfffd;
    } else if (c >= 0xf0 && c < 0xf5 && i + 3 < len && (b[i + 1] & 0xc0) == 0x80 && (b[i + 2] & 0xc0) == 0x80 && (b[i + 3] & 0xc0) == 0x80) {
      cp = ((c & 7) << 18) | ((b[i + 1] & 63) << 12) | ((b[i + 2] & 63) << 6) | (b[i + 3] & 63), k = 4;
      if (cp < 0x10000 || cp > 0x10ffff) cp = 0xfffd;
    }
    if (cp >= 0x10000) {
      cp -= 0x10000;
      tmp[n++] = (uint16_t)(0xd800 + (cp >> 10));
      tmp[n++] = (uint16_t)(0xdc00 + (cp & 0x3ff));
    } else {
      tmp[n++] = (uint16_t)cp;
    }
    i += k;
  }
  moonbit_string_t out = moonbit_make_string_raw((int32_t)n);
  memcpy(out, tmp, n * sizeof(uint16_t));
  free(tmp);
  return out;
}

// ── what core.mbt calls ──

static void say_fatal(const char *reason) {
  char buf[256];
  int n = snprintf(buf, sizeof buf, "{\"fatal\":\"%s\"}", reason);
  push(buf, (size_t)n);
}

int32_t mbc_start(moonbit_string_t data_dir, moonbit_string_t cloud, int32_t beta) {
  if (!engine) return 0;
  char *dir = utf8_of(data_dir, NULL);
  char *origin = utf8_of(cloud, NULL);
  const char *where = *dir ? dir : engine->data_dir ? engine->data_dir() : NULL;
  if (where) engine->start(where, origin, beta, on_message, NULL);
  else say_fatal("no place for the core's files");
  free(dir);
  free(origin);
  return 1;
}

void mbc_send(moonbit_string_t json) {
  if (!engine) return;
  size_t len;
  char *s = utf8_of(json, &len);
  engine->send(s, len, NULL, 0);
  free(s);
}

void mbc_stop(void) {
  if (!engine) return;
  engine->stop();
  // What the stopped core said and the UI has not taken is its last words: the next core's ids are the same.
  drop_all();
}

moonbit_string_t mbc_next(void) {
  pthread_mutex_lock(&lock);
  msg *m = head;
  if (m) {
    head = m->next;
    if (!head) tail = NULL;
  }
  pthread_mutex_unlock(&lock);
  free(taken);
  taken = m;
  if (!m) return moonbit_make_string_raw(0);
  return string_of(m->json, m->len);
}

moonbit_bytes_t mbc_next_bytes(void) {
  size_t n = taken ? taken->blen : 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, taken->json + taken->len, n);
  return b;
}

// A browser session's end, queued as a message of ours: {"mbui_auth": token, "url"|"error": "..."}.
static void auth_done(const char *url, const char *error, void *ctx) {
  const char *text = url ? url : error ? error : "the browser session ended";
  size_t n = strlen(text);
  char *buf = malloc(n * 6 + 64);
  size_t o = (size_t)sprintf(buf, "{\"mbui_auth\":%ld,\"%s\":\"", (long)(intptr_t)ctx, url ? "url" : "error");
  for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
    if (*p == '"' || *p == '\\') buf[o++] = '\\', buf[o++] = (char)*p;
    else if (*p < 0x20) o += (size_t)sprintf(buf + o, "\\u%04x", *p);
    else buf[o++] = (char)*p;
  }
  buf[o++] = '"';
  buf[o++] = '}';
  push(buf, o);
  free(buf);
}

int32_t mbc_has_web_auth(void) { return engine && engine->web_auth ? 1 : 0; }

int32_t mbc_web_auth(int32_t token, moonbit_string_t url, moonbit_string_t scheme) {
  if (!engine || !engine->web_auth) return 0;
  char *u = utf8_of(url, NULL);
  char *s = utf8_of(scheme, NULL);
  engine->web_auth(u, s, auth_done, (void *)(intptr_t)token);
  free(u);
  free(s);
  return 1;
}

double mbc_wall_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_REALTIME, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

double mbc_now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}
