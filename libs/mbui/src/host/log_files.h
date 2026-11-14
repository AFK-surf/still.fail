// What a host's log files are, whatever the system (win_logs.h is Windows' system side; scripts/log_files_test.c its
// tests, run by scripts/check.sh on any machine): a line made fit to keep (log_clean), the bounded queue between the
// threads that say lines and the one that writes them (lf_queue), which file a line goes to and which files go
// (lf_pick, lf_oldest). Plain C, no system's calls, no allocation.
#ifndef MB_LOG_FILES_H
#define MB_LOG_FILES_H
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ---- a line made fit to keep ----

// The most of one line kept, in bytes: past it the line is cut (and a file's overshoot of its size is at most this).
#define LF_LINE_MOST 4096

static const char lf_cut[] = "<cut>";

static int lf_lower(int c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
static int lf_digit(int c) { return c >= '0' && c <= '9'; }
static int lf_alpha(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static int lf_word(int c) { return lf_alpha(c) || lf_digit(c) || c == '_' || c == '-'; }

// `word` at s[i], case aside (its length; 0: not there)
static size_t lf_at(const char *s, size_t n, size_t i, const char *word) {
  size_t k = 0;
  for (; word[k]; k++)
    if (i + k >= n || lf_lower((unsigned char)s[i + k]) != word[k]) return 0;
  return k;
}

typedef struct {
  char *out;
  size_t cap, o;
} lf_out;
static void lf_put(lf_out *w, const char *s, size_t n) {
  if (w->o + n > w->cap) n = w->cap - w->o;
  memcpy(w->out + w->o, s, n);
  w->o += n;
}
static void lf_says_cut(lf_out *w) { lf_put(w, lf_cut, sizeof lf_cut - 1); }

// The end of a URL's text from i, as logs and JSON have it.
static size_t lf_url_end(const char *s, size_t n, size_t i) {
  while (i < n) {
    unsigned char c = (unsigned char)s[i];
    if (c <= ' ' || c == '"' || c == '\'' || c == '<' || c == '>' || c == '`' || c == '\\') break;
    i++;
  }
  return i;
}

// A URL from s[i] (its scheme): only its scheme and host kept, for a link says who is signing in, what is shared and
// the tokens of both in its user, path, query and fragment. Where it took one, the end of it; else i.
static size_t lf_try_url(const char *s, size_t n, size_t i, lf_out *w) {
  size_t k = i;
  while (k < n && (lf_alpha((unsigned char)s[k]) || lf_digit((unsigned char)s[k]) || s[k] == '+' || s[k] == '-' || s[k] == '.')) k++;
  if (k == i || !lf_at(s, n, k, "://")) return i;
  size_t host = k + 3, end = lf_url_end(s, n, host), stop = host;
  while (stop < end && s[stop] != '/' && s[stop] != '?' && s[stop] != '#') stop++;
  size_t from = host;
  for (size_t a = host; a < stop; a++)
    if (s[a] == '@') from = a + 1;  // (the user and password before a host)
  lf_put(w, s + i, host - i);
  lf_put(w, s + from, stop - from);
  if (stop < end) {
    lf_put(w, "/", 1);
    lf_says_cut(w);
  }
  return end;
}

// What names a secret, ahead of its value (`"accessToken":"…"`, `password=…`), ending a name or all of it.
static const char *const lf_names[] = {"token", "secret", "password", "passwd", "passphrase", "pwd", "apikey", "api_key", "api-key",
                                       "private_key", "privatekey", "credential", "credentials", "signature", NULL};
// What takes the whole of the rest of the line with it (a header's value has spaces in it, `Bearer …`).
static const char *const lf_names_all[] = {"authorization", "cookie", NULL};

// After a name at `at`: its value's start, past an optional closing quote, spaces and : or =; 0 where none follows.
static size_t lf_value_at(const char *s, size_t n, size_t at) {
  if (at < n && s[at] == '\\') at++;  // (JSON said within JSON)
  if (at < n && (s[at] == '"' || s[at] == '\'')) at++;
  while (at < n && s[at] == ' ') at++;
  if (at >= n || (s[at] != ':' && s[at] != '=')) return 0;
  at++;
  while (at < n && s[at] == ' ') at++;
  return at < n ? at : 0;
}

// A secret's name at s[i] and its value: the name kept, the value cut. Where it took one, the end of it; else i.
static size_t lf_try_named(const char *s, size_t n, size_t i, lf_out *w) {
  for (int all = 0; all < 2; all++) {
    for (const char *const *name = all ? lf_names_all : lf_names; *name; name++) {
      size_t len = lf_at(s, n, i, *name);
      if (!len) continue;
      size_t v = lf_value_at(s, n, i + len);
      if (!v) continue;
      lf_put(w, s + i, v - i);
      lf_says_cut(w);
      if (all) return n;
      size_t e = v;
      if (s[v] == '\\' && v + 1 < n && s[v + 1] == '"') {
        for (e = v + 2; e < n && s[e] != '"'; e++) {}
        return e < n ? e + 1 : n;
      }
      if (s[v] == '"' || s[v] == '\'') {
        for (e = v + 1; e < n && s[e] != s[v]; e++)
          if (s[e] == '\\') e++;
        return e < n ? e + 1 : n;
      }
      while (e < n && s[e] != ' ' && s[e] != '&' && s[e] != ',' && s[e] != ';' && s[e] != '}' && s[e] != ')' && s[e] != ']' && s[e] != '"') e++;
      return e;
    }
  }
  return i;
}

// `bearer <value>` at s[i] (a header said without its name). Where it took one, the end of it; else i.
static size_t lf_try_bearer(const char *s, size_t n, size_t i, lf_out *w) {
  size_t len = lf_at(s, n, i, "bearer ");
  if (!len || i + len >= n) return i;
  lf_put(w, s + i, len);
  lf_says_cut(w);
  size_t e = i + len;
  while (e < n && s[e] != ' ' && s[e] != '"' && s[e] != '\'' && s[e] != ',') e++;
  return e;
}

static int lf_email_local(int c) { return lf_alpha(c) || lf_digit(c) || c == '.' || c == '_' || c == '%' || c == '+' || c == '-'; }

// An address from s[i]: whose it is is a person's. Where it took one, the end of it; else i.
static size_t lf_try_email(const char *s, size_t n, size_t i, lf_out *w) {
  size_t k = i;
  while (k < n && lf_email_local((unsigned char)s[k])) k++;
  if (k == i || k >= n || s[k] != '@') return i;
  size_t e = k + 1, dot = 0;
  while (e < n && (lf_alpha((unsigned char)s[e]) || lf_digit((unsigned char)s[e]) || s[e] == '-' || s[e] == '.')) {
    if (s[e] == '.' && e > k + 1) dot = e;
    e++;
  }
  if (!dot || dot + 1 >= e) return i;
  lf_put(w, "<email>", 7);
  return e;
}

// A home folder's name (`C:\Users\<name>\…`): whose it is is a person's. Where it took one, the end of it; else i.
static size_t lf_try_home(const char *s, size_t n, size_t i, lf_out *w) {
  if (s[i] != '\\' && s[i] != '/') return i;
  size_t len = lf_at(s, n, i + 1, "users");
  if (!len || i + 1 + len >= n || s[i + 1 + len] != s[i]) return i;
  size_t e = i + 2 + len;
  while (e < n && s[e] == s[i]) e++;  // (a path as JSON says it: \\Users\\)
  lf_put(w, s + i, e - i);
  size_t name = e;
  while (e < n && s[e] != '\\' && s[e] != '/' && s[e] != ' ' && s[e] != '"') e++;
  if (e > name) lf_says_cut(w);
  return e;
}

// A long run of what keys and tokens are made of, letters and digits both (a name in a program has no digits, or
// short runs of them): what it is cannot be told, so it goes. With a '/' in it (base64's) a path is as likely: only
// where longer, and of both cases. Where it took one, the end of it; else i.
static size_t lf_try_opaque(const char *s, size_t n, size_t i, lf_out *w) {
  size_t e = i;
  int digit = 0, lower = 0, upper = 0, slash = 0;
  while (e < n) {
    int c = (unsigned char)s[e];
    if (lf_digit(c)) digit = 1;
    else if (c >= 'a' && c <= 'z') lower = 1;
    else if (c >= 'A' && c <= 'Z') upper = 1;
    else if (c == '/') slash = 1;
    else if (c != '_' && c != '-' && c != '+' && c != '=') break;
    e++;
  }
  size_t len = e - i;
  if (len < 32 || !digit || !(lower || upper)) return i;
  if (slash && (len < 40 || !lower || !upper)) return i;
  lf_says_cut(w);
  return e;
}

// `in`'s n bytes as they may be kept in a log file, into `out` (cap bytes, at least a line's most): what a host's log
// and its stderr carry that must stay out of a file: secrets, a person's address and home folder's name, what links
// say; 0 where the line is not kept at all, else its length. Written for what passes here (the core's [core error]
// lines, the app's "AUTH_URL …", "link opens …", "SIGN_IN taken in: …", a shell's `<name>: …`), and not a proof: a
// secret said in the words of a line, with no name before it and shorter than a key's run, is not found.
static size_t log_clean(const char *in, size_t n, char *out, size_t cap) {
  // (MB_CORE_TRACE=1's and MB_CORE_DEBUG=1's: what the core says and is asked, whole: a developer's terminal's alone)
  if (lf_at(in, n, 0, "[core trace]") || lf_at(in, n, 0, "[core debug]")) return 0;
  int cut = n > LF_LINE_MOST;
  if (cut) n = LF_LINE_MOST;
  lf_out w = {out, cap, 0};
  size_t i = 0;
  int run_begins = 1;  // at the start of a word's run: what is looked for from a run's start alone
  while (i < n && w.o < cap) {
    size_t to = i;
    if (run_begins) {
      to = lf_try_url(in, n, i, &w);
      if (to == i) to = lf_try_email(in, n, i, &w);
      if (to == i) to = lf_try_bearer(in, n, i, &w);
      if (to == i) to = lf_try_opaque(in, n, i, &w);
    }
    if (to == i) to = lf_try_named(in, n, i, &w);
    if (to == i) to = lf_try_home(in, n, i, &w);
    if (to != i) {
      i = to;
      run_begins = i >= n || !lf_word((unsigned char)in[i]);
      continue;
    }
    unsigned char c = (unsigned char)in[i++];
    // (a line stays one line, and a terminal's escapes are nobody's to replay)
    char put = c < 0x20 || c == 0x7f ? ' ' : (char)c;
    lf_put(&w, &put, 1);
    run_begins = !lf_word(c);
  }
  // (a cut through a character's bytes: the character goes)
  if (cut || i < n) {
    size_t e = w.o;
    while (e > 0 && ((unsigned char)out[e - 1] & 0xC0) == 0x80) e--;
    if (e > 0 && ((unsigned char)out[e - 1] & 0x80)) e--;
    size_t whole = e;
    if (e < w.o) {
      unsigned char lead = (unsigned char)out[e];
      size_t need = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1;
      if (e + need == w.o) whole = w.o;
    }
    w.o = whole;
  }
  return w.o;
}

// ---- the queue between those who say lines and who writes them ----

// A ring of records, [kind 1][when 8][length 2][bytes]: it holds what it holds and what does not fit is counted and
// let go, so whoever says a line (the window's thread) never waits for a disk. Its user locks it, only as long as a
// call here takes.
typedef struct {
  unsigned char *buf;
  size_t cap, head, used;
  uint64_t dropped;
} lf_queue;

static void lf_ring_put(lf_queue *q, const void *p, size_t n) {
  size_t at = (q->head + q->used) % q->cap, first = q->cap - at < n ? q->cap - at : n;
  memcpy(q->buf + at, p, first);
  memcpy(q->buf, (const unsigned char *)p + first, n - first);
  q->used += n;
}
static void lf_ring_take(lf_queue *q, void *p, size_t n) {
  size_t first = q->cap - q->head < n ? q->cap - q->head : n;
  if (p) {
    memcpy(p, q->buf + q->head, first);
    memcpy((unsigned char *)p + first, q->buf, n - first);
  }
  q->head = (q->head + n) % q->cap;
  q->used -= n;
}

// One line in, cut to a line's most; 0 where it did not fit (counted: lf_queue's dropped).
static int lf_push(lf_queue *q, int kind, uint64_t when, const char *text, size_t n) {
  if (n > LF_LINE_MOST) n = LF_LINE_MOST;
  if (q->cap - q->used < 11 + n) {
    q->dropped++;
    return 0;
  }
  unsigned char k = (unsigned char)kind;
  uint16_t len = (uint16_t)n;
  lf_ring_put(q, &k, 1);
  lf_ring_put(q, &when, 8);
  lf_ring_put(q, &len, 2);
  lf_ring_put(q, text, n);
  return 1;
}

// The oldest line out into `out` (at least a line's most): its length; -1 where there is none.
static int lf_pop(lf_queue *q, int *kind, uint64_t *when, char *out) {
  if (q->used == 0) return -1;
  unsigned char k;
  uint16_t len;
  lf_ring_take(q, &k, 1);
  lf_ring_take(q, when, 8);
  lf_ring_take(q, &len, 2);
  lf_ring_take(q, out, len);
  *kind = k;
  return len;
}

// ---- the files ----

// The files a stream keeps, named <prefix>-<YYYYMMDD>-<NNN>.log: in the order of their names, the order they began.
#define LF_FILES_MOST 64
#define LF_NAME_MOST 48
typedef struct {
  char name[LF_NAME_MOST];
  unsigned long long bytes;
} lf_file;

static void lf_name(char *out, const char *prefix, unsigned day, unsigned seq) {
  snprintf(out, LF_NAME_MOST, "%s-%08u-%03u.log", prefix, day, seq);
}

// Whether `name` is one of a stream's files, its day and number if so.
static int lf_parse(const char *name, const char *prefix, unsigned *day, unsigned *seq) {
  size_t p = strlen(prefix), n = strlen(name);
  if (n != p + 17 || memcmp(name, prefix, p) != 0 || name[p] != '-' || name[p + 9] != '-' || strcmp(name + p + 13, ".log") != 0) return 0;
  unsigned d = 0, s = 0;
  for (size_t i = p + 1; i < p + 9; i++) {
    if (!lf_digit((unsigned char)name[i])) return 0;
    d = d * 10 + (unsigned)(name[i] - '0');
  }
  for (size_t i = p + 10; i < p + 13; i++) {
    if (!lf_digit((unsigned char)name[i])) return 0;
    s = s * 10 + (unsigned)(name[i] - '0');
  }
  *day = d;
  *seq = s;
  return 1;
}

// Which file `n` more bytes of `prefix`'s go to on `day` (`files` what is there now, in any order): the day's last
// while they fit in it within `most`, else the next of the day. Into `out` (LF_NAME_MOST); 1 where that file is new.
// (A number run out, 999 files in a day: the last again, whose lines then go on only as it is removed.)
static int lf_pick(const lf_file *files, int count, const char *prefix, unsigned day, unsigned long long most, size_t n, char *out) {
  unsigned last = 0;
  unsigned long long bytes = 0;
  int any = 0;
  for (int i = 0; i < count; i++) {
    unsigned d, s;
    if (lf_parse(files[i].name, prefix, &d, &s) && d == day && (!any || s >= last)) {
      any = 1;
      last = s;
      bytes = files[i].bytes;
    }
  }
  if (any && (bytes + n <= most || last >= 999)) {
    lf_name(out, prefix, day, last);
    return 0;
  }
  lf_name(out, prefix, day, any ? last + 1 : 1);
  return 1;
}

// The oldest of a stream's files beyond the `kept` newest: its index in `files`, -1 where none is beyond them.
static int lf_oldest(const lf_file *files, int count, const char *prefix, int kept) {
  int have = 0, oldest = -1;
  unsigned od = 0, os = 0;
  for (int i = 0; i < count; i++) {
    unsigned d, s;
    if (!lf_parse(files[i].name, prefix, &d, &s)) continue;
    have++;
    if (oldest < 0 || d < od || (d == od && s < os)) {
      oldest = i;
      od = d;
      os = s;
    }
  }
  return have > kept ? oldest : -1;
}

#endif
