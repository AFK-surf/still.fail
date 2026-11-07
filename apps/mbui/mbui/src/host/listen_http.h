// HTTP request parsing and byte buffers shared by the Linux and Windows loopback listeners.
// Included after each host defines its request limits and socket API.
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
#ifdef _WIN32
static int read_request(SOCKET c, buf *json, buf *body) {
#else
static int read_request(int c, buf *json, buf *body) {
#endif
  buf in = {0};
  char chunk[8192];
  char *end = NULL;
  while (!end) {
    if (in.n >= LISTEN_HEAD_MOST) goto fail;
#ifdef _WIN32
    int got = recv(c, chunk, sizeof chunk, 0);
#else
    ssize_t got = recv(c, chunk, sizeof chunk, 0);
#endif
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
#ifdef _WIN32
      if (kn == 14 && _strnicmp(k, "content-length", 14) == 0) length = _strtoi64(v, NULL, 10);
#else
      if (kn == 14 && strncasecmp(k, "content-length", 14) == 0) length = strtoll(v, NULL, 10);
#endif
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
#ifdef _WIN32
    int got = recv(c, chunk, (int)(left < (long long)sizeof chunk ? left : (long long)sizeof chunk), 0);
#else
    ssize_t got = recv(c, chunk, (size_t)(left < (long long)sizeof chunk ? left : (long long)sizeof chunk), 0);
#endif
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
