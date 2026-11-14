// A delta applied, as the desktop hosts' updaters apply one (mac_app.m's Updates, linux_update.h, win_update.h): the
// installed app's files turned into the release's raw package, whose SHA-256 the feed says, so that a few MB are
// downloaded instead of the whole package. Its format is still.fail's scripts/delta.ts's (little-endian):
//
//   "SFDELTA1"; u32 n_files, each { u16 len; UTF-8 path }   the old blob: these files (relative to the app's root, '/'
//                                                            between names) one after the other
//   u32 n_inflate (0 here); u64 old_size; 32 bytes the old blob's SHA-256; u32 n_deflate (0 here); u64 made_size
//   chunks { u32 raw_len (at most 1 MiB); u32 packed_len; packed_len bytes of raw deflate }, the last { 0, 0 }
//
// The chunks' bytes one after the other are a bsdiff stream (endsley's, uncompressed): records { i64 x, y, z; x bytes
// added to the old blob's at p (0 outside it); y bytes as they are }, p moved on by x, then by z. Only a tree's delta
// (n_files > 0) is taken here: the Android one (n_inflate, n_deflate) is the Java tool's.
//
// The old blob is made in memory (old_size, ~60 MB, at once) and checked against its size and SHA-256 before a byte is
// made; the chunks are inflated one at a time (each its own raw deflate stream, RFC 1951, inflated here: no library), and
// what they make written out as it is made. Whatever is wrong with a delta (it is untrusted until its made package's
// SHA-256 is checked: every length is checked before it is read) is refused with a short reason, never more.
//
// Plain C99 of no system's: compiled as C and Objective-C, by clang, gcc and MSVC. Its own SHA-256 is offered to the
// hosts as well (ud_sha256_*). update_delta_test.c (test/delta-c.test.ts) holds it to scripts/delta.ts and node's zlib.
#ifndef MB_UPDATE_DELTA_H
#define MB_UPDATE_DELTA_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__GNUC__) || defined(__clang__)
#define UD_FN static __attribute__((unused))
#else
#define UD_FN static
#endif

// ---- SHA-256 (FIPS 180-4) ----

typedef struct {
  uint32_t h[8];
  uint64_t len;  // bytes taken
  unsigned char buf[64];
  size_t have;
} ud_sha256;

static const uint32_t ud_sha_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
    0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
    0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

