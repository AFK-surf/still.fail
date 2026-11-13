// A loopback HTTP listener for the Linux host (listen_api.h), as win_listen.c is for Windows' (whose shape this keeps):
// POSIX sockets, a thread accepting per listener, each request read whole on a thread of its own (blocking, 15 s at
// most) and handed on from one serial queue (a thread of its own), which keeps every listener's state and writes the
// answers, so a listener's `fn` is never called twice at once and a close asked after an answer ends the listener only
// once that answer is out.
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include "listen_api.h"

/// Most of a request's head and body taken (a login's callback: a query, or a small form).
enum { LISTEN_HEAD_MOST = 64 * 1024, LISTEN_BODY_MOST = 1000000, LISTEN_READ_MS = 15000 };

typedef struct asked {
  struct asked *next;
  long request;
  int c;
} asked;

typedef struct listener {
  struct listener *next;
  int id;
  int fd;
  mb_listen_fn fn;
  void *ctx;
  long requests;
  volatile int closed;
  asked *asked;  // the connections whose request was handed on, until answered (the queue's)
} listener;

// ── the queue: one thread running what is posted, in order ──

typedef struct task {
  struct task *next;
  void (*run)(void *);
  void *arg;
} task;

static pthread_once_t once = PTHREAD_ONCE_INIT;
static pthread_mutex_t q_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t q_wake = PTHREAD_COND_INITIALIZER;
static task *q_head, *q_tail;
// The listeners (the queue's, but for mb_listen_open's adding, under q_lock).
static listener *listeners;
static int listen_next_id;

static void *queue_main(void *unused) {
  (void)unused;
  for (;;) {
    pthread_mutex_lock(&q_lock);
    while (!q_head) pthread_cond_wait(&q_wake, &q_lock);
    task *t = q_head;
    q_head = t->next;
    if (!q_head) q_tail = NULL;
    pthread_mutex_unlock(&q_lock);
    t->run(t->arg);
    free(t);
  }
  return NULL;
}

// a thread of its own, let go (nothing joins it)
static int spawn(void *(*fn)(void *), void *arg) {
  pthread_t th;
  if (pthread_create(&th, NULL, fn, arg) != 0) return 0;
  pthread_detach(th);
  return 1;
}

static void start(void) { spawn(queue_main, NULL); }

static void post(void (*run)(void *), void *arg) {
  task *t = malloc(sizeof *t);
  t->next = NULL;
  t->run = run;
  t->arg = arg;
  pthread_mutex_lock(&q_lock);
  if (q_tail) q_tail->next = t;
  else q_head = t;
  q_tail = t;
  pthread_mutex_unlock(&q_lock);
  pthread_cond_signal(&q_wake);
}

// On the queue (or under q_lock).
static listener *find(int id) {
  for (listener *l = listeners; l; l = l->next)
    if (l->id == id) return l;
  return NULL;
}

static void say_why(char *why, size_t len, const char *text) {
  if (why && len) snprintf(why, len, "%s", text);
}

static void say_errno(char *why, size_t len) {
  int e = errno;
  if (e == EADDRINUSE || e == EACCES) say_why(why, len, "Address already in use");
  else if (why && len) snprintf(why, len, "socket error %d (%s)", e, strerror(e));
}

// ── a request off a connection ──

typedef struct {
  char *p;
  size_t n, cap;
} buf;

static void put(buf *b, const void *p, size_t n) {
  if (b->n + n + 1 > b->cap) {
    b->cap = (b->n + n + 1) * 2;
    b->p = realloc(b->p, b->cap);
  }
  memcpy(b->p + b->n, p, n);
  b->n += n;
  b->p[b->n] = 0;
}

static void puts_(buf *b, const char *s) { put(b, s, strlen(s)); }

