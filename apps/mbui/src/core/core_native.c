// mbui/core's native side: the engine's messages, which come on the core's own thread, posted to mbui's queue
// (mb_post, mbui's src/host/post.h, handed over with the engine: core_client.h) on the channel "core": the window's
// next frame takes them as it begins and hands them
// to the app's handler (@ui.on_message_read("core", @core.receive_read)); the first since a frame took the last wakes
// the host.
// The engine itself is the app's (core_client.h, mbc_use).
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "moonbit.h"
#include "core_client.h"

static const mbc_engine *engine;

void mbc_use(const mbc_engine *e) { engine = e; }

static void push_with(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  // (mbui's queue, as the engine gives it: mb_post, a message for the next frame from any thread)
  if (engine && engine->post) engine->post("core", json, len, bytes, blen);
}

static void push(const char *json, size_t len) { push_with(json, len, NULL, 0); }

// With the bytes beside a message (a picture, a file read), which the UI takes with its JSON.
static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  push_with(json, len, bytes, blen);
}

// ── strings: MoonBit's are UTF-16, the core's UTF-8 (what comes back is mbui's to make: post.h) ──

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

// With bytes beside it (a file's part going up): `bytes` is a MoonBit Bytes, its length in its header.
void mbc_send_bytes(moonbit_string_t json, moonbit_bytes_t bytes) {
  if (!engine) return;
  size_t len;
  char *s = utf8_of(json, &len);
  engine->send(s, len, (const uint8_t *)bytes, (size_t)Moonbit_array_length(bytes));
  free(s);
}

void mbc_stop(void) {
  if (!engine) return;
  engine->stop();
  // What the stopped core said and the UI has not taken is its last words: the next core's ids are the same.
  if (engine->post_drop) engine->post_drop("core");
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

#ifdef _WIN32
double mbc_wall_ms(void) {
  FILETIME ft;
  GetSystemTimePreciseAsFileTime(&ft);
  uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;  // 100 ns since 1601
  return (double)(t - 116444736000000000ULL) / 10000.0;
}

double mbc_now_ms(void) {
  static LARGE_INTEGER freq;
  LARGE_INTEGER t;
  if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t);
  return (double)t.QuadPart * 1000.0 / (double)freq.QuadPart;
}
#else
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
#endif
