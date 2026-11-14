// An instance drawn in strips (scissor rectangles) that leave out where what it writes changes nothing: a shadow's
// inside where it is only outside its box (kind 2, 12 > 0: zero there), a ground's inside where it has only its border
// (kind 0, no colour: zero between its edges), and a shadow's inside where the box it is under, the instance right
// after it, writes over it whole (kind 0, opaque, the same clip: what the shadow wrote there is gone). Cut around one
// rectangle, a ring with large corners keeps most of what it shades for nothing; so it is cut into bands of rows,
// each drawing only the columns outside where its inside certainly is (MyGo's gpu/bands.go): what is shaded grows
// with the ring's length, not its area. The bands across its corners are as many as pay for their draw calls
// (MB_BAND_COST). A large ground of one colour is drawn in nine pieces, the cross between its corners by a flat
// pipeline (mb_pieces). The same quad drawn, only cut by the scissor: each pixel drawn is the pixel drawn whole, to the
// byte (scripts/render_dl.sh render_strips: MBUI_STRIPS=0 draws every instance whole). The web's renderer
// (web/host.js) draws every instance whole.
//
// An inside's corners: a corner of radius r as smooth as its box has room for (corner.sl mb_sd_box), wholly smooth
// (room 1.25 r or more), lies outside the circle of its R (1.25 r) about the same centre (a superellipse holds its
// circle), so the circle's rounded rect is inside the shape; one less smooth eases into its edges (a capsule's end,
// mb_capsule_tail) and is not cut so.

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// what a draw call of its own costs, in pixels shaded (MyGo's bandCost)
#define MB_BAND_COST 4096
// what a piece drawn of its own costs, in pixels the flat pipeline draws instead of the shader (MyGo's pieceCost)
#define MB_PIECE_COST 16384
// how far in, in pixels, past the half a pixel that its edge's cover reaches, a pixel is taken to be inside
#define MB_BAND_MARGIN 2.0f
// the fewest rows a band across corners has
#define MB_BAND_ROWS 8
// the most strips: two a band, the bands across the corners 32 at the top and at the foot, and three more
#define MB_STRIPS 140

// a strip, in pixels from the target's top left; `flat`: drawn by the flat pipeline (its colour, nothing worked out)
typedef struct {
  int x0, y0, x1, y1, flat;
} MBStrip;

static inline MBStrip mb_strip(int x0, int y0, int x1, int y1) {
  MBStrip s = {x0, y0, x1, y1, 0};
  return s;
}

// A rounded rect in pixels: x0 y0 x1 y1, its corners' circles' radii (top left, top right, bottom right, bottom left).
typedef struct {
  float x0, y0, x1, y1, r[4];
} MBRound;

// The columns `s`, shrunk by t, covers at row y: 0 none.
static int mb_round_span(const MBRound *s, float y, float t, float *l, float *r) {
  float x0 = s->x0 + t, y0 = s->y0 + t, x1 = s->x1 - t, y1 = s->y1 - t;
  if (y < y0 || y > y1 || x1 <= x0) return 0;
  int top = y < (s->y0 + s->y1) * 0.5f;
  float left = top ? s->r[0] : s->r[3], right = top ? s->r[1] : s->r[2];
  float dy = top ? y - y0 : y1 - y;
  float in[2];
  float radii[2] = {left, right};
  for (int k = 0; k < 2; k++) {
    float rho = radii[k] - t;
    if (rho < 0) rho = 0;
    in[k] = 0;
    if (dy < rho) {
      float d = rho - dy;
      in[k] = rho - sqrtf(fmaxf(rho * rho - d * d, 0));
    }
  }
  *l = x0 + in[0];
  *r = x1 - in[1];
  return *l < *r;
}

// The columns `s`, shrunk by t, covers at every row from y0 to y1 (as it is convex: those it covers at both).
static int mb_round_narrowest(const MBRound *s, float y0, float y1, float t, float *l, float *r) {
  float l0, r0, l1, r1;
  int a = mb_round_span(s, y0, t, &l0, &r0), b = mb_round_span(s, y1, t, &l1, &r1);
  *l = fmaxf(l0, l1);
  *r = fminf(r0, r1);
  return a && b && *l < *r;
}

static long mb_strip_area(MBStrip s) {
  return s.x1 > s.x0 && s.y1 > s.y0 ? (long)(s.x1 - s.x0) * (s.y1 - s.y0) : 0;
}

static MBStrip mb_strip_meet(MBStrip a, MBStrip b) {
  MBStrip m = {a.x0 > b.x0 ? a.x0 : b.x0, a.y0 > b.y0 ? a.y0 : b.y0, a.x1 < b.x1 ? a.x1 : b.x1, a.y1 < b.y1 ? a.y1 : b.y1,
               0};
  return m;
}