// A JSON string of bytes taken as Latin-1 (as a request's head is), so the JSON is UTF-8 whatever they are.
static void put_json(buf *b, const char *s, size_t n) {
  put(b, "\"", 1);
  for (size_t i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    char e[8];
    if (c == '"' || c == '\\') e[0] = '\\', e[1] = (char)c, put(b, e, 2);
    else if (c < 0x20) snprintf(e, sizeof e, "\\u%04x", c), put(b, e, 6);
    else if (c >= 0x80) e[0] = (char)(0xc0 | (c >> 6)), e[1] = (char)(0x80 | (c & 63)), put(b, e, 2);
    else put(b, (const char *)&c, 1);
  }
  put(b, "\"", 1);
}

static const char *trimmed(const char *s, const char *end, size_t *n) {
  while (s < end && (*s == ' ' || *s == '\t')) s++;
  while (end > s && (end[-1] == ' ' || end[-1] == '\t')) end--;
  *n = (size_t)(end - s);
  return s;
}

// An HTTP/1.x request, whole, as its JSON (without "request") and body: 0 for what is not one, or one too slow or big.
static int read_request(int c, buf *json, buf *body) {
  buf in = {0};
  char chunk[8192];
  char *end = NULL;
  while (!end) {
    if (in.n >= LISTEN_HEAD_MOST) goto fail;
    ssize_t got = recv(c, chunk, sizeof chunk, 0);
    if (got <= 0) goto fail;
    put(&in, chunk, (size_t)got);
    end = strstr(in.p, "\r\n\r\n");
  }
  size_t head_len = (size_t)(end - in.p);
  // the request line: METHOD SP PATH SP HTTP/1.x
  char *line_end = strstr(in.p, "\r\n");
  char *sp1 = memchr(in.p, ' ', (size_t)(line_end - in.p));
  char *sp2 = sp1 ? memchr(sp1 + 1, ' ', (size_t)(line_end - sp1 - 1)) : NULL;
  if (!sp1 || !sp2 || line_end - sp2 - 1 < 8 || strncmp(sp2 + 1, "HTTP/1.", 7) != 0) goto fail;
  puts_(json, "{\"method\":");
  put_json(json, in.p, (size_t)(sp1 - in.p));
  puts_(json, ",\"path\":");
  put_json(json, sp1 + 1, (size_t)(sp2 - sp1 - 1));
  puts_(json, ",\"headers\":[");
  long long length = 0;
  int first = 1;
  for (char *l = line_end + 2; l < in.p + head_len;) {
    char *e = strstr(l, "\r\n");
    if (!e || e > in.p + head_len) e = in.p + head_len;
    char *colon = memchr(l, ':', (size_t)(e - l));
    if (colon && colon > l) {
      size_t kn, vn;
      const char *k = trimmed(l, colon, &kn), *v = trimmed(colon + 1, e, &vn);
      if (kn == 14 && strncasecmp(k, "content-length", 14) == 0) length = strtoll(v, NULL, 10);
      if (!first) put(json, ",", 1);
      first = 0;
      put(json, "[", 1);
      put_json(json, k, kn);
      put(json, ",", 1);
      put_json(json, v, vn);
      put(json, "]", 1);
    }
    l = e + 2;
  }
  puts_(json, "]}");
  if (length < 0) goto fail;
  size_t start = head_len + 4;
  size_t have = in.n - start;
  if ((long long)have > length) have = (size_t)length;
  put(body, in.p + start, have > LISTEN_BODY_MOST ? LISTEN_BODY_MOST : have);
  long long left = length - (long long)(in.n - start);
  while (left > 0) {
    ssize_t got = recv(c, chunk, (size_t)(left < (long long)sizeof chunk ? left : (long long)sizeof chunk), 0);
    if (got <= 0) goto fail;
    if (body->n < LISTEN_BODY_MOST) put(body, chunk, (size_t)got < LISTEN_BODY_MOST - body->n ? (size_t)got : LISTEN_BODY_MOST - body->n);
    left -= got;
  }
  free(in.p);
  return 1;
fail:
  free(in.p);
  return 0;
}

typedef struct {
  listener *l;
  int c;
  buf json, body;
} taken;