#define UD_ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void ud_sha256_block(ud_sha256 *s, const unsigned char *p) {
  uint32_t w[64], a, b, c, d, e, f, g, h;
  int i;
  for (i = 0; i < 16; i++)
    w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 | (uint32_t)p[4 * i + 2] << 8 | (uint32_t)p[4 * i + 3];
  for (i = 16; i < 64; i++) {
    uint32_t s0 = UD_ROR(w[i - 15], 7) ^ UD_ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = UD_ROR(w[i - 2], 17) ^ UD_ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  a = s->h[0], b = s->h[1], c = s->h[2], d = s->h[3], e = s->h[4], f = s->h[5], g = s->h[6], h = s->h[7];
  for (i = 0; i < 64; i++) {
    uint32_t t1 = h + (UD_ROR(e, 6) ^ UD_ROR(e, 11) ^ UD_ROR(e, 25)) + ((e & f) ^ (~e & g)) + ud_sha_k[i] + w[i];
    uint32_t t2 = (UD_ROR(a, 2) ^ UD_ROR(a, 13) ^ UD_ROR(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
    h = g, g = f, f = e, e = d + t1, d = c, c = b, b = a, a = t1 + t2;
  }
  s->h[0] += a, s->h[1] += b, s->h[2] += c, s->h[3] += d, s->h[4] += e, s->h[5] += f, s->h[6] += g, s->h[7] += h;
}

UD_FN void ud_sha256_init(ud_sha256 *s) {
  static const uint32_t h0[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  memcpy(s->h, h0, sizeof h0);
  s->len = 0;
  s->have = 0;
}

UD_FN void ud_sha256_update(ud_sha256 *s, const void *data, size_t n) {
  const unsigned char *p = (const unsigned char *)data;
  s->len += n;
  if (s->have) {
    size_t k = 64 - s->have < n ? 64 - s->have : n;
    memcpy(s->buf + s->have, p, k);
    s->have += k, p += k, n -= k;
    if (s->have < 64) return;
    ud_sha256_block(s, s->buf);
    s->have = 0;
  }
  for (; n >= 64; p += 64, n -= 64) ud_sha256_block(s, p);
  memcpy(s->buf, p, n);
  s->have = n;
}

UD_FN void ud_sha256_final(ud_sha256 *s, unsigned char out[32]) {
  uint64_t bits = s->len * 8;
  int i;
  s->buf[s->have++] = 0x80;
  if (s->have > 56) {
    memset(s->buf + s->have, 0, 64 - s->have);
    ud_sha256_block(s, s->buf);
    s->have = 0;
  }
  memset(s->buf + s->have, 0, 56 - s->have);
  for (i = 0; i < 8; i++) s->buf[56 + i] = (unsigned char)(bits >> (56 - 8 * i));
  ud_sha256_block(s, s->buf);
  for (i = 0; i < 32; i++) out[i] = (unsigned char)(s->h[i / 4] >> (24 - 8 * (i % 4)));
}

// ---- raw inflate (RFC 1951) ----
// Into a buffer of its own size (a chunk's raw_len): what refers back reaches only what this stream made.

enum { UD_FAST = 10 };  // bits a code is looked up by at once; a longer one is walked bit by bit

typedef struct {
  // fast[bits]: symbol << 4 | length, 0 for a longer code (or none)
  uint16_t fast[1 << UD_FAST];
  int16_t count[16];  // codes of each length
  int16_t sym[288];   // symbols in canonical order
} ud_huff;

typedef struct {
  const unsigned char *in;
  size_t pos, end;
  uint64_t bits;
  int nbits;
} ud_bitin;

static void ud_fill(ud_bitin *b) {
  while (b->nbits <= 56 && b->pos < b->end) {
    b->bits |= (uint64_t)b->in[b->pos++] << b->nbits;
    b->nbits += 8;
  }
}

// n (≤ 32) bits, or -1 when the stream ends first
static int64_t ud_getbits(ud_bitin *b, int n) {
  uint64_t v;
  if (b->nbits < n) ud_fill(b);
  if (b->nbits < n) return -1;
  v = b->bits & (((uint64_t)1 << n) - 1);
  b->bits >>= n;
  b->nbits -= n;
  return (int64_t)v;
}

// a code from lengths: 0, or -1 when they are more than a code can be (an incomplete one is taken: what is not in it
// is refused as it is met)
static int ud_build(ud_huff *h, const unsigned char *len, int n) {
  int16_t offs[16];
  int i, left = 1;
  memset(h->count, 0, sizeof h->count);
  memset(h->fast, 0, sizeof h->fast);
  for (i = 0; i < n; i++) h->count[len[i]]++;
  h->count[0] = 0;
  for (i = 1; i < 16; i++) {
    left <<= 1;
    left -= h->count[i];
    if (left < 0) return -1;
  }
  offs[1] = 0;
  for (i = 1; i < 15; i++) offs[i + 1] = (int16_t)(offs[i] + h->count[i]);
  for (i = 0; i < n; i++)
    if (len[i]) h->sym[offs[len[i]]++] = (int16_t)i;
  {
    // the short codes in the table, by their bits as they come (reversed)
    int code = 0, k = 0, l;
    for (l = 1; l < 16; l++) {
      int c;
      for (c = 0; c < h->count[l]; c++, k++, code++) {
        if (l <= UD_FAST) {
          int r = 0, j, step;
          for (j = 0; j < l; j++) r |= ((code >> j) & 1) << (l - 1 - j);
          for (step = r; step < (1 << UD_FAST); step += 1 << l) h->fast[step] = (uint16_t)(h->sym[k] << 4 | l);
        }
      }
      code <<= 1;
    }
  }
  return 0;
}

// the next symbol, or -1 (the stream ends, or a code not in it)
static int ud_decode(ud_bitin *b, const ud_huff *h) {
  uint16_t e;
  int code = 0, first = 0, index = 0, l;
  if (b->nbits < 15) ud_fill(b);
  e = h->fast[b->bits & ((1u << UD_FAST) - 1)];
  if (e) {
    int n = e & 15;
    if (n > b->nbits) return -1;
    b->bits >>= n;
    b->nbits -= n;
    return e >> 4;
  }
  // canonically, a bit at a time
  for (l = 1; l < 16; l++) {
    int64_t bit = ud_getbits(b, 1);
    int count = h->count[l];
    if (bit < 0) return -1;
    code |= (int)bit;
    if (code - count < first) return h->sym[index + (code - first)];
    index += count;
    first += count;
    first <<= 1;
    code <<= 1;
  }
  return -1;
}

static const uint16_t ud_len_base[29] = {3,  4,  5,  6,  7,  8,  9,  10, 11,  13,  15,  17,  19,  23, 27,
                                          31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
static const unsigned char ud_len_extra[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2,
                                               2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
static const uint16_t ud_dist_base[30] = {1,   2,   3,   4,   5,   7,    9,    13,   17,   25,   33,   49,   65,    97,    129,
                                           193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
static const unsigned char ud_dist_extra[30] = {0, 0, 0, 0, 1, 1, 2, 2,  3,  3,  4,  4,  5,  5,  6,
                                                6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};

typedef struct {
  ud_huff lit, dist;
  unsigned char lens[19 + 286 + 30];  // the code lengths' code's, then the literals' and distances'
} ud_inflate_mem;

static const char *ud_codes(ud_bitin *b, const ud_inflate_mem *m, unsigned char *out, size_t cap, size_t *o) {
  for (;;) {
    int s = ud_decode(b, &m->lit);
    if (s < 0) return "a deflate stream is cut short or holds a code it does not have";
    if (s < 256) {
      if (*o >= cap) return "a chunk inflates to more than its raw_len";
      out[(*o)++] = (unsigned char)s;
    } else if (s == 256) {
      return NULL;
    } else {
      int64_t e;
      size_t len, dist, i;
      int d;
      s -= 257;
      if (s >= 29) return "a deflate stream holds a length code that is none";
      e = ud_getbits(b, ud_len_extra[s]);
      if (e < 0) return "a deflate stream is cut short";
      len = ud_len_base[s] + (size_t)e;
      d = ud_decode(b, &m->dist);
      if (d < 0) return "a deflate stream is cut short or holds a code it does not have";
      if (d >= 30) return "a deflate stream holds a distance code that is none";
      e = ud_getbits(b, ud_dist_extra[d]);
      if (e < 0) return "a deflate stream is cut short";
      dist = ud_dist_base[d] + (size_t)e;
      if (dist > *o) return "a deflate stream refers back before its start";
      if (len > cap - *o) return "a chunk inflates to more than its raw_len";
      for (i = 0; i < len; i++, (*o)++) out[*o] = out[*o - dist];
    }
  }
}

// The raw deflate stream in[0..n) inflated into out (at most cap bytes): NULL, its size in *made and how many of in's
// bytes it took in *took; or why not.
UD_FN const char *ud_inflate(const unsigned char *in, size_t n, unsigned char *out, size_t cap, size_t *made,
                             size_t *took) {
  static const unsigned char order[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
  ud_bitin b;
  size_t o = 0;
  const char *why = NULL;
  int last = 0;
  ud_inflate_mem *m = (ud_inflate_mem *)malloc(sizeof *m);
  if (!m) return "out of memory";
  b.in = in, b.pos = 0, b.end = n, b.bits = 0, b.nbits = 0;
  while (!last && !why) {
    int64_t head = ud_getbits(&b, 3);
    if (head < 0) {
      why = "a deflate stream is cut short";
      break;
    }
    last = (int)(head & 1);
    switch ((int)(head >> 1)) {
      case 0: {  // stored: from the next byte, LEN, ~LEN, LEN bytes
        size_t len;
        // (the rest of this byte let go, the whole bytes read ahead given back)
        b.pos -= (size_t)(b.nbits / 8);
        b.bits = 0, b.nbits = 0;
        if (b.end - b.pos < 4) {
          why = "a deflate stream is cut short";
          break;
        }
        len = (size_t)in[b.pos] | (size_t)in[b.pos + 1] << 8;
        if ((len ^ ((size_t)in[b.pos + 2] | (size_t)in[b.pos + 3] << 8)) != 0xffff) {
          why = "a stored block's length is not what its complement says";
          break;
        }
        b.pos += 4;
        if (b.end - b.pos < len) {
          why = "a deflate stream is cut short";
          break;
        }
        if (len > cap - o) {
          why = "a chunk inflates to more than its raw_len";
          break;
        }
        memcpy(out + o, in + b.pos, len);
        o += len;
        b.pos += len;
        break;
      }
      case 1: {  // the fixed codes
        int i;
        for (i = 0; i < 144; i++) m->lens[i] = 8;
        for (; i < 256; i++) m->lens[i] = 9;
        for (; i < 280; i++) m->lens[i] = 7;
        for (; i < 288; i++) m->lens[i] = 8;
        ud_build(&m->lit, m->lens, 288);
        for (i = 0; i < 30; i++) m->lens[i] = 5;
        ud_build(&m->dist, m->lens, 30);
        why = ud_codes(&b, m, out, cap, &o);
        break;
      }
      case 2: {  // the codes it says
        int64_t hlit = ud_getbits(&b, 5), hdist = ud_getbits(&b, 5), hclen = ud_getbits(&b, 4);
        int nlit, ndist, i;
        if (hclen < 0) {
          why = "a deflate stream is cut short";
          break;
        }
        nlit = (int)hlit + 257, ndist = (int)hdist + 1;
        if (nlit > 286 || ndist > 30) {
          why = "a deflate block says more codes than there are";
          break;
        }
        memset(m->lens, 0, 19);
        for (i = 0; i < (int)hclen + 4; i++) {
          int64_t l = ud_getbits(&b, 3);
          if (l < 0) break;
          m->lens[order[i]] = (unsigned char)l;
        }
        if (i < (int)hclen + 4) {
          why = "a deflate stream is cut short";
          break;
        }
        if (ud_build(&m->lit, m->lens, 19) != 0) {
          why = "a deflate block's code lengths' code is more than a code";
          break;
        }
        for (i = 0; i < nlit + ndist && !why;) {
          int s = ud_decode(&b, &m->lit);
          int64_t r;
          int times;
          unsigned char what = 0;
          if (s < 0) {
            why = "a deflate stream is cut short or holds a code it does not have";
          } else if (s < 16) {
            m->lens[19 + i++] = (unsigned char)s;
          } else {
            if (s == 16) {
              if (i == 0) {
                why = "a deflate block repeats a length before any";
                break;
              }
              what = m->lens[19 + i - 1];
              r = ud_getbits(&b, 2), times = 3;
            } else if (s == 17) {
              r = ud_getbits(&b, 3), times = 3;
            } else {
              r = ud_getbits(&b, 7), times = 11;
            }
            if (r < 0) {
              why = "a deflate stream is cut short";
              break;
            }
            times += (int)r;
            if (i + times > nlit + ndist) {
              why = "a deflate block's lengths run past its codes";
              break;
            }
            while (times--) m->lens[19 + i++] = what;
          }
        }
        if (why) break;
        if (m->lens[19 + 256] == 0) {
          why = "a deflate block has no end code";
          break;
        }
        if (ud_build(&m->lit, m->lens + 19, nlit) != 0 || ud_build(&m->dist, m->lens + 19 + nlit, ndist) != 0) {
          why = "a deflate block's lengths are more than a code";
          break;
        }
        why = ud_codes(&b, m, out, cap, &o);
        break;
      }
      default:
        why = "a deflate block of a kind that is none";
    }
  }
  free(m);
  if (why) return why;
  *made = o;
  *took = b.pos - (size_t)(b.nbits / 8);
  return NULL;
}

// ---- the delta ----

// One old file by its path (relative, '/' between names, UTF-8): its bytes in a buffer of malloc's (the applier frees
// it) and their count, or NULL when it cannot be read.
typedef unsigned char *(*ud_read_fn)(void *ctx, const char *path, size_t *size);
// Made bytes, in order: 1 when written.
typedef int (*ud_write_fn)(void *ctx, const unsigned char *bytes, size_t n);

enum { UD_CHUNK_MAX = 1 << 20 };

typedef struct {
  const unsigned char *d;
  size_t n, at;
} ud_reader;

static int ud_take(ud_reader *r, size_t k, const unsigned char **p) {
  if (r->n - r->at < k) return 0;
  *p = r->d + r->at;
  r->at += k;
  return 1;
}

static uint64_t ud_le(const unsigned char *p, int k) {
  uint64_t v = 0;
  int i;
  for (i = k - 1; i >= 0; i--) v = v << 8 | p[i];
  return v;
}

// a path an applier may read (as scripts/delta.ts's checkPath): relative, UTF-8, '/' between names, none of them empty
// or "..", no drive's letter before it ("C:"), no backslash or NUL
static int ud_path_safe(const unsigned char *p, size_t n) {
  size_t i, from = 0;
  if (n == 0) return 0;
  if (n >= 2 && p[1] == ':' && ((p[0] | 0x20) >= 'a' && (p[0] | 0x20) <= 'z')) return 0;
  for (i = 0; i <= n; i++) {
    if (i == n || p[i] == '/') {
      size_t k = i - from;
      if (k == 0 || (k == 2 && p[from] == '.' && p[from + 1] == '.')) return 0;
      from = i + 1;
    } else if (p[i] == '\\' || p[i] == 0) {
      return 0;
    }
  }
  // UTF-8, well formed (no overlong form, surrogate or past U+10FFFF)
  for (i = 0; i < n;) {
    unsigned c = p[i];
    size_t k = c < 0x80 ? 0 : (c & 0xe0) == 0xc0 ? 1 : (c & 0xf0) == 0xe0 ? 2 : (c & 0xf8) == 0xf0 ? 3 : 4;
    unsigned v, min;
    size_t j;
    if (k == 4 || n - i <= k) return 0;
    v = k == 0 ? c : k == 1 ? (c & 0x1f) : k == 2 ? (c & 0x0f) : (c & 0x07);
    for (j = 1; j <= k; j++) {
      if ((p[i + j] & 0xc0) != 0x80) return 0;
      v = v << 6 | (p[i + j] & 0x3f);
    }
    min = k == 0 ? 0 : k == 1 ? 0x80 : k == 2 ? 0x800 : 0x10000;
    if (v < min || v > 0x10ffff || (v >= 0xd800 && v < 0xe000)) return 0;
    i += k + 1;
  }
  return 1;
}

// numbers are kept below 2^53 (scripts/delta.ts reads them as JavaScript's): an i64 in [-2^53, 2^53)
static int ud_i64_fits(uint64_t v) { return v < ((uint64_t)1 << 53) || v >= (uint64_t)0 - ((uint64_t)1 << 53); }

// the bsdiff stream, taken a piece at a time (a record may span chunks)
typedef struct {
  const unsigned char *old;
  uint64_t old_size, made_size, o, p;  // p wraps: "before the old blob" is past its end as well
  uint64_t left;                        // of this record's diff (state 1) or extra (state 2)
  uint64_t extra;                       // the extra after the diff
  int state;                            // 0 a record's 24 bytes, 1 diff, 2 extra
  unsigned char head[24];
  int have;
  ud_write_fn write;
  void *wctx;
  unsigned char buf[1 << 16];
} ud_patch;

static const char *ud_patch_take(ud_patch *s, const unsigned char *b, size_t n) {
  while (n > 0) {
    if (s->state == 0) {
      size_t k = (size_t)(24 - s->have) < n ? (size_t)(24 - s->have) : n;
      int64_t x, y;
      if (s->o == s->made_size) return "the bsdiff stream goes on after made_size";
      memcpy(s->head + s->have, b, k);
      s->have += (int)k, b += k, n -= k;
      if (s->have < 24) break;
      s->have = 0;
      if (!ud_i64_fits(ud_le(s->head, 8)) || !ud_i64_fits(ud_le(s->head + 8, 8)) || !ud_i64_fits(ud_le(s->head + 16, 8)))
        return "a bsdiff record's number is too large";
      x = (int64_t)ud_le(s->head, 8), y = (int64_t)ud_le(s->head + 8, 8);
      if (x < 0 || y < 0) return "a bsdiff record says a negative length";
      if ((uint64_t)x > s->made_size - s->o || (uint64_t)y > s->made_size - s->o - (uint64_t)x)
        return "a bsdiff record makes more than made_size";
      s->extra = (uint64_t)y;
      s->state = x ? 1 : y ? 2 : 0;
      s->left = x ? (uint64_t)x : s->extra;
      // (z: the old blob's place moved once the record is done; as no record is empty but the last, at once is the same)
      if (s->state == 0) s->p += ud_le(s->head + 16, 8);
    } else if (s->state == 1) {
      size_t k = s->left < (uint64_t)n ? (size_t)s->left : n, i;
      if (k > sizeof s->buf) k = sizeof s->buf;
      for (i = 0; i < k; i++, s->p++) s->buf[i] = (unsigned char)(b[i] + (s->p < s->old_size ? s->old[s->p] : 0));
      if (!s->write(s->wctx, s->buf, k)) return "the made package could not be written";
      s->o += k, s->left -= k, b += k, n -= k;
      if (s->left == 0) {
        s->left = s->extra;
        s->state = s->left ? 2 : 0;
        if (s->state == 0) s->p += ud_le(s->head + 16, 8);
      }
    } else {
      size_t k = s->left < (uint64_t)n ? (size_t)s->left : n;
      if (!s->write(s->wctx, b, k)) return "the made package could not be written";
      s->o += k, s->left -= k, b += k, n -= k;
      if (s->left == 0) {
        s->state = 0;
        s->p += ud_le(s->head + 16, 8);
      }
    }
  }
  return NULL;
}

// The delta d[0..n) applied to the old files `read` gives, what it makes given to `write` in order. made_size_wanted:
// the size the made package must be (what the feed says), 0 for whatever the delta says. NULL when it is all made
// (its SHA-256 is still the caller's to check), else why not (nothing made yet where the old files are not the ones it
// is from).
UD_FN const char *ud_apply(const unsigned char *d, size_t n, ud_read_fn read, void *rctx, ud_write_fn write, void *wctx,
                           uint64_t made_size_wanted) {
  ud_reader r;
  const unsigned char *p;
  uint32_t n_files, i;
  size_t files_at;
  uint64_t old_size, made_size, at = 0;
  unsigned char old_sha[32], got[32];
  unsigned char *old = NULL, *raw = NULL;
  ud_patch *s = NULL;
  ud_sha256 sha;
  const char *why = NULL;
  r.d = d, r.n = n, r.at = 0;
  if (!ud_take(&r, 8, &p) || memcmp(p, "SFDELTA1", 8) != 0) return "not a delta (SFDELTA1)";
  if (!ud_take(&r, 4, &p)) return "the delta is cut short";
  n_files = (uint32_t)ud_le(p, 4);
  if (n_files == 0) return "not a delta of files (n_files 0)";
  files_at = r.at;
  for (i = 0; i < n_files; i++) {
    size_t len;
    if (!ud_take(&r, 2, &p)) return "the delta is cut short";
    len = (size_t)ud_le(p, 2);
    if (!ud_take(&r, len, &p)) return "the delta is cut short";
    if (!ud_path_safe(p, len)) return "the delta names an unsafe path";
  }
  if (!ud_take(&r, 4, &p)) return "the delta is cut short";
  if (ud_le(p, 4) != 0) return "not a delta of files (n_inflate)";
  if (!ud_take(&r, 8, &p)) return "the delta is cut short";
  old_size = ud_le(p, 8);
  if (!ud_take(&r, 32, &p)) return "the delta is cut short";
  memcpy(old_sha, p, 32);
  if (!ud_take(&r, 4, &p)) return "the delta is cut short";
  if (ud_le(p, 4) != 0) return "not a delta of files (n_deflate)";
  if (!ud_take(&r, 8, &p)) return "the delta is cut short";
  made_size = ud_le(p, 8);
  if (made_size_wanted && made_size != made_size_wanted) return "the delta makes another size than the feed says";
  if (old_size >= (uint64_t)1 << 53 || made_size >= (uint64_t)1 << 53) return "the delta's header has a number too large";
  if (old_size != (uint64_t)(size_t)old_size || old_size >= (uint64_t)1 << 40) return "the delta's old_size is too big";

  // the old blob, checked
  old = (unsigned char *)malloc(old_size ? (size_t)old_size : 1);
  if (!old) return "out of memory for the old files";
  ud_sha256_init(&sha);
  {
    size_t q = files_at;
    char *path = (char *)malloc(65536);
    if (!path) why = "out of memory";
    for (i = 0; i < n_files && !why; i++) {
      size_t len = (size_t)ud_le(d + q, 2), size = 0;
      unsigned char *f;
      memcpy(path, d + q + 2, len);
      path[len] = 0;
      q += 2 + len;
      f = read(rctx, path, &size);
      if (!f) {
        why = "an old file could not be read";
      } else if (size > old_size - at) {
        why = "the old files are more than old_size";
      } else {
        memcpy(old + at, f, size);
        ud_sha256_update(&sha, f, size);
        at += size;
      }
      free(f);
    }
    free(path);
  }
  if (!why && at != old_size) why = "the old files are not old_size";
  if (!why) {
    ud_sha256_final(&sha, got);
    if (memcmp(got, old_sha, 32) != 0) why = "the old files are not the ones the delta is from (SHA-256)";
  }

  // the chunks, inflated and patched one at a time
  if (!why) {
    raw = (unsigned char *)malloc(UD_CHUNK_MAX);
    s = (ud_patch *)calloc(1, sizeof *s);
    if (!raw || !s) why = "out of memory";
  }
  if (!why) {
    s->old = old, s->old_size = old_size, s->made_size = made_size;
    s->write = write, s->wctx = wctx;
    for (;;) {
      uint32_t raw_len, packed_len;
      size_t made = 0, took = 0;
      if (!ud_take(&r, 8, &p)) {
        why = "the delta ends without its end chunk";
        break;
      }
      raw_len = (uint32_t)ud_le(p, 4);
      packed_len = (uint32_t)ud_le(p + 4, 4);
      if (raw_len == 0) {
        if (packed_len != 0 || r.at != r.n) why = "the delta goes on after its end chunk";
        break;
      }
      if (raw_len > UD_CHUNK_MAX) {
        why = "a chunk is more than 1 MiB";
        break;
      }
      if (!ud_take(&r, packed_len, &p)) {
        why = "the delta is cut short";
        break;
      }
      why = ud_inflate(p, packed_len, raw, raw_len, &made, &took);
      if (!why && made != raw_len) why = "a chunk inflates to less than its raw_len";
      if (!why && took != packed_len) why = "a chunk holds more than its deflate stream";
      if (!why) why = ud_patch_take(s, raw, made);
      if (why) break;
    }
    if (!why && (s->o != made_size || s->state != 0 || s->have != 0)) why = "the bsdiff stream ends before made_size";
  }
  free(s);
  free(raw);
  free(old);
  return why;
}

#endif