// The inside of the box of instance `a` (its rect moved up by `up`, shrunk by `in`), in pixels: its corners as
// corner.sl's mb_sd_box draws them (36-39), each wholly smooth or square; 0 where one is not.
static int mb_inside(const float *a, float up, float in, float scale, MBRound *o) {
  float hw = a[2] * 0.5f, hh = a[3] * 0.5f;
  float room = fminf(hw, hh);
  if (room <= in) return 0;
  for (int i = 0; i < 4; i++) {
    float rr = fminf(a[36 + i], room);
    if (rr <= 0) {
      o->r[i] = 0;
      continue;
    }
    // (corner.sl mb_smoothness: wholly smooth, R a quarter longer)
    if (room - rr < 0.25f * rr) return 0;
    o->r[i] = fminf(rr * 1.25f, room) * scale;
  }
  o->x0 = a[0] * scale;
  o->y0 = (a[1] - up) * scale;
  o->x1 = (a[0] + a[2]) * scale;
  o->y1 = (a[1] - up + a[3]) * scale;
  // shrunk by `in` (points): its corners' circles too
  float t = in * scale;
  o->x0 += t; o->y0 += t; o->x1 -= t; o->y1 -= t;
  for (int i = 0; i < 4; i++) o->r[i] = fmaxf(o->r[i] - t, 0);
  return o->x0 < o->x1 && o->y0 < o->y1;
}

// Whether instances a and b are cut alike: the same clip, outer clip, fades and turn (16-19, 24-35, 40-59).
static int mb_cut_alike(const float *a, const float *b) {
  for (int k = 16; k < 60; k++) {
    if (k >= 20 && k < 24) continue;
    if (k >= 36 && k < 40) continue;
    if (a[k] != b[k]) return 0;
  }
  return 1;
}

// The quad of instance `a` as the vertex shader grows it (src/host: `grow`), in whole pixels, cut to `to` and to its
// clip's rect (where it is not turned).
static MBStrip mb_whole(const float *a, int kind, float scale, MBStrip to) {
  float grow = kind == 2 ? a[7] * 3.0f + 2.0f : 1.0f;
  MBStrip whole = mb_strip((int)floorf((a[0] - grow) * scale), (int)floorf((a[1] - grow) * scale),
                           (int)ceilf((a[0] + a[2] + grow) * scale), (int)ceilf((a[1] + a[3] + grow) * scale));
  if (a[35] < 0.5f) {
    MBStrip clip = mb_strip((int)floorf(fmaxf(a[16] * scale, -1e8f)), (int)floorf(fmaxf(a[17] * scale, -1e8f)),
                            (int)ceilf(fminf(a[18] * scale, 1e8f)), (int)ceilf(fminf(a[19] * scale, 1e8f)));
    whole = mb_strip_meet(whole, clip);
  }
  return mb_strip_meet(whole, to);
}

