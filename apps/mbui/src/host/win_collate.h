// The order people read names in, for the core (its Host.collate: client/core-ts's text.collate, a call the engine hands
// the host to answer at once: engine.h app_sync), the system's as Windows sorts them (CompareStringEx: case, accents and
// widths aside, digits by their value, in the person's first display language: 中文 by pinyin, zh-CN's own order),
// each name's place in it, equal names one place, as apple_collate.h has it on Apple's systems. With none of the
// host's, the core orders by hand. Included by win_core.c and core/collate_test_win.c (scripts/win.sh collate).
#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// how a name compares with another in `locale`: <0, 0, >0
static int win_collate_cmp(const WCHAR *a, const WCHAR *b, const WCHAR *locale) {
  int r = CompareStringEx(locale, LINGUISTIC_IGNORECASE | LINGUISTIC_IGNOREDIACRITIC | NORM_IGNOREWIDTH | SORT_DIGITSASNUMBERS,
                          a, -1, b, -1, NULL, NULL, 0);
  return r == CSTR_LESS_THAN ? -1 : r == CSTR_GREATER_THAN ? 1 : 0;
}

typedef struct {
  const WCHAR *const *names;
  const WCHAR *locale;
} win_collating;

// (stable: names alike stay in the order they came)
static int __cdecl win_collate_order(void *ctx, const void *x, const void *y) {
  const win_collating *c = (const win_collating *)ctx;
  int i = *(const int *)x, j = *(const int *)y;
  int r = win_collate_cmp(c->names[i], c->names[j], c->locale);
  return r ? r : (i > j) - (i < j);
}

// Each of the `n` names' place in their order in `locale` (equal ones the first of their place's), into `place`.
static void win_collate(const WCHAR *const *names, int n, const WCHAR *locale, int *place) {
  int *order = (int *)malloc(sizeof(int) * (size_t)(n ? n : 1));
  if (!order) return;
  for (int i = 0; i < n; i++) order[i] = i;
  win_collating c = {names, locale};
  qsort_s(order, (size_t)n, sizeof(int), win_collate_order, &c);
  int at = 0;
  for (int k = 0; k < n; k++) {
    int i = order[k];
    if (k > 0 && win_collate_cmp(names[order[k - 1]], names[i], locale) != 0) at = k;
    place[i] = at;
  }
  free(order);
}

// the person's first display language (zh-CN, en-US…), else their locale's, into `buf`
static const WCHAR *win_collate_locale(WCHAR *buf, ULONG cap) {
  ULONG count = 0, len = cap;
  if (GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &count, buf, &len) && count > 0 && buf[0]) return buf;
  if (GetUserDefaultLocaleName(buf, (int)cap)) return buf;
  return LOCALE_NAME_USER_DEFAULT;
}

