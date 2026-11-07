// The core host call arguments, shared by the Linux and Windows hosts.
#ifndef STILLFAIL_CORE_JSON_H
#define STILLFAIL_CORE_JSON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

#endif