// On the queue: the request handed on (numbered, its connection kept for the answer), or the connection closed.
static void hand_on(void *arg) {
  taken *t = arg;
  listener *l = t->l;
  if (l->closed) {
    close(t->c);
  } else {
    long n = ++l->requests;
    asked *a = malloc(sizeof *a);
    a->next = l->asked;
    a->request = n;
    a->c = t->c;
    l->asked = a;
    buf j = {0};
    char head[40];
    snprintf(head, sizeof head, "{\"request\":%ld,", n);
    puts_(&j, head);
    put(&j, t->json.p + 1, t->json.n - 1);  // the rest, after its "{"
    static const uint8_t none = 0;
    l->fn(l->ctx, j.p, j.n, t->body.n ? (const uint8_t *)t->body.p : &none, t->body.n);
    free(j.p);
  }
  free(t->json.p);
  free(t->body.p);
  free(t);
}

static void *read_main(void *arg) {
  taken *t = arg;
  struct timeval tv = {LISTEN_READ_MS / 1000, (LISTEN_READ_MS % 1000) * 1000};
  setsockopt(t->c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  setsockopt(t->c, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
  if (read_request(t->c, &t->json, &t->body)) {
    post(hand_on, t);
  } else {
    close(t->c);
    free(t->json.p);
    free(t->body.p);
    free(t);
  }
  return NULL;
}

// A listener's accepting thread: until its socket is shut (mb_listen_close: accept then fails at once).
static void *accept_main(void *arg) {
  listener *l = arg;
  for (;;) {
    int c = accept(l->fd, NULL, NULL);
    if (c < 0) {
      if (l->closed) break;
      if (errno == EINTR || errno == ECONNABORTED) continue;
      break;
    }
    if (l->closed) {
      close(c);
      continue;
    }
    taken *t = calloc(1, sizeof *t);
    t->l = l;
    t->c = c;
    if (!spawn(read_main, t)) close(c), free(t);
  }
  close(l->fd);
  return NULL;
}

// ── the API ──

int mb_listen_open(const char *host, int port, mb_listen_fn fn, void *ctx, int *bound, char *why, size_t why_len) {
  pthread_once(&once, start);
  int v6 = strcmp(host, "::1") == 0;
  if (!v6 && strcmp(host, "127.0.0.1") != 0) {
    say_why(why, why_len, "not a loopback address");
    return 0;
  }
  if (port < 0 || port > 65535) {
    say_why(why, why_len, "no such port");
    return 0;
  }
  int fd = socket(v6 ? AF_INET6 : AF_INET, SOCK_STREAM | SOCK_CLOEXEC, IPPROTO_TCP);
  if (fd < 0) {
    say_errno(why, why_len);
    return 0;
  }
  // (no SO_REUSEADDR: a port another program listens on is refused)
  int on = 1;
  struct sockaddr_storage at = {0};
  socklen_t at_len;
  if (v6) {
    setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &on, sizeof on);
    struct sockaddr_in6 *a = (struct sockaddr_in6 *)&at;
    a->sin6_family = AF_INET6;
    a->sin6_port = htons((uint16_t)port);
    a->sin6_addr.s6_addr[15] = 1;  // ::1
    at_len = sizeof *a;
  } else {
    struct sockaddr_in *a = (struct sockaddr_in *)&at;
    a->sin_family = AF_INET;
    a->sin_port = htons((uint16_t)port);
    a->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    at_len = sizeof *a;
  }
  if (bind(fd, (struct sockaddr *)&at, at_len) != 0 || listen(fd, 16) != 0) {
    say_errno(why, why_len);
    close(fd);
    return 0;
  }
  socklen_t got_len = at_len;
  getsockname(fd, (struct sockaddr *)&at, &got_len);
  if (bound) *bound = ntohs(v6 ? ((struct sockaddr_in6 *)&at)->sin6_port : ((struct sockaddr_in *)&at)->sin_port);

  // Kept once made (a few dozen bytes a listener: a login's, now and then), so a thread still holding it is safe.
  listener *l = calloc(1, sizeof *l);
  l->fd = fd;
  l->fn = fn;
  l->ctx = ctx;
  pthread_mutex_lock(&q_lock);
  l->id = ++listen_next_id;
  l->next = listeners;
  listeners = l;
  pthread_mutex_unlock(&q_lock);
  spawn(accept_main, l);
  return l->id;
}

static const char *reason(int status) {
  switch (status) {
    case 200: return "OK";
    case 302: return "Found";
    case 303: return "See Other";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 502: return "Bad Gateway";
    default: return "Status";
  }
}

typedef struct {
  int id;
  long request;
  buf out;
} answer;

static int send_all(int c, const char *p, size_t n) {
  while (n > 0) {
    ssize_t w = send(c, p, n > 1 << 20 ? 1 << 20 : n, MSG_NOSIGNAL);
    if (w <= 0) return -1;
    p += w;
    n -= (size_t)w;
  }
  return 0;
}

// On the queue: written there (a small page to a loopback peer; SO_SNDTIMEO bounds it), so a close asked after it ends
// the listener only once the answer is out: an app may exit as its sign-in's listener ends.
static void write_answer(void *arg) {
  answer *a = arg;
  pthread_mutex_lock(&q_lock);
  listener *l = find(a->id);
  pthread_mutex_unlock(&q_lock);
  for (asked **p = l ? &l->asked : NULL; p && *p; p = &(*p)->next) {
    if ((*p)->request != a->request) continue;
    asked *found = *p;
    *p = found->next;
    send_all(found->c, a->out.p, a->out.n);
    shutdown(found->c, SHUT_WR);
    close(found->c);
    free(found);
    break;
  }
  free(a->out.p);
  free(a);
}

void mb_listen_respond(int id, long request, int status, const char *const *headers, int n, const uint8_t *body, size_t blen) {
  pthread_once(&once, start);
  // The answer, made now (the pointers are the caller's): the connection's own headers are ours.
  answer *a = calloc(1, sizeof *a);
  a->id = id;
  a->request = request;
  char line[64];
  snprintf(line, sizeof line, "HTTP/1.1 %d %s\r\n", status, reason(status));
  puts_(&a->out, line);
  for (int i = 0; i + 1 < 2 * n; i += 2) {
    const char *k = headers[i], *v = headers[i + 1];
    if (!k || !v || !strcasecmp(k, "connection") || !strcasecmp(k, "transfer-encoding") || !strcasecmp(k, "content-length") ||
        !strcasecmp(k, "keep-alive"))
      continue;
    puts_(&a->out, k);
    puts_(&a->out, ": ");
    for (const char *c = v; *c; c++)
      if (*c != '\r' && *c != '\n') put(&a->out, c, 1);
    puts_(&a->out, "\r\n");
  }
  snprintf(line, sizeof line, "Connection: close\r\nContent-Length: %zu\r\n\r\n", blen);
  puts_(&a->out, line);
  if (blen) put(&a->out, body, blen);
  post(write_answer, a);
}

static void close_on_queue(void *arg) {
  int id = (int)(intptr_t)arg;
  pthread_mutex_lock(&q_lock);
  listener *l = find(id);
  if (l) {
    for (listener **p = &listeners; *p; p = &(*p)->next)
      if (*p == l) {
        *p = l->next;
        break;
      }
  }
  pthread_mutex_unlock(&q_lock);
  if (!l) return;
  __atomic_store_n(&l->closed, 1, __ATOMIC_SEQ_CST);
  shutdown(l->fd, SHUT_RDWR);  // its accepting thread ends (and closes it)
  while (l->asked) {
    asked *a = l->asked;
    l->asked = a->next;
    close(a->c);
    free(a);
  }
  l->fn(l->ctx, NULL, 0, NULL, 0);
}

void mb_listen_close(int id) {
  pthread_once(&once, start);
  post(close_on_queue, (void *)(intptr_t)id);
}