// a JSON string at *p (its quote), its words as UTF-16 (malloc'd), *p after it; NULL where it is none
static WCHAR *win_collate_string(const char **p, const char *end) {
  if (*p >= end || **p != '"') return NULL;
  (*p)++;
  size_t cap = 16, n = 0;
  char *b = (char *)malloc(cap);
  while (b && *p < end && **p != '"') {
    if (n + 5 > cap) {
      char *g = (char *)realloc(b, cap *= 2);
      if (!g) break;
      b = g;
    }
    char c = *(*p)++;
    if (c != '\\') {
      b[n++] = c;
      continue;
    }
    if (*p >= end) break;
    c = *(*p)++;
    if (c == 'u' && *p + 4 <= end) {
      unsigned cp = 0;
      for (int i = 0; i < 4; i++) {
        char h = (*p)[i];
        cp = cp * 16 + (unsigned)(h >= 'a' ? h - 'a' + 10 : h >= 'A' ? h - 'A' + 10 : h - '0');
      }
      *p += 4;
      if (cp >= 0xD800 && cp < 0xDC00 && *p + 6 <= end && (*p)[0] == '\\' && (*p)[1] == 'u') {
        unsigned lo = 0;
        for (int i = 2; i < 6; i++) {
          char h = (*p)[i];
          lo = lo * 16 + (unsigned)(h >= 'a' ? h - 'a' + 10 : h >= 'A' ? h - 'A' + 10 : h - '0');
        }
        if (lo >= 0xDC00 && lo < 0xE000) cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00), *p += 6;
      }
      if (cp < 0x80) b[n++] = (char)cp;
      else if (cp < 0x800) b[n++] = (char)(0xC0 | (cp >> 6)), b[n++] = (char)(0x80 | (cp & 0x3F));
      else if (cp < 0x10000)
        b[n++] = (char)(0xE0 | (cp >> 12)), b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)), b[n++] = (char)(0x80 | (cp & 0x3F));
      else
        b[n++] = (char)(0xF0 | (cp >> 18)), b[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)),
        b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)), b[n++] = (char)(0x80 | (cp & 0x3F));
      continue;
    }
    b[n++] = c == 'n' ? '\n' : c == 't' ? '\t' : c == 'r' ? '\r' : c == 'b' ? '\b' : c == 'f' ? '\f' : c;
  }
  if (!b || *p >= end || **p != '"') {
    free(b);
    return NULL;
  }
  (*p)++;
  int w = MultiByteToWideChar(CP_UTF8, 0, b, (int)n, NULL, 0);
  WCHAR *s = (WCHAR *)calloc((size_t)w + 1, sizeof(WCHAR));
  if (s) MultiByteToWideChar(CP_UTF8, 0, b, (int)n, s, w);
  free(b);
  return s;
}

static void win_collate_ws(const char **p, const char *end) {
  while (*p < end && (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r')) (*p)++;
}

// The core's ask (`{"names": [...]}`) answered in `locale` (NULL: the person's first display language): `{"value":
// [place, …]}`, or why not; malloc'd, NUL-terminated.
static char *win_collate_answer(const char *json, size_t len, const WCHAR *locale) {
  const char *end = json + len, *p = json;
  const char *key = NULL;
  for (const char *q = json; q + 7 <= end; q++)
    if (!memcmp(q, "\"names\"", 7)) {
      key = q + 7;
      break;
    }
  WCHAR **names = NULL;
  int n = 0, ok = 0;
  if (key) {
    p = key;
    win_collate_ws(&p, end);
    if (p < end && *p == ':') p++;
    win_collate_ws(&p, end);
    if (p < end && *p == '[') {
      p++;
      win_collate_ws(&p, end);
      ok = 1;
      while (ok && p < end && *p != ']') {
        WCHAR *s = win_collate_string(&p, end);
        WCHAR **g = s ? (WCHAR **)realloc(names, sizeof(WCHAR *) * (size_t)(n + 1)) : NULL;
        if (!g) {
          free(s);
          ok = 0;
          break;
        }
        names = g;
        names[n++] = s;
        win_collate_ws(&p, end);
        if (p < end && *p == ',') p++;
        win_collate_ws(&p, end);
      }
      ok = ok && p < end && *p == ']';
    }
  }
  char *out = NULL;
  if (ok) {
    WCHAR buf[LOCALE_NAME_MAX_LENGTH * 4];
    const WCHAR *in = locale ? locale : win_collate_locale(buf, sizeof buf / sizeof buf[0]);
    int *place = (int *)calloc((size_t)(n ? n : 1), sizeof(int));
    size_t cap = 16 + (size_t)n * 12, o = 0;
    out = place ? (char *)malloc(cap) : NULL;
    if (out) {
      win_collate((const WCHAR *const *)names, n, in, place);
      o += (size_t)snprintf(out, cap, "{\"value\":[");
      for (int i = 0; i < n; i++) o += (size_t)snprintf(out + o, cap - o, "%s%d", i ? "," : "", place[i]);
      snprintf(out + o, cap - o, "]}");
    }
    free(place);
  } else {
    out = _strdup("{\"error\":\"text.collate: names are strings\"}");
  }
  for (int i = 0; i < n; i++) free(names[i]);
  free(names);
  return out;
}