// A ground of one colour (kind 0, no border, no notch) in nine pieces: where it is certainly covered whole and none of
// its corners' curves reaches (its cover 1: the rows between its corners, the columns between them, within its edges
// by MB_BAND_MARGIN), what the shader writes is its colour alone, (col.rgb, 1) col.a, as cover 1 and a clip of straight
// edges keep it (none rounded, no outer, nothing fading): that cross drawn flat (the flat pipeline: the same colour,
// nothing worked out), the eight pieces round it as before (MyGo's gpu/corners.go). Into `out` as mb_bands.
static int mb_pieces(const float *a, float scale, MBStrip to, MBStrip out[MB_STRIPS]) {
  for (int k = 0; k < 4; k++)
    if (a[24 + k] > 0 || a[44 + k] > 0) return -1;
  if (a[53] > 0 || a[55] > 0 || a[57] > 0 || a[59] > 0 || a[35] > 0.5f) return -1;
  MBStrip whole = mb_whole(a, 0, scale, to);
  // each corner's reach, R (mb_inside), in pixels: wholly smooth or square
  float hw = a[2] * 0.5f, hh = a[3] * 0.5f, room = fminf(hw, hh), R[4];
  for (int i = 0; i < 4; i++) {
    float rr = fminf(a[36 + i], room);
    if (rr <= 0) {
      R[i] = 0;
      continue;
    }
    if (room - rr < 0.25f * rr) return -1;
    R[i] = fminf(rr * 1.25f, room) * scale;
  }
  const float m = MB_BAND_MARGIN;
  float x0 = a[0] * scale, y0 = a[1] * scale, x1 = (a[0] + a[2]) * scale, y1 = (a[1] + a[3]) * scale;
  // within its clip (its pixels' middles inside it by a pixel) and `to`
  MBStrip in = mb_strip_meet(mb_strip((int)ceilf(a[16] * scale) + 1, (int)ceilf(a[17] * scale) + 1,
                                      (int)floorf(a[18] * scale) - 1, (int)floorf(a[19] * scale) - 1), to);
  int c0 = whole.x0, c5 = whole.x1, r0 = whole.y0, r5 = whole.y1;
  int c1 = (int)ceilf(x0 + m), c4 = (int)floorf(x1 - m), r1 = (int)ceilf(y0 + m), r4 = (int)floorf(y1 - m);
  if (c1 < in.x0) c1 = in.x0;
  if (c4 > in.x1) c4 = in.x1;
  if (r1 < in.y0) r1 = in.y0;
  if (r4 > in.y1) r4 = in.y1;
  if (c1 < c0 || r1 < r0 || c4 > c5 || r4 > r5 || c1 >= c4 || r1 >= r4) return -1;
  // the columns between the corners (the top's and the foot's), the rows between them (the left's and the right's)
  int c2 = (int)ceilf(x0 + fmaxf(R[0], R[3])), c3 = (int)floorf(x1 - fmaxf(R[1], R[2]));
  int r2 = (int)ceilf(y0 + fmaxf(R[0], R[1])), r3 = (int)floorf(y1 - fmaxf(R[3], R[2]));
  if (c2 < c1) c2 = c1;
  if (c3 > c4) c3 = c4;
  if (r2 < r1) r2 = r1;
  if (r3 > r4) r3 = r4;
  if (c2 > c3) c2 = c3 = (c2 + c3) / 2 < c1 ? c1 : (c2 + c3) / 2 > c4 ? c4 : (c2 + c3) / 2;
  if (r2 > r3) r2 = r3 = (r2 + r3) / 2 < r1 ? r1 : (r2 + r3) / 2 > r4 ? r4 : (r2 + r3) / 2;
  MBStrip p[11] = {
      mb_strip(c2, r1, c3, r2), mb_strip(c1, r2, c4, r3), mb_strip(c2, r3, c3, r4),
      mb_strip(c0, r0, c5, r1), mb_strip(c0, r1, c2, r2), mb_strip(c3, r1, c5, r2), mb_strip(c0, r2, c1, r3),
      mb_strip(c4, r2, c5, r3), mb_strip(c0, r3, c2, r4), mb_strip(c3, r3, c5, r4), mb_strip(c0, r4, c5, r5),
  };
  long flat = 0;
  int n = 0;
  for (int k = 0; k < 11; k++) {
    if (mb_strip_area(p[k]) == 0) continue;
    p[k].flat = k < 3;
    if (k < 3) flat += mb_strip_area(p[k]);
    out[n++] = p[k];
  }
  // (what the flat pipeline saves pays for the draw calls: MB_PIECE_COST)
  if (flat < (long)n * MB_PIECE_COST) return -1;
  return n;
}

// Whether instance i (of `count` in f) might be drawn in strips: what mb_bands looks at first.
static inline int mb_band_kind(const float *f, int32_t i) {
  int kind = (int)(f[(size_t)i * 60 + 5] + 0.5f);
  return kind == 0 || kind == 2;
}

