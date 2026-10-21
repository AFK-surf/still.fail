// What comes from outside the frames as a message (a core's answer, from the core's own thread), kept by the framework
// for the window's next frame (docs/determinism.md, src/ui/messages.mbt). Included once by each host's own file
// (mac_app.m, ios_app.m, android_host.c, win_app.c), which defines `mb_post_wake`: a frame asked for, from any thread.
//
//   mb_post(channel, json, len, bytes, blen)   any thread: the message copied in; the first since the last take wakes
//                                              the host (one frame), the rest wait for it
//   mb_post_drop(channel)                      what is posted on `channel` and not handed on yet, gone (a core
//                                              stopped: its last words are not the next one's)
//   mb_host_post_take / _next / _json / _bytes the frame's: all that is posted taken as it begins (host_native.mbt
//                                              post_take), then handed on one at a time
//   mb_post_pending()                          whether something is posted that no frame has taken (a run to its
//                                              rest is not at it while one is)
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "post_api.h"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
static SRWLOCK post_lock = SRWLOCK_INIT;
#define POST_LOCK() AcquireSRWLockExclusive(&post_lock)
#define POST_UNLOCK() ReleaseSRWLockExclusive(&post_lock)
#else
#include <pthread.h>
static pthread_mutex_t post_lock = PTHREAD_MUTEX_INITIALIZER;
#define POST_LOCK() pthread_mutex_lock(&post_lock)
#define POST_UNLOCK() pthread_mutex_unlock(&post_lock)
#endif

typedef struct mb_posted {
  struct mb_posted *next;
  size_t clen, len, blen;  // the channel, then the JSON, then the bytes, in `data`
  char data[1];
} mb_posted;

// posted, not taken; taken by the frame, not handed on yet; the one handed on now (its JSON and bytes read after)
static mb_posted *post_head, *post_tail, *post_taken, *post_cur;

// The host's: a frame asked for, from whatever thread posted.
static void mb_post_wake(void);

void mb_post(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  size_t clen = channel ? strlen(channel) : 0;
  if (!clen) return;
  if (!bytes) blen = 0;
  mb_posted *m = (mb_posted *)malloc(sizeof(mb_posted) + clen + len + blen);
  if (!m) return;
  m->next = NULL;
  m->clen = clen;
  m->len = len;
  m->blen = blen;
  memcpy(m->data, channel, clen);
  if (len) memcpy(m->data + clen, json, len);
  if (blen) memcpy(m->data + clen + len, bytes, blen);
  POST_LOCK();
  int first = post_head == NULL;
  if (post_tail) post_tail->next = m;
  else post_head = m;
  post_tail = m;
  POST_UNLOCK();
  // the first since the frame took the last: one frame, which takes this one and all that come before it
  if (first) mb_post_wake();
}

static int post_on(const mb_posted *m, const char *channel, size_t clen) {
  return m->clen == clen && memcmp(m->data, channel, clen) == 0;
}

static mb_posted *post_drop_from(mb_posted *m, const char *channel, size_t clen, mb_posted **last) {
  mb_posted *keep = NULL, **at = &keep;
  *last = NULL;
  while (m) {
    mb_posted *next = m->next;
    if (post_on(m, channel, clen)) {
      free(m);
    } else {
      m->next = NULL;
      *at = m;
      at = &m->next;
      *last = m;
    }
    m = next;
  }
  return keep;
}

void mb_post_drop(const char *channel) {
  size_t clen = channel ? strlen(channel) : 0;
  mb_posted *last;
  POST_LOCK();
  post_head = post_drop_from(post_head, channel, clen, &last);
  post_tail = last;
  post_taken = post_drop_from(post_taken, channel, clen, &last);
  POST_UNLOCK();
}

static inline int mb_post_pending(void) {
  POST_LOCK();
  int n = post_head != NULL;
  POST_UNLOCK();
  return n;
}

int32_t mb_host_post_take(void) {
  POST_LOCK();
  // (what the last frame took and did not hand on stays first: none, as each frame hands on all it took)
  mb_posted **at = &post_taken;
  while (*at) at = &(*at)->next;
  *at = post_head;
  post_head = post_tail = NULL;
  int32_t n = 0;
  for (mb_posted *m = post_taken; m; m = m->next) n++;
  POST_UNLOCK();
  return n;
}

// UTF-8 as MoonBit's UTF-16 (what is not UTF-8: U+FFFD)
static moonbit_string_t post_string(const char *p, size_t len) {
  const uint8_t *b = (const uint8_t *)p;
  uint16_t *tmp = (uint16_t *)malloc((len ? len : 1) * sizeof(uint16_t));
  size_t n = 0;
  for (size_t i = 0; i < len;) {
    uint32_t c = b[i], cp = 0xfffd;
    size_t k = 1;
    if (c < 0x80) cp = c;
    else if (c >= 0xc2 && c < 0xe0 && i + 1 < len && (b[i + 1] & 0xc0) == 0x80) cp = ((c & 31) << 6) | (b[i + 1] & 63), k = 2;
    else if (c >= 0xe0 && c < 0xf0 && i + 2 < len && (b[i + 1] & 0xc0) == 0x80 && (b[i + 2] & 0xc0) == 0x80) {
      cp = ((c & 15) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63), k = 3;
      if (cp < 0x800 || (cp >= 0xd800 && cp < 0xe000)) cp = 0xfffd;
    } else if (c >= 0xf0 && c < 0xf5 && i + 3 < len && (b[i + 1] & 0xc0) == 0x80 && (b[i + 2] & 0xc0) == 0x80 &&
               (b[i + 3] & 0xc0) == 0x80) {
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

moonbit_string_t mb_host_post_next(void) {
  POST_LOCK();
  mb_posted *m = post_taken;
  if (m) post_taken = m->next;
  POST_UNLOCK();
  free(post_cur);
  post_cur = m;
  if (!m) return moonbit_make_string_raw(0);
  return post_string(m->data, m->clen);
}

moonbit_string_t mb_host_post_json(void) {
  if (!post_cur) return moonbit_make_string_raw(0);
  return post_string(post_cur->data + post_cur->clen, post_cur->len);
}

moonbit_bytes_t mb_host_post_bytes(void) {
  size_t n = post_cur ? post_cur->blen : 0;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, post_cur->data + post_cur->clen + post_cur->len, n);
  return b;
}
