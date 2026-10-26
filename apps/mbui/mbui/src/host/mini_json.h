// A little JSON, read: what a host is given as JSON and reads in C (the app's menus, @hostapi.menu_setup: win_life.h's
// icon in the notification area, linux_life.h's among the desktop's apps' icons). Each value parsed whole into a tree
// of its own (jparse), freed with it (jv_free); a number kept only as one (its digits unread).
#ifndef MB_MINI_JSON_H
#define MB_MINI_JSON_H
#include <stdlib.h>
#include <string.h>

typedef struct jv {
  char kind;  // o object, a array, s string, n number, t true, f false, z null
  int n;      // an object's or an array's how many
  struct jv *at;
  char **keys;  // an object's
  char *s;      // a string's, UTF-8
} jv;

static void jv_free(jv *v) {
  if (!v) return;
  for (int i = 0; i < v->n; i++) {
    jv_free(&v->at[i]);
    if (v->keys) free(v->keys[i]);
  }
  free(v->at);
  free(v->keys);
  free(v->s);
}

static void jws(const char **p) {
  while (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r') (*p)++;
}

static int hex4(const char *p) {
  int v = 0;
  for (int i = 0; i < 4; i++) {
    char c = p[i];
    v <<= 4;
    if (c >= '0' && c <= '9') v |= c - '0';
    else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
    else return -1;
  }
  return v;
}

static char *jstr(const char **p) {
  if (**p != '"') return NULL;
  (*p)++;
  size_t cap = 16, n = 0;
  char *b = (char *)malloc(cap);
  while (b && **p && **p != '"') {
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
    c = *(*p)++;
    unsigned cp = 0;
    switch (c) {
      case 'n': b[n++] = '\n'; continue;
      case 't': b[n++] = '\t'; continue;
      case 'r': b[n++] = '\r'; continue;
      case 'b': b[n++] = '\b'; continue;
      case 'f': b[n++] = '\f'; continue;
      case 'u': {
        int h = hex4(*p);
        if (h < 0) goto bad;
        *p += 4;
        cp = (unsigned)h;
        if (cp >= 0xD800 && cp < 0xDC00 && (*p)[0] == '\\' && (*p)[1] == 'u') {
          int l = hex4(*p + 2);
          if (l >= 0xDC00 && l < 0xE000) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + ((unsigned)l - 0xDC00);
            *p += 6;
          }
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
      case 0: goto bad;
      default: b[n++] = c; continue;  // \" \\ \/
    }
  }
  if (!b || **p != '"') goto bad;
  (*p)++;
  b[n] = 0;
  return b;
bad:
  free(b);
  return NULL;
}

static int jparse(const char **p, jv *v, int depth) {
  memset(v, 0, sizeof *v);
  jws(p);
  if (depth > 32) return 0;
  char c = **p;
  if (c == '{' || c == '[') {
    v->kind = c == '{' ? 'o' : 'a';
    (*p)++;
    jws(p);
    char end = c == '{' ? '}' : ']';
    if (**p == end) {
      (*p)++;
      return 1;
    }
    for (;;) {
      char *key = NULL;
      if (v->kind == 'o') {
        jws(p);
        key = jstr(p);
        jws(p);
        if (!key || **p != ':') {
          free(key);
          return 0;
        }
        (*p)++;
      }
      jv *at = (jv *)realloc(v->at, sizeof(jv) * (size_t)(v->n + 1));
      if (!at) {
        free(key);
        return 0;
      }
      v->at = at;
      if (v->kind == 'o') {
        char **keys = (char **)realloc(v->keys, sizeof(char *) * (size_t)(v->n + 1));
        if (!keys) {
          free(key);
          return 0;
        }
        v->keys = keys;
        v->keys[v->n] = key;
      }
      int ok = jparse(p, &v->at[v->n], depth + 1);
      v->n++;
      if (!ok) return 0;
      jws(p);
      if (**p == ',') {
        (*p)++;
        continue;
      }
      if (**p == end) {
        (*p)++;
        return 1;
      }
      return 0;
    }
  }
  if (c == '"') {
    v->kind = 's';
    v->s = jstr(p);
    return v->s != NULL;
  }
  if (!strncmp(*p, "true", 4)) return v->kind = 't', *p += 4, 1;
  if (!strncmp(*p, "false", 5)) return v->kind = 'f', *p += 5, 1;
  if (!strncmp(*p, "null", 4)) return v->kind = 'z', *p += 4, 1;
  if (c == '-' || (c >= '0' && c <= '9')) {
    v->kind = 'n';
    while (**p && strchr("+-.eE0123456789", **p)) (*p)++;
    return 1;
  }
  return 0;
}

// an object's field, or NULL
static const jv *jget(const jv *o, const char *key) {
  if (!o || o->kind != 'o') return NULL;
  for (int i = 0; i < o->n; i++)
    if (!strcmp(o->keys[i], key)) return &o->at[i];
  return NULL;
}

static const char *jtext(const jv *o, const char *key) {
  const jv *v = jget(o, key);
  return v && v->kind == 's' ? v->s : "";
}

#endif