// The strips instance i of `count` in f is drawn in, into `out`, cut to `to` (the target, or the part of it drawn
// again; pixels, from the top left): how many, or -1 where it is drawn whole (what it leaves out too little to pay for
// the draw calls, or nothing to leave out).
static int mb_bands(const float *f, int32_t i, int32_t count, float scale, MBStrip to, MBStrip out[MB_STRIPS]) {
  // (MBUI_STRIPS=0: every instance whole, the picture to compare with: scripts/render_dl.sh render_strips)
  static int off = -1;
  if (off < 0) {
    const char *e = getenv("MBUI_STRIPS");
    off = e && e[0] == '0';
  }
  if (off) return -1;
  const float *a = f + (size_t)i * 60;
  int kind = (int)(a[5] + 0.5f);
  // (nothing turned: its strips are where it is laid out)
  if (a[32] != 0 || a[20] != 0) return -1;
  MBRound hole;
  if (kind == 2) {
    if (a[12] > 0.5f) {
      // only outside its box, 13 above it: nothing inside the box
      if (!mb_inside(a, a[13], 0, scale, &hole)) return -1;
    } else {
      // under the box drawn right after it, opaque: what it writes inside that box written over whole (alpha 1,
      // cover 1: a clip of straight edges, no outer, nothing fading), its border as opaque, no notch
      if (i + 1 >= count) return -1;
      const float *b = a + 60;
      if ((int)(b[5] + 0.5f) != 0 || b[20] != 0 || b[11] != 1.0f || b[22] > 0) return -1;
      if (b[6] > 0 && b[15] != 1.0f) return -1;
      if (!mb_cut_alike(a, b)) return -1;
      for (int k = 0; k < 4; k++)
        if (b[24 + k] > 0 || b[44 + k] > 0) return -1;
      if (b[53] > 0 || b[55] > 0 || b[57] > 0 || b[59] > 0) return -1;
      if (!mb_inside(b, 0, 0, scale, &hole)) return -1;
    }
  } else if (kind == 0) {
    if (a[22] > 0) return -1;
    // a ground of one colour: in pieces, its middle flat (mb_pieces)
    if (a[11] > 0 && a[6] <= 0) return mb_pieces(a, scale, to, out);
    // only its border: nothing between its edges (fill 0, its border's cover whole)
    if (a[11] != 0 || a[6] <= 0) return -1;
    if (!mb_inside(a, 0, a[6], scale, &hole)) return -1;
  } else {
    return -1;
  }
  MBStrip whole = mb_whole(a, kind, scale, to);
  if (mb_strip_area(whole) <= MB_BAND_COST) return -1;
  const float m = MB_BAND_MARGIN;
  int top = whole.y0, bottom = whole.y1;
  int hTop = (int)ceilf(hole.y0 + m), hBottom = (int)floorf(hole.y1 - m);
  float rTop = fmaxf(hole.r[0], hole.r[1]), rBottom = fmaxf(hole.r[2], hole.r[3]);
  // what bands could leave out at most: the hole's rectangle; a hole takes four draw calls or more, three more than
  // drawing whole
  MBStrip hr = mb_strip((int)ceilf(hole.x0 + m), hTop, (int)floorf(hole.x1 - m), hBottom);
  if (mb_strip_area(mb_strip_meet(whole, hr)) <= 2 * MB_BAND_COST) return -1;
  int mTop = hTop + (int)ceilf(rTop), mBottom = hBottom - (int)ceilf(rBottom);
  if (mTop > mBottom) mTop = mBottom = (mTop + mBottom) / 2;
#define MB_CLAMP(y) ((y) < top ? top : (y) > bottom ? bottom : (y))
  hTop = MB_CLAMP(hTop);
  hBottom = MB_CLAMP(hBottom);
  mTop = MB_CLAMP(mTop);
  mBottom = MB_CLAMP(mBottom);
#undef MB_CLAMP
  MBStrip tryb[MB_STRIPS];
  long best = mb_strip_area(whole) + MB_BAND_COST, last = -1;
  int found = -1;
  int rows = mTop - hTop > hBottom - mBottom ? mTop - hTop : hBottom - mBottom;
  for (int k = 1; k <= 32 && (k == 1 || rows / k >= MB_BAND_ROWS); k *= 2) {
    int n = 0;
    long cost = 0;
    // a band of rows y0 to y1: all its columns, less those the hole covers at every row of it
    for (int s = 0; s < 2 * k + 3; s++) {
      int y0, y1;
      if (hTop >= hBottom) {
        if (s > 0) break;
        y0 = top; y1 = bottom;
      } else if (s == 0) {
        y0 = top; y1 = hTop;
      } else if (s <= k) {
        y0 = hTop + (mTop - hTop) * (s - 1) / k; y1 = hTop + (mTop - hTop) * s / k;
      } else if (s == k + 1) {
        y0 = mTop; y1 = mBottom;
      } else if (s <= 2 * k + 1) {
        int j = s - k - 2;
        y0 = mBottom + (hBottom - mBottom) * j / k; y1 = mBottom + (hBottom - mBottom) * (j + 1) / k;
      } else {
        y0 = hBottom; y1 = bottom;
      }
      if (y0 >= y1) continue;
      int hl = 0, hrr = 0;
      if (y0 >= hTop && y1 <= hBottom) {
        float l, r;
        if (mb_round_narrowest(&hole, (float)y0, (float)y1, m, &l, &r)) {
          hl = (int)ceilf(l);
          hrr = (int)floorf(r);
          if (hl < whole.x0) hl = whole.x0;
          if (hrr > whole.x1) hrr = whole.x1;
        }
      }
      MBStrip st[2];
      int ns = 0;
      if (hl >= hrr) {
        st[ns++] = mb_strip(whole.x0, y0, whole.x1, y1);
      } else {
        st[ns++] = mb_strip(whole.x0, y0, hl, y1);
        st[ns++] = mb_strip(hrr, y0, whole.x1, y1);
      }
      for (int q = 0; q < ns; q++) {
        if (mb_strip_area(st[q]) == 0) continue;
        tryb[n++] = st[q];
        cost += mb_strip_area(st[q]) + MB_BAND_COST;
      }
    }
    if (cost < best) {
      best = cost;
      found = n;
      memcpy(out, tryb, sizeof(MBStrip) * n);
    }
    if (last >= 0 && cost >= last) break;
    last = cost;
  }
  return found;
}
