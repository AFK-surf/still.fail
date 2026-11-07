// Shared core listen.* queues and dispatch; the including host supplies its lock API and answer().
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

#ifdef _WIN32
static CRITICAL_SECTION listen_lock;
#define core_listen_lock() EnterCriticalSection(&listen_lock)
#define core_listen_unlock() LeaveCriticalSection(&listen_lock)
#else
static pthread_mutex_t listen_lock = PTHREAD_MUTEX_INITIALIZER;
#define core_listen_lock() pthread_mutex_lock(&listen_lock)
#define core_listen_unlock() pthread_mutex_unlock(&listen_lock)
#endif
static listening *listens;

static listening *find_listen(int lid) {
  for (listening *l = listens; l; l = l->next)
    if (l->lid == lid && !l->ended) return l;
  return NULL;
}

// What a listener says, from its queue: a request (handed to a waiting listen.next, else kept), or its end.
static void listen_took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  listening *l = ctx;
  core_listen_lock();
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
    core_listen_unlock();
    for (waiter *n; w; w = n) n = w->next, answer(w->id, "{\"end\":true}", NULL, NULL, 0), free(w);
    free(l);
    return;
  }
  if (l->waiting) {
    waiter *w = l->waiting;
    l->waiting = w->next;
    if (!l->waiting) l->waiting_tail = NULL;
    core_listen_unlock();
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
  core_listen_unlock();
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
    core_listen_lock();
    l->lid = -1;
    l->next = listens;
    listens = l;
    core_listen_unlock();
    int lid = mb_listen_open(host, (int)port, listen_took, l, &bound, why, sizeof why);
    free(host);
    core_listen_lock();
    if (!lid) {
      for (listening **p = &listens; *p; p = &(*p)->next)
        if (*p == l) {
          *p = l->next;
          break;
        }
      core_listen_unlock();
      free(l);
      answer(id, NULL, why, NULL, 0);
      return;
    }
    l->lid = lid;
    core_listen_unlock();
    snprintf(buf, sizeof buf, "{\"id\":%d,\"port\":%d}", lid, bound);
    answer(id, buf, NULL, NULL, 0);
  } else if (strcmp(op, "listen.next") == 0) {
    core_listen_lock();
    listening *l = has_id ? find_listen((int)which) : NULL;
    if (!l) {
      core_listen_unlock();
      answer(id, "{\"end\":true}", NULL, NULL, 0);
      return;
    }
    if (l->requests) {
      request *r = l->requests;
      l->requests = r->next;
      if (!l->requests) l->requests_tail = NULL;
      core_listen_unlock();
      answer(id, r->json, NULL, r->body, r->blen);
      free(r->json), free(r->body), free(r);
      return;
    }
    waiter *w = calloc(1, sizeof *w);
    w->id = id;
    if (l->waiting_tail) l->waiting_tail->next = w;
    else l->waiting = w;
    l->waiting_tail = w;
    core_listen_unlock();
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
  core_listen_lock();
  for (listening *l = listens; l && n < 64; l = l->next)
    if (l->lid > 0 && !l->ended) lids[n++] = l->lid;
  core_listen_unlock();
  for (int i = 0; i < n; i++) mb_listen_close(lids[i]);
}

#undef core_listen_lock
#undef core_listen_unlock
